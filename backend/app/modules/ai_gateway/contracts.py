from collections.abc import AsyncIterator
from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class GenerationInput:
    model: str | None
    system_prompt: str | None
    user_prompt: str
    temperature: float | None
    max_output_tokens: int | None


@dataclass(frozen=True)
class TokenUsage:
    input_tokens: int | None
    output_tokens: int | None
    total_tokens: int | None


@dataclass(frozen=True)
class GenerationOutput:
    provider: str
    model: str
    text: str
    latency_ms: int
    usage: TokenUsage


@dataclass(frozen=True)
class GenerationStreamEvent:
    event: str
    text: str | None = None
    output: GenerationOutput | None = None


class TextGenerationProvider(Protocol):
    name: str

    @property
    def is_available(self) -> bool: ...

    def available_models(self) -> list[str]: ...

    async def generate(self, generation_input: GenerationInput) -> GenerationOutput: ...

    async def stream(self, generation_input: GenerationInput) -> AsyncIterator[GenerationStreamEvent]: ...
