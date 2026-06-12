from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import logging

from routers import auth, dashboard, azure, aws, docker_ops, terraform, kubernetes_ops, activity, ai_agent
from db.database import init_db

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
logger = logging.getLogger(__name__)

app = FastAPI(
    title="CloudOps Automation Hub",
    description="Self-service Platform Engineering Portal for AWS, Azure, Docker, Kubernetes and Terraform",
    version="1.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
async def startup():
    await init_db()
    logger.info("CloudOps Automation Hub started")


@app.get("/api/health")
async def health():
    return {"status": "ok", "service": "cloudops-automation-hub"}


app.include_router(auth.router,           prefix="/api/auth",       tags=["Auth"])
app.include_router(dashboard.router,      prefix="/api/dashboard",  tags=["Dashboard"])
app.include_router(azure.router,          prefix="/api/azure",      tags=["Azure"])
app.include_router(aws.router,            prefix="/api/aws",        tags=["AWS"])
app.include_router(docker_ops.router,     prefix="/api/docker",     tags=["Docker"])
app.include_router(terraform.router,      prefix="/api/terraform",  tags=["Terraform"])
app.include_router(kubernetes_ops.router, prefix="/api/k8s",        tags=["Kubernetes"])
app.include_router(activity.router,       prefix="/api/activity",   tags=["Activity"])
app.include_router(ai_agent.router,       prefix="/api/ai",         tags=["AI Agent"])
