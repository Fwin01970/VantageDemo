"""
Fallback Chain
===============
Tries providers in order: Ollama (free, local) first, then Anthropic,
then OpenAI. The first one that responds successfully wins. If every
provider fails, callers get a clear AllProvidersFailedError rather than
a silent wrong answer.

Order and which providers are even configured comes from environment
variables — see app/config.py — so this can run with just Ollama, just
one paid provider, or all three, without code changes.
"""
from dataclasses import dataclass

from app.llm.providers import (
    LLMProvider, LLMError, OllamaProvider, AnthropicProvider, OpenAIProvider, GeminiProvider,
)
from app import config


class AllProvidersFailedError(Exception):
    def __init__(self, attempts: list[tuple[str, str]]):
        self.attempts = attempts  # [(provider_name, error_message), ...]
        detail = "; ".join(f"{name}: {err}" for name, err in attempts)
        super().__init__(f"All LLM providers failed — {detail}")


@dataclass
class GenerationResult:
    text: str
    provider_used: str


def _build_providers() -> list[LLMProvider]:
    """Builds the ordered list of providers to try, skipping any that
    have no configuration at all (e.g. no API key set).

    Order: Gemini first (genuine free tier, actually reachable), then
    Anthropic and OpenAI (real API keys, once billing is sorted), then
    Ollama last (no model downloaded on this machine yet).
    """
    providers: list[LLMProvider] = []

    if config.GEMINI_API_KEY:
        providers.append(GeminiProvider(config.GEMINI_API_KEY, config.GEMINI_MODEL))
    if config.ANTHROPIC_API_KEY:
        providers.append(AnthropicProvider(config.ANTHROPIC_API_KEY, config.ANTHROPIC_MODEL))
    if config.OPENAI_API_KEY:
        providers.append(OpenAIProvider(config.OPENAI_API_KEY, config.OPENAI_MODEL))
    if config.OLLAMA_BASE_URL:
        providers.append(OllamaProvider(config.OLLAMA_BASE_URL, config.OLLAMA_MODEL))

    return providers


def generate_with_fallback(prompt: str, timeout_seconds: float = 15) -> GenerationResult:
    providers = _build_providers()
    if not providers:
        raise AllProvidersFailedError([("none", "No LLM providers are configured at all")])

    attempts: list[tuple[str, str]] = []
    for provider in providers:
        try:
            text = provider.generate(prompt, timeout_seconds=timeout_seconds)
            return GenerationResult(text=text, provider_used=provider.name)
        except LLMError as e:
            attempts.append((provider.name, str(e)))
            continue

    raise AllProvidersFailedError(attempts)
