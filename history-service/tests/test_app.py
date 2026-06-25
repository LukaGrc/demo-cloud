import pytest

from main import app


@pytest.fixture
def client():
    app.config.update(TESTING=True)
    with app.test_client() as c:
        yield c


def test_health_ok(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["status"] == "ok"


def test_unknown_route_returns_404(client):
    resp = client.get("/this-does-not-exist")
    assert resp.status_code == 404


def test_create_record_requires_name_and_size(client):
    resp = client.post("/records", json={"name": "notes.md"})
    assert resp.status_code == 400


def test_create_record_requires_body(client):
    resp = client.post("/records", json={})
    assert resp.status_code == 400
