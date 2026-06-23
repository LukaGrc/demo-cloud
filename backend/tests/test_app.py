import io

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


def test_update_object_rejects_missing_content(client):
    resp = client.put("/object/notes.md", json={})
    assert resp.status_code == 400


def test_update_object_rejects_non_markdown(client):
    resp = client.put("/object/photo.jpg", json={"content": "data"})
    assert resp.status_code == 400
    assert "md" in resp.get_json()["error"]


def test_store_requires_file(client):
    resp = client.post("/store", data={})
    assert resp.status_code == 400


def test_store_rejects_non_markdown(client):
    data = {"file": (io.BytesIO(b"data"), "photo.png")}
    resp = client.post("/store", data=data, content_type="multipart/form-data")
    assert resp.status_code == 400
    assert "md" in resp.get_json()["error"]