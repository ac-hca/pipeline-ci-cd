import pytest
from sqlalchemy import delete

from app.db.session import SessionLocal
from app.models.task import Task


@pytest.fixture(autouse=True)
def clean_tasks() -> None:
    with SessionLocal.begin() as session:
        session.execute(delete(Task))
    yield
    with SessionLocal.begin() as session:
        session.execute(delete(Task))
