from uuid import uuid4

from fastapi.testclient import TestClient


def create_task(client: TestClient, **overrides: object) -> dict[str, object]:
    payload: dict[str, object] = {
        "title": "Prepare deployment",
        "description": "Validate the release before deployment",
        "priority": "high",
        "due_date": "2026-10-20T18:00:00Z",
    }
    payload.update(overrides)
    response = client.post("/api/v1/tasks", json=payload)
    assert response.status_code == 201
    return response.json()


def test_create_task(client: TestClient) -> None:
    task = create_task(client)

    assert task["title"] == "Prepare deployment"
    assert task["status"] == "pending"
    assert task["priority"] == "high"
    assert task["id"]
    assert task["created_at"]
    assert task["updated_at"]


def test_list_tasks_with_filters(client: TestClient) -> None:
    create_task(client, title="Low priority task", priority="low")
    expected = create_task(client, title="High priority task", priority="high")

    response = client.get("/api/v1/tasks", params={"priority": "high"})

    assert response.status_code == 200
    assert response.json() == [expected]


def test_get_task(client: TestClient) -> None:
    created = create_task(client)

    response = client.get(f"/api/v1/tasks/{created['id']}")

    assert response.status_code == 200
    assert response.json() == created


def test_update_task(client: TestClient) -> None:
    created = create_task(client)

    response = client.patch(
        f"/api/v1/tasks/{created['id']}",
        json={"status": "completed", "description": None},
    )

    assert response.status_code == 200
    assert response.json()["status"] == "completed"
    assert response.json()["description"] is None


def test_delete_task(client: TestClient) -> None:
    created = create_task(client)

    delete_response = client.delete(f"/api/v1/tasks/{created['id']}")
    get_response = client.get(f"/api/v1/tasks/{created['id']}")

    assert delete_response.status_code == 204
    assert delete_response.content == b""
    assert get_response.status_code == 404
    assert get_response.json() == {
        "error": {
            "code": "task_not_found",
            "message": "The requested task does not exist",
        }
    }


def test_unknown_task_returns_not_found(client: TestClient) -> None:
    response = client.get(f"/api/v1/tasks/{uuid4()}")

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "task_not_found"


def test_invalid_task_returns_structured_validation_error(client: TestClient) -> None:
    response = client.post("/api/v1/tasks", json={"title": "No"})

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


def test_empty_update_is_rejected(client: TestClient) -> None:
    created = create_task(client)

    response = client.patch(f"/api/v1/tasks/{created['id']}", json={})

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"
