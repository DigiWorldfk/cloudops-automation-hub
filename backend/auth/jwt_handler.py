import os
from datetime import datetime, timedelta, timezone
from typing import Optional

from jose import JWTError, jwt
import bcrypt
import pyotp

SECRET_KEY   = os.getenv("JWT_SECRET", "")
ALGORITHM    = "HS256"
ACCESS_TTL   = int(os.getenv("JWT_ACCESS_TTL_MINUTES",  "15"))
REFRESH_TTL  = int(os.getenv("JWT_REFRESH_TTL_DAYS",    "7"))

ADMIN_USER        = os.getenv("ADMIN_USER", "admin")
ADMIN_PASS_HASH   = os.getenv("ADMIN_PASS_HASH", "")
TOTP_SECRET       = os.getenv("TOTP_SECRET", "")
ADMIN_ROLE        = os.getenv("ADMIN_ROLE", "admin")

def validate_security_config() -> None:
    required = {
        "JWT_SECRET": SECRET_KEY,
        "ADMIN_PASS_HASH": ADMIN_PASS_HASH,
        "TOTP_SECRET": TOTP_SECRET,
    }
    missing = [name for name, value in required.items() if not value.strip()]
    placeholders = [
        name for name, value in required.items()
        if value.lower().startswith(("change-me", "replace-with", "your-"))
        or "change-this" in value.lower()
    ]
    if missing or placeholders:
        problems = missing + [f"{name} uses a placeholder" for name in placeholders]
        raise RuntimeError("Invalid security configuration: " + ", ".join(problems))
    if len(SECRET_KEY) < 32:
        raise RuntimeError("JWT_SECRET must be at least 32 characters")
    if not ADMIN_PASS_HASH.startswith(("$2a$", "$2b$", "$2y$")):
        raise RuntimeError("ADMIN_PASS_HASH must be a bcrypt hash")
    if len(TOTP_SECRET) < 16:
        raise RuntimeError("TOTP_SECRET must be a valid unique base32 secret")

def verify_password(plain: str, hashed: str) -> bool:
    return bcrypt.checkpw(plain.encode(), hashed.encode())

def verify_totp(code: str) -> bool:
    if not TOTP_SECRET:
        raise RuntimeError("TOTP_SECRET is not configured")
    totp = pyotp.TOTP(TOTP_SECRET)
    return totp.verify(code, valid_window=1)

def authenticate_user(username: str, password: str, totp_code: str) -> Optional[dict]:
    if username != ADMIN_USER:
        return None
    if not ADMIN_PASS_HASH or not verify_password(password, ADMIN_PASS_HASH):
        return None
    if not verify_totp(totp_code):
        return None
    return {"username": username, "role": ADMIN_ROLE}

def create_access_token(data: dict) -> str:
    payload = data.copy()
    payload["exp"] = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TTL)
    payload["type"] = "access"
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)

def create_refresh_token(data: dict) -> str:
    payload = data.copy()
    payload["exp"] = datetime.now(timezone.utc) + timedelta(days=REFRESH_TTL)
    payload["type"] = "refresh"
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)

def decode_token(token: str) -> Optional[dict]:
    try:
        return jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError:
        return None
