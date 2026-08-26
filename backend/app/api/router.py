from fastapi import APIRouter

from app.modules.ai_gateway.router import router as ai_gateway_router
from app.modules.auth.router import router as auth_router
from app.modules.billing.router import router as billing_router
from app.modules.credits.router import router as credits_router
from app.modules.interviews.router import router as interviews_router
from app.modules.payments.router import router as payments_router
from app.modules.projects.router import router as projects_router
from app.modules.prompt_chains.router import router as prompt_chains_router
from app.modules.prompt_engine.router import router as prompt_router
from app.modules.prompt_templates.router import router as prompt_templates_router
from app.modules.smart_profile.router import router as smart_profile_router
from app.modules.users.router import router as users_router

api_router = APIRouter()
api_router.include_router(auth_router, prefix="/auth", tags=["authentication"])
api_router.include_router(users_router, prefix="/users", tags=["users"])
api_router.include_router(ai_gateway_router, prefix="/ai", tags=["ai"])
api_router.include_router(prompt_router, prefix="/prompts", tags=["prompts"])
api_router.include_router(prompt_chains_router, prefix="/chains", tags=["prompt-chains"])
api_router.include_router(projects_router, prefix="/projects", tags=["projects"])
api_router.include_router(prompt_templates_router, prefix="/templates", tags=["templates"])
api_router.include_router(billing_router, prefix="/billing", tags=["billing"])
api_router.include_router(credits_router, prefix="/credits", tags=["credits"])
api_router.include_router(payments_router, prefix="/payments", tags=["payments"])
api_router.include_router(interviews_router, prefix="/interviews", tags=["interviews"])
api_router.include_router(smart_profile_router, prefix="/profile", tags=["profile"])
