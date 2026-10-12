from typing import Annotated

from fastapi import Depends
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.repositories.task_repository import TaskRepository
from app.services.task_service import TaskService


def get_task_service(session: Annotated[Session, Depends(get_db)]) -> TaskService:
    return TaskService(TaskRepository(session))
