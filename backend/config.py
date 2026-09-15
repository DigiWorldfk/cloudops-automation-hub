import os
from typing import List


def environment_name() -> str:
    return os.getenv("ENVIRONMENT", "development").strip().lower()


def is_production() -> bool:
    return environment_name() in {"production", "prod"}


def env_flag(name: str, default: bool = False) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def allowed_origins() -> List[str]:
    configured = os.getenv("CORS_ALLOWED_ORIGINS", "")
    return [origin.strip().rstrip("/") for origin in configured.split(",") if origin.strip()]


def validate_runtime_config() -> None:
    from auth.jwt_handler import validate_security_config

    validate_security_config()
    if is_production() and not env_flag("COOKIE_SECURE"):
        raise RuntimeError("COOKIE_SECURE must be true in production")
    if is_production() and not allowed_origins():
        raise RuntimeError("CORS_ALLOWED_ORIGINS must be configured in production")