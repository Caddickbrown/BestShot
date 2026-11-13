"""Web app safety: python3 -m pytest tests/test_web_safety.py (from the repo root).

Everything runs against a temp project folder. No server is started.
"""

import importlib
import inspect
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


@pytest.fixture()
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("PROJECT_ROOT", str(tmp_path))
    main = importlib.import_module("app.main")
    (tmp_path / "keep").mkdir()
    return main.create_app().test_client(), tmp_path


def test_no_cross_origin_access_is_offered(client):
    c, _ = client
    r = c.get("/")
    assert "Access-Control-Allow-Origin" not in r.headers
    assert "Access-Control-Allow-Methods" not in r.headers


def test_another_site_cant_delete_a_project(client):
    c, root = client
    r = c.delete("/api/projects/keep", headers={"Origin": "https://evil.example"})
    assert r.status_code == 403
    assert (root / "keep").is_dir()


def test_another_site_cant_post_either(client):
    c, _ = client
    r = c.post("/api/projects", json={"name": "x"}, headers={"Origin": "https://evil.example"})
    assert r.status_code == 403


def test_the_app_itself_can_still_delete(client):
    c, root = client
    r = c.delete("/api/projects/keep", headers={"Origin": "http://localhost"})
    assert r.status_code != 403
    assert not (root / "keep").exists()


def test_deleting_a_project_moves_its_files_aside_and_hides_them(client):
    c, root = client
    (root / "keep" / "a.jpg").write_bytes(b"\xff\xd8\xff")
    r = c.delete("/api/projects/keep")
    assert r.status_code == 200
    kept = root / r.get_json()["keptAt"]
    assert (kept / "a.jpg").read_bytes() == b"\xff\xd8\xff"
    assert not (root / "keep").exists()
    assert [p["name"] for p in c.get("/api/projects").get_json()["projects"]] == []
    assert c.get("/api/all-media").status_code == 200


def test_a_tool_with_no_origin_still_works(client):
    c, _ = client
    assert c.delete("/api/projects/keep").status_code != 403


def test_running_it_directly_is_local_and_has_no_debugger():
    source = inspect.getsource(importlib.import_module("app.main"))
    tail = source[source.index('if __name__ == "__main__"'):]
    assert "debug=True" not in tail
    assert "0.0.0.0" not in tail
