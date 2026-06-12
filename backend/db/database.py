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
        await db.execute("""
            CREATE TABLE IF NOT EXISTS ai_approvals (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at   TEXT    NOT NULL,
                requested_by TEXT    NOT NULL,
                tool_name    TEXT    NOT NULL,
                tool_args    TEXT    NOT NULL,
                risk_tier    TEXT    NOT NULL,
                status       TEXT    NOT NULL DEFAULT 'pending',
                reviewed_by  TEXT,
                reviewed_at  TEXT,
                result       TEXT
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


# ── AI Approvals ───────────────────────────────────────────────────────────────

async def create_approval(
    requested_by: str,
    tool_name: str,
    tool_args: dict,
    risk_tier: str,
) -> int:
    import json
    async with aiosqlite.connect(DB_PATH) as db:
        cur = await db.execute(
            """
            INSERT INTO ai_approvals (created_at, requested_by, tool_name, tool_args, risk_tier, status)
            VALUES (?, ?, ?, ?, ?, 'pending')
            """,
            (
                datetime.now(timezone.utc).isoformat(),
                requested_by,
                tool_name,
                json.dumps(tool_args),
                risk_tier,
            ),
        )
        await db.commit()
        return cur.lastrowid


async def get_approvals(status: Optional[str] = "pending") -> List[dict]:
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        if status:
            async with db.execute(
                "SELECT * FROM ai_approvals WHERE status = ? ORDER BY id DESC", (status,)
            ) as cur:
                rows = await cur.fetchall()
        else:
            async with db.execute(
                "SELECT * FROM ai_approvals ORDER BY id DESC"
            ) as cur:
                rows = await cur.fetchall()
        return [dict(r) for r in rows]


async def update_approval(
    approval_id: int,
    status: str,
    reviewed_by: Optional[str] = None,
    result: Optional[str] = None,
) -> None:
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(
            """
            UPDATE ai_approvals
            SET status = ?, reviewed_by = COALESCE(?, reviewed_by),
                reviewed_at = ?, result = COALESCE(?, result)
            WHERE id = ?
            """,
            (
                status,
                reviewed_by,
                datetime.now(timezone.utc).isoformat(),
                result,
                approval_id,
            ),
        )
        await db.commit()
