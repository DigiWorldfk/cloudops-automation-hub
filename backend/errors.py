import logging
import re
from fastapi import HTTPException

_SENSITIVE_PATTERN = re.compile(
    r"(?i)(password|passwd|secret|token|api[_-]?key|authorization|connectionstring|access[_-]?key)"
    r"(\s*[=:]\s*)([^\s,;]+)"
)


def operation_error(logger: logging.Logger, operation: str, exc: Exception) -> HTTPException:
    logger.error("%s failed with %s", operation, type(exc).__name__)
    return HTTPException(status_code=500, detail="Operation failed")


def audit_error(exc: Exception) -> str:
    return type(exc).__name__


def redact_text(value: str) -> str:
    return _SENSITIVE_PATTERN.sub(r"\1\2[REDACTED]", value)