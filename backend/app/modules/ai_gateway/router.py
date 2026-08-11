from collections.abc import AsyncIterator
from json import dumps
from typing import Annotated
from uuid import uuid4

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse

from app.core.ai_exceptions import AIGatewayError
from app.modules.ai_gateway.dependencies import AIGateway
from app.modules.ai_gateway.schemas import GenerateTextRequest, GenerateTextResponse, ProviderListResponse
from app.modules.ai_gateway.service import AIGatewayService
from app.modules.billing.dependencies import Billing
from app.modules.billing.model import UsageRecord
from app.modules.credits.dependencies import Credits
from app.modules.credits.enums import CreditOperationType
from app.modules.credits.model import CreditReservation
from app.modules.users.dependencies import get_current_user
from app.modules.users.model import User

router = APIRouter(dependencies=[Depends(get_current_user)])
CurrentUser = Annotated[User, Depends(get_current_user)]


@router.get("/providers", response_model=ProviderListResponse, summary="Lista providers e modelos configurados")
async def list_providers(gateway: AIGateway) -> ProviderListResponse:
    return gateway.list_providers()


@router.post("/generate", response_model=GenerateTextResponse, summary="Gera texto com um provider de IA")
async def generate_text(
    data: GenerateTextRequest,
    gateway: AIGateway,
    billing: Billing,
    credits: Credits,
    current_user: CurrentUser,
) -> GenerateTextResponse:
    reservation = await billing.reserve_ai_generation(current_user.id, data.provider)
    try:
        credit_reservation = await credits.reserve(
            current_user.id,
            CreditOperationType.TEXT_GENERATION,
            data.provider,
            data.model,
            max(len(data.user_prompt) // 4, 1),
            data.max_output_tokens or 2_000,
            f"ai:{uuid4()}",
        )
    except Exception:
        await billing.repository.release_usage(reservation)
        raise
    try:
        response = await gateway.generate(data)
    except Exception:
        await billing.repository.release_usage(reservation)
        await credits.release(credit_reservation.id)
        raise
    await billing.repository.finalize_usage(
        reservation,
        prompt_id=None,
        provider=response.provider,
        model=response.model,
        input_tokens=response.usage.input_tokens or 0,
        output_tokens=response.usage.output_tokens or 0,
    )
    await credits.settle(
        credit_reservation.id,
        data.provider,
        data.model,
        response.usage.input_tokens or 0,
        response.usage.output_tokens or 0,
    )
    return response


async def _sse_events(
    gateway: AIGatewayService,
    billing: Billing,
    reservation: UsageRecord,
    credits: Credits,
    credit_reservation: CreditReservation,
    data: GenerateTextRequest,
) -> AsyncIterator[str]:
    completed = False
    try:
        async for event in gateway.stream(data):
            if event.text is not None:
                yield f"event: {event.event}\ndata: {dumps({'text': event.text})}\n\n"
            if event.output is not None:
                await billing.repository.finalize_usage(
                    reservation,
                    prompt_id=None,
                    provider=event.output.provider,
                    model=event.output.model,
                    input_tokens=event.output.usage.input_tokens or 0,
                    output_tokens=event.output.usage.output_tokens or 0,
                )
                await credits.settle(
                    credit_reservation.id,
                    data.provider,
                    data.model,
                    event.output.usage.input_tokens or 0,
                    event.output.usage.output_tokens or 0,
                )
                completed = True
                output = GenerateTextResponse(
                    provider=event.output.provider,
                    model=event.output.model,
                    text=event.output.text,
                    latency_ms=event.output.latency_ms,
                    usage=event.output.usage,
                )
                yield f"event: complete\ndata: {output.model_dump_json()}\n\n"
    except AIGatewayError:
        await billing.repository.release_usage(reservation)
        await credits.release(credit_reservation.id)
        completed = True
        yield "event: error\ndata: AI generation is unavailable\n\n"
    finally:
        if not completed:
            await billing.repository.release_usage(reservation)
            await credits.release(credit_reservation.id)


@router.post("/generate/stream", summary="Gera texto por Server-Sent Events")
async def stream_text(
    data: GenerateTextRequest,
    gateway: AIGateway,
    billing: Billing,
    credits: Credits,
    current_user: CurrentUser,
) -> StreamingResponse:
    reservation = await billing.reserve_ai_generation(current_user.id, data.provider)
    try:
        credit_reservation = await credits.reserve(
            current_user.id,
            CreditOperationType.TEXT_GENERATION,
            data.provider,
            data.model,
            max(len(data.user_prompt) // 4, 1),
            data.max_output_tokens or 2_000,
            f"ai-stream:{uuid4()}",
        )
    except Exception:
        await billing.repository.release_usage(reservation)
        raise
    return StreamingResponse(
        _sse_events(gateway, billing, reservation, credits, credit_reservation, data),
        media_type="text/event-stream",
    )
