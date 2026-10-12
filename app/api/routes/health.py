from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.db.session import get_db

router = APIRouter(tags=["health"])


@router.get("/health/live")
def liveness() -> dict[str, Literal["alive"]]:
    return {"status": "alive"}


@router.get("/health/ready")
def readiness(session: Annotated[Session, Depends(get_db)]) -> dict[str, Literal["ready"]]:
    try:
        session.execute(text("SELECT 1"))
    except SQLAlchemyError as exception:
        raise HTTPException(
            status_code=503,
            detail={
                "code": "database_unavailable",
                "message": "The database is not available",
            },
        ) from exception
    return {"status": "ready"}
