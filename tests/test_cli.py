from __future__ import annotations

from pathlib import Path
import subprocess
import sys

import pytest

from todo.cli import build_parser, main, resolve_path
from todo.service import TodoList
from todo.storage import load_tasks


def test_resolve_path_order(monkeypatch: pytest.MonkeyPatch, tmp_path: Path):
    custom_file = tmp_path / "custom.json"
    env_file = tmp_path / "env.json"

    # Khi có cả --file và TODO_FILE -> ưu tiên --file
    monkeypatch.setenv("TODO_FILE", str(env_file))
    assert resolve_path(str(custom_file)) == custom_file

    # Khi chỉ có TODO_FILE -> lấy TODO_FILE
    assert resolve_path(None) == env_file

    # Khi không có TODO_FILE -> mặc định Path.home() / ".todo.json"
    monkeypatch.delenv("TODO_FILE", raising=False)
    monkeypatch.setenv("HOME", str(tmp_path))
    assert resolve_path(None) == tmp_path / ".todo.json"


def test_resolve_path_expanduser(monkeypatch: pytest.MonkeyPatch, tmp_path: Path):
    monkeypatch.setenv("HOME", str(tmp_path))

    # Mở rộng ~ từ tham số cli_file
    assert resolve_path("~/my_todo.json") == tmp_path / "my_todo.json"

    # Mở rộng ~ từ biến môi trường TODO_FILE
    monkeypatch.setenv("TODO_FILE", "~/env_todo.json")
    assert resolve_path(None) == tmp_path / "env_todo.json"


def test_version_flag(capsys: pytest.CaptureFixture[str]):
    parser = build_parser()
    with pytest.raises(SystemExit) as exc_info:
        parser.parse_args(["--version"])
    assert exc_info.value.code == 0
    captured = capsys.readouterr()
    assert "todo 0.1.0" in captured.out


def test_no_subcommand_raises_system_exit():
    with pytest.raises(SystemExit) as exc_info:
        main([])
    assert exc_info.value.code == 2


def test_add_success(todo_file: Path, capsys: pytest.CaptureFixture[str]):
    ret = main(["add", "Mua", "sữa"])
    assert ret == 0

    captured = capsys.readouterr()
    assert "Đã thêm #1: Mua sữa" in captured.out

    tasks = load_tasks(todo_file)
    assert len(tasks) == 1
    assert tasks[0].id == 1
    assert tasks[0].title == "Mua sữa"
    assert tasks[0].done is False


def test_add_empty_title_error(todo_file: Path, capsys: pytest.CaptureFixture[str]):
    ret = main(["add", "   "])
    assert ret == 1

    captured = capsys.readouterr()
    assert captured.err.startswith("Lỗi: ")
    assert "Tiêu đề không được rỗng" in captured.err


def test_list_empty(todo_file: Path, capsys: pytest.CaptureFixture[str]):
    ret = main(["list"])
    assert ret == 0

    captured = capsys.readouterr()
    assert captured.out.strip() == "Không có công việc nào."


def test_list_all_and_filtering(todo_file: Path, capsys: pytest.CaptureFixture[str]):
    assert main(["add", "Công việc 1"]) == 0
    assert main(["add", "Công việc 2"]) == 0

    # Đánh dấu hoàn thành task 2 qua TodoList trực tiếp
    todo_list = TodoList(todo_file)
    todo_list.complete(2)

    # list (mặc định all)
    capsys.readouterr()
    ret_all = main(["list"])
    assert ret_all == 0
    out_all = capsys.readouterr().out
    assert out_all.strip().splitlines() == [
        "[ ] 1. Công việc 1",
        "[x] 2. Công việc 2",
    ]

    # list --pending (chỉ hiện task 1)
    ret_pending = main(["list", "--pending"])
    assert ret_pending == 0
    out_pending = capsys.readouterr().out
    assert out_pending.strip().splitlines() == ["[ ] 1. Công việc 1"]

    # list --done (chỉ hiện task 2)
    ret_done = main(["list", "--done"])
    assert ret_done == 0
    out_done = capsys.readouterr().out
    assert out_done.strip().splitlines() == ["[x] 2. Công việc 2"]


def test_list_filtered_empty(todo_file: Path, capsys: pytest.CaptureFixture[str]):
    assert main(["add", "Việc chưa xong"]) == 0
    capsys.readouterr()

    # Lọc các việc đã xong khi chưa có việc nào xong
    ret = main(["list", "--done"])
    assert ret == 0
    captured = capsys.readouterr()
    assert captured.out.strip() == "Không có công việc nào."


def test_list_mutually_exclusive_flags():
    with pytest.raises(SystemExit) as exc_info:
        main(["list", "--pending", "--done"])
    assert exc_info.value.code == 2


def test_file_flag_overrides_env(todo_file: Path, tmp_path: Path):
    other_file = tmp_path / "other" / "custom.json"
    ret = main(["--file", str(other_file), "add", "Học Python"])
    assert ret == 0
    assert other_file.exists()
    assert not todo_file.exists()

    tasks = load_tasks(other_file)
    assert len(tasks) == 1
    assert tasks[0].title == "Học Python"


def test_corrupted_file_error(todo_file: Path, capsys: pytest.CaptureFixture[str]):
    todo_file.write_text("{not json", encoding="utf-8")

    # main(["list"]) khi file hỏng
    ret_list = main(["list"])
    assert ret_list == 1
    captured_list = capsys.readouterr()
    assert captured_list.err.startswith("Lỗi: ")
    assert str(todo_file) in captured_list.err

    # main(["add", "abc"]) khi file hỏng
    ret_add = main(["add", "abc"])
    assert ret_add == 1
    captured_add = capsys.readouterr()
    assert captured_add.err.startswith("Lỗi: ")
    assert str(todo_file) in captured_add.err

    # File hỏng không bị ghi đè hay sửa
    assert todo_file.read_text(encoding="utf-8") == "{not json"


def test_subprocess_run(tmp_path: Path):
    path = tmp_path / "sub_todo.json"
    repo_root = Path(__file__).resolve().parent.parent

    result = subprocess.run(
        [sys.executable, "-m", "todo", "--file", str(path), "add", "abc"],
        capture_output=True,
        text=True,
        cwd=str(repo_root),
    )
    assert result.returncode == 0
    assert "Đã thêm #1: abc" in result.stdout
    assert path.exists()
