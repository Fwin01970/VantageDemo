"""
LLM Provider Abstraction
=========================
One interface, four concrete implementations. The rest of the app never
needs to know which one actually ran — it just calls run_chat_turn() via
chat_fallback.py.

Same reasoning as the Databricks client: these use direct, stable REST
endpoints rather than each vendor's SDK, since we can't verify exact SDK
method signatures without hitting real credentials/a real local Ollama
install first.

MULTI-STEP TOOL CALLS: a model can legitimately need to call the data
tool more than once in a row before it has enough to answer — e.g. "loss
ratio of this year" first needs a query to find out what "this year"
even is, then a second query using that year. Each provider's chat()
returns a ChatResult with an opaque `history` blob (its own
provider-native shape — the orchestrator in chat_fallback.py never looks
inside it, just passes it back unchanged). continue_with_tool_result()
takes that same history, appends the tool's result, and returns a NEW
ChatResult — which may itself contain another tool_call. The
orchestrator loops on this until it gets a final text reply or hits a
safety cap.

TOOL-CALLING HONESTY NOTE: this was written and reasoned through
carefully against each vendor's documented API shape. The single-tool-
call path has now been run successfully against real Gemini + Databricks
credentials (confirmed in practice); the multi-step loop below is new
and, like the rest of this file, should be treated as unverified until
it's actually been exercised end-to-end.
"""
import json
import httpx


class LLMError(Exception):
    """Raised when a provider fails to produce a usable response —
    unreachable, bad credentials, unexpected response shape, etc."""
    pass


def _split_system(messages: list[dict]) -> tuple[str | None, list[dict]]:
    """Anthropic's and Gemini's APIs take the system prompt as a separate
    top-level field, not a role="system" message in the array (unlike
    OpenAI, which accepts it inline). This pulls a leading system
    message out, if present, so those providers can send it correctly."""
    if messages and messages[0].get("role") == "system":
        return messages[0]["content"], messages[1:]
    return None, messages


class ChatResult:
    """Result of one chat turn. Either `text` is set (a normal reply), or
    `tool_call` is set (the model wants to call our tool before it can
    answer) — never both.

    `history` is an opaque, provider-specific blob representing the full
    conversation-so-far in that provider's own native shape, already
    including the assistant's latest turn. It only matters if `tool_call`
    is set — that's what you pass back into continue_with_tool_result()
    to keep going. Callers outside this file should never inspect it."""
    def __init__(self, text: str | None = None, tool_call: dict | None = None, raw=None, history=None):
        self.text = text
        self.tool_call = tool_call  # {"name": str, "input": dict, "id": str|None}
        self.raw = raw
        self.history = history


class LLMProvider:
    name = "base"

    def generate(self, prompt: str, timeout_seconds: float = 15) -> str:
        raise NotImplementedError

    def chat(self, messages: list[dict], tools: list[dict] | None, timeout_seconds: float = 20) -> ChatResult:
        """messages: [{"role": "user"|"assistant", "content": str}, ...]
        tools: [{"name": str, "description": str, "parameters": {...JSON schema...}}] or None
        """
        raise NotImplementedError

    def continue_with_tool_result(
        self, history, tool_call: dict, tool_result_text: str,
        tools: list[dict] | None = None, timeout_seconds: float = 20,
    ) -> ChatResult:
        """Called after we've executed the tool the model asked for.
        Sends the tool's result back and returns the model's next
        ChatResult — which may be a final text reply, or ANOTHER
        tool_call if the model needs more data before it can answer.
        `tools` is passed again so the model can still choose to call
        the tool again; omit it (None) to force a final answer."""
        raise NotImplementedError


class OllamaProvider(LLMProvider):
    """Free, local, private. No API key needed.

    NOTE: does not support tool-calling in this implementation — Ollama's
    tool support varies by model and isn't consistent enough to rely on
    yet, so chat() here never returns a tool_call. This means when Ollama
    is the provider actually used, the chat assistant can still talk, but
    cannot pull live company data mid-conversation — the UI should make
    this visible rather than silently limiting capability.
    """
    name = "ollama"

    def __init__(self, base_url: str, model: str):
        self.base_url = base_url.rstrip("/")
        self.model = model

    def generate(self, prompt: str, timeout_seconds: float = 15) -> str:
        try:
            resp = httpx.post(
                f"{self.base_url}/api/generate",
                json={"model": self.model, "prompt": prompt, "stream": False},
                timeout=timeout_seconds,
            )
        except httpx.HTTPError as e:
            raise LLMError(f"Ollama unreachable: {e}")

        if resp.status_code != 200:
            raise LLMError(f"Ollama returned HTTP {resp.status_code}: {resp.text[:300]}")

        try:
            return resp.json()["response"]
        except (KeyError, ValueError) as e:
            raise LLMError(f"Unexpected Ollama response shape: {e}")

    def chat(self, messages: list[dict], tools: list[dict] | None, timeout_seconds: float = 20) -> ChatResult:
        # Flatten the conversation into one prompt — no tool support.
        prompt = "\n\n".join(f"{m['role'].upper()}: {m['content']}" for m in messages)
        prompt += "\n\nASSISTANT:"
        text = self.generate(prompt, timeout_seconds=timeout_seconds)
        return ChatResult(text=text)

    def continue_with_tool_result(self, history, tool_call, tool_result_text, tools=None, timeout_seconds=20):
        raise LLMError("Ollama provider does not support tool-calling")


