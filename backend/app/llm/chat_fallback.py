"""
Chat Fallback Orchestrator
============================
Like fallback.py (plain generation), but for a full conversational turn
that may involve one or more tool calls. Tries providers in order
(Gemini first since it has a genuine free tier, then Anthropic, then
OpenAI, then Ollama last); if a provider decides it needs the data tool,
we execute it via the caller-supplied `tool_executor` and let that SAME
provider continue — which may itself ask for the tool AGAIN (e.g. "loss
ratio of this year" needs one query to find out what year it even is,
then a second query using that year) before it finally answers in text.

If a provider fails outright (network, bad key, or it never produces a
final answer within MAX_TOOL_ITERATIONS), we move to the next provider
and start that provider's turn completely fresh — we do not try to hand
a half-finished tool-call chain from one provider to another, since the
message formats differ per vendor.
"""
from dataclasses import dataclass
from typing import Callable, Optional

from app.llm.providers import LLMProvider, LLMError, OllamaProvider, AnthropicProvider, OpenAIProvider, GeminiProvider
from app import config

# Safety cap on how many tool calls a single provider can make in a row
# within one turn, before we give up on that provider and try the next
# one. Without this, a model stuck in a "call tool -> still not
# satisfied -> call tool again" loop could run indefinitely.
MAX_TOOL_ITERATIONS = 4


class AllProvidersFailedError(Exception):
    def __init__(self, attempts: list[tuple[str, str]]):
        self.attempts = attempts
        detail = "; ".join(f"{name}: {err}" for name, err in attempts)
        super().__init__(f"All LLM providers failed — {detail}")

    def user_facing_summary(self) -> str:
        """
        The raw `attempts` detail (also kept, above, for logs) is each
        vendor's actual HTTP response body — request IDs, doc links,
        internal error type strings. That's exactly what got shown to
        the end user before this existed: a wall of nested JSON with no
        clear next step. This turns it into one short, human sentence
        per provider instead, based on recognizable patterns in each
        vendor's own error text (every major provider uses one of these
        same few shapes for quota/billing/auth/missing-model failures).
        """
        reasons = [_classify_provider_error(name, err) for name, err in self.attempts]
        return "The AI assistant isn't available right now: " + "; ".join(reasons) + "."


def _classify_provider_error(provider_name: str, error_text: str) -> str:
    text = error_text.lower()
    if "credit balance is too low" in text or "insufficient_quota" in text or "exceeded your current quota" in text:
        return f"{provider_name} — usage quota/billing limit reached, contact your admin to top up or upgrade the plan"
    if "429" in text or "rate limit" in text or "rate_limit" in text:
        return f"{provider_name} — rate limit reached, try again shortly"
    if "no gemini api key" in text or "no anthropic api key" in text or "no openai api key" in text or "401" in text or "invalid api key" in text or "authentication" in text:
        return f"{provider_name} — API key missing or invalid, contact your admin"
    if "404" in text and "model" in text:
        return f"{provider_name} — configured model isn't available on this server"
    if "unreachable" in text or "timeout" in text or "timed out" in text:
        return f"{provider_name} — temporarily unreachable"
    return f"{provider_name} — request failed"


@dataclass
class ChatTurnResult:
    text: str
    provider_used: str
    tool_used: bool
    tool_question: Optional[str] = None  # kept as the field name for
    # frontend/API compat, but now holds the SQL from the LAST tool call
    # made this turn (there may have been more than one)


