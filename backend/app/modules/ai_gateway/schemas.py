from pydantic import BaseModel, Field


class GenerateTextRequest(BaseModel):
    provider: str = Field(default="openai", min_length=1, max_length=50)
    model: str | None = Field(default=None, min_length=1, max_length=200)
    system_prompt: str | None = Field(default=None, max_length=20_000)
    user_prompt: str = Field(min_length=1, max_length=100_000)
    temperature: float | None = Field(default=None, ge=0, le=2)
    max_output_tokens: int | None = Field(default=None, ge=1, le=32_768)


class TokenUsageResponse(BaseModel):
    input_tokens: int | None
    output_tokens: int | None
    total_tokens: int | None


class GenerateTextResponse(BaseModel):
    provider: str
    model: str
    text: str
    latency_ms: int
    usage: TokenUsageResponse


class ProviderResponse(BaseModel):
    provider: str
    models: list[str]


class ProviderListResponse(BaseModel):
    providers: list[ProviderResponse]
