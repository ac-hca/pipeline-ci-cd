from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Response, status

from app.api.dependencies import get_task_service
from app.schemas.task import TaskCreate, TaskPriority, TaskRead, TaskStatus, TaskUpdate
from app.services.task_service import TaskService

router = APIRouter(prefix="/api/v1/tasks", tags=["tasks"])

TaskServiceDependency = Annotated[TaskService, Depends(get_task_service)]


@router.post("", response_model=TaskRead, status_code=status.HTTP_201_CREATED)
def create_task(task_data: TaskCreate, service: TaskServiceDependency) -> TaskRead:
    return TaskRead.model_validate(service.create(task_data))


@router.get("", response_model=list[TaskRead])
def list_tasks(
    service: TaskServiceDependency,
    task_status: Annotated[TaskStatus | None, Query(alias="status")] = None,
    priority: TaskPriority | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> list[TaskRead]:
    return [
        TaskRead.model_validate(task)
        for task in service.list(
            status=task_status,
            priority=priority,
            limit=limit,
            offset=offset,
        )
    ]


@router.get("/{task_id}", response_model=TaskRead)
def get_task(task_id: UUID, service: TaskServiceDependency) -> TaskRead:
    return TaskRead.model_validate(service.get(task_id))


@router.patch("/{task_id}", response_model=TaskRead)
def update_task(
    task_id: UUID,
    task_data: TaskUpdate,
    service: TaskServiceDependency,
) -> TaskRead:
    return TaskRead.model_validate(service.update(task_id, task_data))


@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_task(task_id: UUID, service: TaskServiceDependency) -> Response:
    service.delete(task_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