class AnthropicProvider(LLMProvider):
    name = "anthropic"

    def __init__(self, api_key: str, model: str):
        self.api_key = api_key
        self.model = model

    def _headers(self):
        return {
            "x-api-key": self.api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        }

    def _tools_payload(self, tools: list[dict] | None):
        if not tools:
            return None
        return [
            {"name": t["name"], "description": t["description"], "input_schema": t["parameters"]}
            for t in tools
        ]

    def generate(self, prompt: str, timeout_seconds: float = 15) -> str:
        if not self.api_key:
            raise LLMError("No Anthropic API key configured")
        try:
            resp = httpx.post(
                "https://api.anthropic.com/v1/messages",
                headers=self._headers(),
                json={
                    "model": self.model,
                    "max_tokens": 300,
                    "messages": [{"role": "user", "content": prompt}],
                },
                timeout=timeout_seconds,
            )
        except httpx.HTTPError as e:
            raise LLMError(f"Anthropic unreachable: {e}")

        if resp.status_code != 200:
            raise LLMError(f"Anthropic returned HTTP {resp.status_code}: {resp.text[:300]}")

        try:
            return resp.json()["content"][0]["text"]
        except (KeyError, IndexError, ValueError) as e:
            raise LLMError(f"Unexpected Anthropic response shape: {e}")

    def _call(self, system_text, conversation, tools, timeout_seconds) -> tuple[list, dict]:
        """Shared by chat() and continue_with_tool_result() — makes the
        actual request and returns (content_blocks, full_json)."""
        body = {"model": self.model, "max_tokens": 1024, "messages": conversation}
        if system_text:
            body["system"] = system_text
        tools_payload = self._tools_payload(tools)
        if tools_payload:
            body["tools"] = tools_payload

        try:
            resp = httpx.post(
                "https://api.anthropic.com/v1/messages", headers=self._headers(), json=body, timeout=timeout_seconds
            )
        except httpx.HTTPError as e:
            raise LLMError(f"Anthropic unreachable: {e}")

        if resp.status_code != 200:
            raise LLMError(f"Anthropic returned HTTP {resp.status_code}: {resp.text[:300]}")

        data = resp.json()
        return data.get("content", []), data

    def chat(self, messages: list[dict], tools: list[dict] | None, timeout_seconds: float = 20) -> ChatResult:
        if not self.api_key:
            raise LLMError("No Anthropic API key configured")

        system_text, conversation = _split_system(messages)
        content_blocks, _ = self._call(system_text, conversation, tools, timeout_seconds)

        tool_block = next((b for b in content_blocks if b.get("type") == "tool_use"), None)
        if tool_block:
            history = {"system": system_text, "conversation": conversation + [{"role": "assistant", "content": content_blocks}]}
            return ChatResult(
                tool_call={"name": tool_block["name"], "input": tool_block.get("input", {}), "id": tool_block["id"]},
                raw=content_blocks, history=history,
            )

        text = "".join(b.get("text", "") for b in content_blocks if b.get("type") == "text")
        return ChatResult(text=text, raw=content_blocks)

    def continue_with_tool_result(self, history, tool_call, tool_result_text, tools=None, timeout_seconds=20) -> ChatResult:
        # Anthropic's protocol: the assistant's tool_use turn is already
        # in `history["conversation"]` (chat()/the previous hop put it
        # there) — we just append a user turn with the matching
        # tool_result block, then call again. If `tools` is passed again,
        # the model may respond with ANOTHER tool_use instead of text.
        system_text = history.get("system")
        conversation = history["conversation"] + [
            {"role": "user", "content": [
                {"type": "tool_result", "tool_use_id": tool_call["id"], "content": tool_result_text}
            ]},
        ]
        content_blocks, _ = self._call(system_text, conversation, tools, timeout_seconds)

        tool_block = next((b for b in content_blocks if b.get("type") == "tool_use"), None)
        if tool_block:
            new_history = {"system": system_text, "conversation": conversation + [{"role": "assistant", "content": content_blocks}]}
            return ChatResult(
                tool_call={"name": tool_block["name"], "input": tool_block.get("input", {}), "id": tool_block["id"]},
                raw=content_blocks, history=new_history,
            )

        text = "".join(b.get("text", "") for b in content_blocks if b.get("type") == "text")
        return ChatResult(text=text, raw=content_blocks)


