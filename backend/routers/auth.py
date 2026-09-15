from collections import defaultdict, deque
import time
from fastapi import APIRouter, HTTPException, Response, Request, status, Depends
from models.schemas import LoginRequest, TokenResponse, UserInfo
from auth.jwt_handler import authenticate_user, create_access_token, create_refresh_token, decode_token
from auth.dependencies import get_current_user
from db.database import log_activity
from config import env_flag
from errors import audit_error

router = APIRouter()
_login_attempts: dict[str, deque[float]] = defaultdict(deque)
_LOGIN_LIMIT = 5
_LOGIN_WINDOW_SECONDS = 60


def _check_login_rate_limit(client_key: str) -> None:
    now = time.monotonic()
    attempts = _login_attempts[client_key]
    while attempts and now - attempts[0] >= _LOGIN_WINDOW_SECONDS:
        attempts.popleft()
    if len(attempts) >= _LOGIN_LIMIT:
        raise HTTPException(status_code=429, detail="Too many login attempts")
    attempts.append(now)


@router.post("/login")
async def login(body: LoginRequest, request: Request, response: Response):
    _check_login_rate_limit(request.client.host if request.client else "unknown")
    user = authenticate_user(body.username, body.password, body.totp_code)
    if not user:
        await log_activity("anonymous", "LOGIN_FAILED", "user", "FAIL", "Invalid credentials or TOTP")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid username, password, or TOTP code")

    payload = {"sub": user["username"], "role": user["role"]}
    access_token   = create_access_token(payload)
    refresh_token  = create_refresh_token(payload)

    cookie_options = {"httponly": True, "samesite": "strict", "secure": env_flag("COOKIE_SECURE"), "path": "/"}
    response.set_cookie("access_token", access_token, max_age=900, **cookie_options)
    response.set_cookie("refresh_token", refresh_token, max_age=604800, **cookie_options)

    await log_activity(user["username"], "LOGIN", f"user:{user['username']}", "OK")
    return {"message": "Authenticated", "role": user["role"]}


@router.post("/refresh")
async def refresh(request: Request, response: Response):
    token = request.cookies.get("refresh_token")
    if not token:
        raise HTTPException(status_code=401, detail="No refresh token")
    payload = decode_token(token)
    if not payload or payload.get("type") != "refresh":
        raise HTTPException(status_code=401, detail="Invalid refresh token")
    new_access = create_access_token({"sub": payload["sub"], "role": payload["role"]})
    response.set_cookie(
        "access_token", new_access, httponly=True, samesite="strict",
        secure=env_flag("COOKIE_SECURE"), max_age=900, path="/",
    )
    return {"message": "Token refreshed"}


@router.post("/logout")
async def logout(response: Response, user: dict = Depends(get_current_user)):
    await log_activity(user["username"], "LOGOUT", f"user:{user['username']}", "OK")
    response.delete_cookie("access_token")
    response.delete_cookie("refresh_token")
    return {"message": "Logged out"}


@router.get("/me", response_model=UserInfo)
async def me(user: dict = Depends(get_current_user)):
    return UserInfo(username=user["username"], role=user["role"])
