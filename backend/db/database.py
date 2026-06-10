import aiosqlite
import os
from datetime import datetime, timezone
from typing import Optional, List

DB_PATH = os.getenv("DB_PATH", "/app/data/cloudops.db")


async def init_db():
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute("""
            CREATE TABLE IF NOT EXISTS activity_log (
                id        INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT    NOT NULL,
                user      TEXT    NOT NULL,
                action    TEXT    NOT NULL,
                resource  TEXT    NOT NULL,
                status    TEXT    NOT NULL,
                detail    TEXT
            )
        """)
        await db.commit()


async def log_activity(user: str, action: str, resource: str, status: str, detail: Optional[str] = None):
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(
            "INSERT INTO activity_log (timestamp, user, action, resource, status, detail) VALUES (?, ?, ?, ?, ?, ?)",
            (datetime.now(timezone.utc).isoformat(), user, action, resource, status, detail),
        )
        await db.commit()


async def get_activity(limit: int = 100, offset: int = 0) -> List[dict]:
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute(
            "SELECT * FROM activity_log ORDER BY id DESC LIMIT ? OFFSET ?",
            (limit, offset),
        ) as cur:
            rows = await cur.fetchall()
            return [dict(r) for r in rows]


async def count_activity() -> int:
    async with aiosqlite.connect(DB_PATH) as db:
        async with db.execute("SELECT COUNT(*) FROM activity_log") as cur:
            row = await cur.fetchone()
            return row[0] if row else 0