class OpenAIProvider(LLMProvider):
    name = "openai"

    def __init__(self, api_key: str, model: str):
        self.api_key = api_key
        self.model = model

    def _tools_payload(self, tools: list[dict] | None):
        if not tools:
            return None
        return [
            {"type": "function", "function": {"name": t["name"], "description": t["description"], "parameters": t["parameters"]}}
            for t in tools
        ]

    def generate(self, prompt: str, timeout_seconds: float = 15) -> str:
        if not self.api_key:
            raise LLMError("No OpenAI API key configured")
        try:
            resp = httpx.post(
                "https://api.openai.com/v1/chat/completions",
                headers={"Authorization": f"Bearer {self.api_key}"},
                json={"model": self.model, "messages": [{"role": "user", "content": prompt}]},
                timeout=timeout_seconds,
            )
        except httpx.HTTPError as e:
            raise LLMError(f"OpenAI unreachable: {e}")

        if resp.status_code != 200:
            raise LLMError(f"OpenAI returned HTTP {resp.status_code}: {resp.text[:300]}")

        try:
            return resp.json()["choices"][0]["message"]["content"]
        except (KeyError, IndexError, ValueError) as e:
            raise LLMError(f"Unexpected OpenAI response shape: {e}")

    def _call(self, full_messages: list[dict], tools: list[dict] | None, timeout_seconds: float):
        body = {"model": self.model, "messages": full_messages}
        tools_payload = self._tools_payload(tools)
        if tools_payload:
            body["tools"] = tools_payload
            body["tool_choice"] = "auto"

        try:
            resp = httpx.post(
                "https://api.openai.com/v1/chat/completions",
                headers={"Authorization": f"Bearer {self.api_key}"},
                json=body,
                timeout=timeout_seconds,
            )
        except httpx.HTTPError as e:
            raise LLMError(f"OpenAI unreachable: {e}")

        if resp.status_code != 200:
            raise LLMError(f"OpenAI returned HTTP {resp.status_code}: {resp.text[:300]}")

        return resp.json()["choices"][0]["message"]

    def chat(self, messages: list[dict], tools: list[dict] | None, timeout_seconds: float = 20) -> ChatResult:
        if not self.api_key:
            raise LLMError("No OpenAI API key configured")

        message = self._call(messages, tools, timeout_seconds)
        tool_calls = message.get("tool_calls")
        if tool_calls:
            call = tool_calls[0]
            try:
                args = json.loads(call["function"]["arguments"])
            except (ValueError, KeyError):
                args = {}
            history = messages + [message]
            return ChatResult(
                tool_call={"name": call["function"]["name"], "input": args, "id": call["id"]},
                raw=message, history=history,
            )

        return ChatResult(text=message.get("content", ""), raw=message)

    def continue_with_tool_result(self, history, tool_call, tool_result_text, tools=None, timeout_seconds=20) -> ChatResult:
        # OpenAI's protocol: `history` already ends with the assistant
        # message containing its tool_calls — append the matching
        # role="tool" result, then call again. Passing `tools` again
        # lets the model choose to call the tool a second time.
        full_messages = history + [
            {"role": "tool", "tool_call_id": tool_call["id"], "content": tool_result_text},
        ]
        message = self._call(full_messages, tools, timeout_seconds)
        tool_calls = message.get("tool_calls")
        if tool_calls:
            call = tool_calls[0]
            try:
                args = json.loads(call["function"]["arguments"])
            except (ValueError, KeyError):
                args = {}
            new_history = full_messages + [message]
            return ChatResult(
                tool_call={"name": call["function"]["name"], "input": args, "id": call["id"]},
                raw=message, history=new_history,
            )

        return ChatResult(text=message.get("content", ""), raw=message)


