from __future__ import annotations

import pathlib
import pytest


@pytest.fixture
def todo_file(tmp_path: pathlib.Path, monkeypatch: pytest.MonkeyPatch) -> pathlib.Path:
    """Fixture cung cấp file todo.json tạm và cấu hình biến môi trường để cô lập kiểm thử."""
    path = tmp_path / "todo.json"
    monkeypatch.setenv("TODO_FILE", str(path))
    monkeypatch.setenv("HOME", str(tmp_path))
    return path
