from fastapi import APIRouter, Depends, Query
from auth.dependencies import get_current_user
from db.database import get_activity, count_activity

router = APIRouter()


@router.get("")
async def list_activity(
    limit:  int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    _user: dict = Depends(get_current_user),
):
    rows  = await get_activity(limit=limit, offset=offset)
    total = await count_activity()
    return {"total": total, "items": rows}