class GeminiProvider(LLMProvider):
    """
    Google Gemini — has a genuine free tier (no card required in most
    regions), useful as an actual-reachable fallback while OpenAI/
    Anthropic billing gets sorted out.

    The single-tool-call path (chat() -> tool_call -> continue_with_tool_
    result() -> final text) has now been confirmed working against a
    real account. Multi-step (continue_with_tool_result() itself
    returning another tool_call) is new and unverified until it's been
    seen to work end-to-end.
    """
    name = "gemini"

    def __init__(self, api_key: str, model: str):
        self.api_key = api_key
        self.model = model

    def _url(self, method: str) -> str:
        # Deliberately NOT ?key=... in the query string anymore — httpx
        # (and any proxy/log aggregator in between) logs the full request
        # URL, which put the live API key in plaintext in every log line
        # for every single call. Google's Gemini API accepts the key via
        # the x-goog-api-key header just as well; see _headers().
        return f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:{method}"

    def _headers(self) -> dict:
        return {"x-goog-api-key": self.api_key, "Content-Type": "application/json"}

    @staticmethod
    def _to_gemini_contents(messages: list[dict]) -> tuple[str | None, list[dict]]:
        """Gemini uses role 'model' instead of 'assistant', and takes the
        system prompt as a separate top-level field — same shape problem
        as Anthropic, different field name (systemInstruction)."""
        system_text = None
        contents = []
        for m in messages:
            if m["role"] == "system":
                system_text = m["content"]
                continue
            role = "model" if m["role"] == "assistant" else "user"
            contents.append({"role": role, "parts": [{"text": m["content"]}]})
        return system_text, contents

    def generate(self, prompt: str, timeout_seconds: float = 15) -> str:
        if not self.api_key:
            raise LLMError("No Gemini API key configured")
        try:
            resp = httpx.post(
                self._url("generateContent"),
                json={"contents": [{"role": "user", "parts": [{"text": prompt}]}]},
                headers=self._headers(),
                timeout=timeout_seconds,
            )
        except httpx.HTTPError as e:
            raise LLMError(f"Gemini unreachable: {e}")

        if resp.status_code != 200:
            raise LLMError(f"Gemini returned HTTP {resp.status_code}: {resp.text[:300]}")

        try:
            parts = resp.json()["candidates"][0]["content"]["parts"]
            return "".join(p.get("text", "") for p in parts)
        except (KeyError, IndexError, ValueError) as e:
            raise LLMError(f"Unexpected Gemini response shape: {e}")

    def _tools_payload(self, tools: list[dict] | None):
        if not tools:
            return None
        return [{
            "functionDeclarations": [
                {"name": t["name"], "description": t["description"], "parameters": t["parameters"]}
                for t in tools
            ]
        }]

    def _call(self, system_text, contents, tools, timeout_seconds):
        body: dict = {"contents": contents}
        if system_text:
            body["systemInstruction"] = {"parts": [{"text": system_text}]}
        tools_payload = self._tools_payload(tools)
        if tools_payload:
            body["tools"] = tools_payload

        try:
            resp = httpx.post(self._url("generateContent"), json=body, headers=self._headers(), timeout=timeout_seconds)
        except httpx.HTTPError as e:
            raise LLMError(f"Gemini unreachable: {e}")

        if resp.status_code != 200:
            raise LLMError(f"Gemini returned HTTP {resp.status_code}: {resp.text[:300]}")

        data = resp.json()
        try:
            candidate = data["candidates"][0]
        except (KeyError, IndexError) as e:
            raise LLMError(f"Unexpected Gemini response shape: {e}")
        return candidate, data

    def chat(self, messages: list[dict], tools: list[dict] | None, timeout_seconds: float = 20) -> ChatResult:
        if not self.api_key:
            raise LLMError("No Gemini API key configured")

        system_text, contents = self._to_gemini_contents(messages)
        candidate, _ = self._call(system_text, contents, tools, timeout_seconds)
        content = candidate.get("content", {})
        parts = content.get("parts", [])

        function_call_part = next((p for p in parts if "functionCall" in p), None)
        if function_call_part:
            fc = function_call_part["functionCall"]
            history = {"system": system_text, "contents": contents + [content]}
            return ChatResult(
                tool_call={"name": fc["name"], "input": fc.get("args", {}), "id": fc["name"]},
                raw=content, history=history,
            )

        text = "".join(p.get("text", "") for p in parts)
        return ChatResult(text=text, raw=content)

    def continue_with_tool_result(self, history, tool_call, tool_result_text, tools=None, timeout_seconds=20) -> ChatResult:
        system_text = history.get("system")
        contents = history["contents"] + [
            {"role": "user", "parts": [{
                "functionResponse": {"name": tool_call["name"], "response": {"result": tool_result_text}},
            }]},
        ]
        candidate, data = self._call(system_text, contents, tools, timeout_seconds)
        content = candidate.get("content", {})
        parts = content.get("parts", [])

        function_call_part = next((p for p in parts if "functionCall" in p), None)
        if function_call_part:
            fc = function_call_part["functionCall"]
            new_history = {"system": system_text, "contents": contents + [content]}
            return ChatResult(
                tool_call={"name": fc["name"], "input": fc.get("args", {}), "id": fc["name"]},
                raw=content, history=new_history,
            )

        text = "".join(p.get("text", "") for p in parts)

        # Same empty-text diagnostics as before — if there's genuinely no
        # text and no further tool call, say exactly why instead of
        # silently returning "".
        if not text.strip():
            finish_reason = candidate.get("finishReason", "unknown")
            raise LLMError(
                f"Gemini returned no text and no further tool call (finishReason={finish_reason}). "
                f"Raw response: {json.dumps(data)[:800]}"
            )
        return ChatResult(text=text, raw=content)
