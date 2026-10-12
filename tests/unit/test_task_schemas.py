from datetime import UTC, datetime

import pytest
from pydantic import ValidationError

from app.schemas.task import TaskCreate, TaskPriority, TaskStatus, TaskUpdate


def test_task_create_applies_defaults() -> None:
    task = TaskCreate(title="  Prepare deployment  ")

    assert task.title == "Prepare deployment"
    assert task.status is TaskStatus.PENDING
    assert task.priority is TaskPriority.MEDIUM


def test_task_create_rejects_short_title() -> None:
    with pytest.raises(ValidationError):
        TaskCreate(title="No")


def test_task_create_requires_timezone_in_due_date() -> None:
    with pytest.raises(ValidationError, match="must include a timezone"):
        TaskCreate(title="Prepare deployment", due_date=datetime(2026, 10, 20, 18, 0))


def test_task_create_normalizes_due_date_to_utc() -> None:
    task = TaskCreate(
        title="Prepare deployment",
        due_date=datetime(2026, 10, 20, 18, 0, tzinfo=UTC),
    )

    assert task.due_date is not None
    assert task.due_date.tzinfo is UTC


def test_task_update_requires_at_least_one_field() -> None:
    with pytest.raises(ValidationError, match="At least one field"):
        TaskUpdate()


@pytest.mark.parametrize("field", ["title", "status", "priority"])
def test_task_update_rejects_null_required_fields(field: str) -> None:
    with pytest.raises(ValidationError, match=f"{field} cannot be null"):
        TaskUpdate.model_validate({field: None})
