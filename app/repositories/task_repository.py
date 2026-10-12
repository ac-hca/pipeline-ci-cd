from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.task import Task
from app.schemas.task import TaskCreate, TaskPriority, TaskStatus, TaskUpdate


class TaskRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def create(self, task_data: TaskCreate) -> Task:
        task = Task(**task_data.model_dump())
        self.session.add(task)
        self.session.commit()
        self.session.refresh(task)
        return task

    def list(
        self,
        *,
        status: TaskStatus | None,
        priority: TaskPriority | None,
        limit: int,
        offset: int,
    ) -> list[Task]:
        statement = select(Task).order_by(Task.created_at.desc()).limit(limit).offset(offset)
        if status is not None:
            statement = statement.where(Task.status == status)
        if priority is not None:
            statement = statement.where(Task.priority == priority)
        return list(self.session.scalars(statement).all())

    def get(self, task_id: UUID) -> Task | None:
        return self.session.get(Task, task_id)

    def update(self, task: Task, task_data: TaskUpdate) -> Task:
        for field, value in task_data.model_dump(exclude_unset=True).items():
            setattr(task, field, value)
        self.session.add(task)
        self.session.commit()
        self.session.refresh(task)
        return task

    def delete(self, task: Task) -> None:
        self.session.delete(task)
        self.session.commit()
