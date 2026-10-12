from uuid import UUID

from app.core.errors import TaskNotFoundError
from app.models.task import Task
from app.repositories.task_repository import TaskRepository
from app.schemas.task import TaskCreate, TaskPriority, TaskStatus, TaskUpdate


class TaskService:
    def __init__(self, repository: TaskRepository) -> None:
        self.repository = repository

    def create(self, task_data: TaskCreate) -> Task:
        return self.repository.create(task_data)

    def list(
        self,
        *,
        status: TaskStatus | None,
        priority: TaskPriority | None,
        limit: int,
        offset: int,
    ) -> list[Task]:
        return self.repository.list(
            status=status,
            priority=priority,
            limit=limit,
            offset=offset,
        )

    def get(self, task_id: UUID) -> Task:
        task = self.repository.get(task_id)
        if task is None:
            raise TaskNotFoundError(task_id)
        return task

    def update(self, task_id: UUID, task_data: TaskUpdate) -> Task:
        return self.repository.update(self.get(task_id), task_data)

    def delete(self, task_id: UUID) -> None:
        self.repository.delete(self.get(task_id))
