from collections.abc import AsyncIterator
from json import dumps

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse

from app.core.ai_exceptions import AIGatewayError
from app.modules.ai_gateway.dependencies import AIGateway
from app.modules.ai_gateway.schemas import GenerateTextRequest, GenerateTextResponse, ProviderListResponse
from app.modules.ai_gateway.service import AIGatewayService
from app.modules.users.dependencies import get_current_user

router = APIRouter(dependencies=[Depends(get_current_user)])


@router.get("/providers", response_model=ProviderListResponse, summary="Lista providers e modelos configurados")
async def list_providers(gateway: AIGateway) -> ProviderListResponse:
    return gateway.list_providers()


@router.post("/generate", response_model=GenerateTextResponse, summary="Gera texto com um provider de IA")
async def generate_text(data: GenerateTextRequest, gateway: AIGateway) -> GenerateTextResponse:
    return await gateway.generate(data)


async def _sse_events(gateway: AIGatewayService, data: GenerateTextRequest) -> AsyncIterator[str]:
    try:
        async for event in gateway.stream(data):
            if event.text is not None:
                yield f"event: {event.event}\ndata: {dumps({'text': event.text})}\n\n"
            if event.output is not None:
                output = GenerateTextResponse(
                    provider=event.output.provider,
                    model=event.output.model,
                    text=event.output.text,
                    latency_ms=event.output.latency_ms,
                    usage=event.output.usage,
                )
                yield f"event: complete\ndata: {output.model_dump_json()}\n\n"
    except AIGatewayError:
        yield "event: error\ndata: AI generation is unavailable\n\n"


@router.post("/generate/stream", summary="Gera texto por Server-Sent Events")
async def stream_text(data: GenerateTextRequest, gateway: AIGateway) -> StreamingResponse:
    return StreamingResponse(_sse_events(gateway, data), media_type="text/event-stream")