def _build_providers(user_override: tuple[str, str] | None = None) -> list[LLMProvider]:
    """Builds the ordered list of providers to try, skipping any that
    have no configuration at all (e.g. no API key set).

    Order: the user's OWN personal LLM credential first, if they've
    configured one (see CREDENTIAL_MANAGEMENT_DESIGN.md) — then the
    normal global fallback chain: Gemini (genuine free tier, actually
    reachable), then Anthropic and OpenAI (real API keys, once billing is
    sorted), then Ollama last (no model downloaded on this machine yet).

    user_override is (provider_name, api_key) from
    get_llm_override_for_user() — None means "no personal credential
    configured," which is the same behavior as before this feature
    existed, so nothing changes for users who never touch the new
    settings page.
    """
    providers: list[LLMProvider] = []

    if user_override:
        provider_name, api_key = user_override
        if provider_name == "gemini":
            providers.append(GeminiProvider(api_key, config.GEMINI_MODEL))
        elif provider_name == "anthropic":
            providers.append(AnthropicProvider(api_key, config.ANTHROPIC_MODEL))
        elif provider_name == "openai":
            providers.append(OpenAIProvider(api_key, config.OPENAI_MODEL))
        # An unrecognized provider_name (e.g. 'azure_openai', not yet
        # wired — see credentials.py) is silently skipped here rather
        # than raising, so a user with an unsupported provider choice
        # still gets the normal tenant-wide chain below instead of a
        # broken chat turn.

    if config.GEMINI_API_KEY:
        providers.append(GeminiProvider(config.GEMINI_API_KEY, config.GEMINI_MODEL))
    if config.ANTHROPIC_API_KEY:
        providers.append(AnthropicProvider(config.ANTHROPIC_API_KEY, config.ANTHROPIC_MODEL))
    if config.OPENAI_API_KEY:
        providers.append(OpenAIProvider(config.OPENAI_API_KEY, config.OPENAI_MODEL))
    if config.OLLAMA_BASE_URL:
        providers.append(OllamaProvider(config.OLLAMA_BASE_URL, config.OLLAMA_MODEL))
    return providers


def run_chat_turn(
    messages: list[dict],
    tools: list[dict] | None,
    tool_executor: Callable[[str, dict], str],
    timeout_seconds: float = 20,
    user_llm_override: tuple[str, str] | None = None,
) -> ChatTurnResult:
    """
    tool_executor(tool_name, tool_input) -> a plain-text result to feed
    back to the model. Should never raise — catch its own errors and
    return a descriptive string instead, so the model can tell the user
    what went wrong rather than the whole turn failing.

    user_llm_override: optional (provider_name, api_key) — see
    _build_providers() above. Pass this whenever the caller has already
    resolved a per-user LLM credential (get_llm_override_for_user());
    omit it for the unchanged, tenant-wide-only behavior.
    """
    providers = _build_providers(user_llm_override)
    if not providers:
        raise AllProvidersFailedError([("none", "No LLM providers are configured at all")])

    attempts: list[tuple[str, str]] = []
    for provider in providers:
        try:
            result = provider.chat(messages, tools, timeout_seconds=timeout_seconds)

            tool_calls_made: list[str] = []
            iterations = 0
            while result.tool_call:
                if iterations >= MAX_TOOL_ITERATIONS:
                    raise LLMError(
                        f"Made {MAX_TOOL_ITERATIONS} tool calls in a row without a final answer "
                        f"(last call was '{result.tool_call['name']}') — giving up on this provider."
                    )

                tool_result_text = tool_executor(result.tool_call["name"], result.tool_call["input"])
                sql_or_question = result.tool_call["input"].get("sql") or result.tool_call["input"].get("question")
                if sql_or_question:
                    tool_calls_made.append(sql_or_question)

                # Pass `tools` again so the model CAN ask for another
                # tool call if it still doesn't have enough to answer —
                # this is what makes multi-step lookups (e.g. "find the
                # year, then query that year") work instead of erroring.
                result = provider.continue_with_tool_result(
                    result.history, result.tool_call, tool_result_text,
                    tools=tools, timeout_seconds=timeout_seconds,
                )
                iterations += 1

            return ChatTurnResult(
                text=result.text or "",
                provider_used=provider.name,
                tool_used=bool(tool_calls_made),
                tool_question=tool_calls_made[-1] if tool_calls_made else None,
            )

        except LLMError as e:
            attempts.append((provider.name, str(e)))
            continue

    raise AllProvidersFailedError(attempts)
