import os
from datetime import datetime, timedelta, timezone
from typing import Optional

from jose import JWTError, jwt
import bcrypt
import pyotp

SECRET_KEY   = os.getenv("JWT_SECRET", "change-me-in-production-minimum-64-chars-xxxxxxxxxxxxxxxxxxxx")
ALGORITHM    = "HS256"
ACCESS_TTL   = int(os.getenv("JWT_ACCESS_TTL_MINUTES",  "15"))
REFRESH_TTL  = int(os.getenv("JWT_REFRESH_TTL_DAYS",    "7"))

ADMIN_USER        = os.getenv("ADMIN_USER", "admin")
ADMIN_PASS_HASH   = os.getenv("ADMIN_PASS_HASH", "")
TOTP_SECRET       = os.getenv("TOTP_SECRET", "")
ADMIN_ROLE        = os.getenv("ADMIN_ROLE", "admin")

def verify_password(plain: str, hashed: str) -> bool:
    return bcrypt.checkpw(plain.encode(), hashed.encode())

def verify_totp(code: str) -> bool:
    if not TOTP_SECRET:
        return False
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
