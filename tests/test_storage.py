import json
from pathlib import Path
import pytest

from todo.models import Task
from todo.storage import StorageError, load_tasks, save_tasks


def test_load_nonexistent_file(tmp_path: Path) -> None:
    """Load file không tồn tại trả về [] và không tự tạo file."""
    path = tmp_path / "tasks.json"
    assert not path.exists()

    tasks = load_tasks(path)
    assert tasks == []
    assert not path.exists()


def test_load_empty_or_whitespace_file(tmp_path: Path) -> None:
    """File 0 byte hoặc chỉ chứa khoảng trắng trả về []."""
    empty_file = tmp_path / "empty.json"
    empty_file.write_text("", encoding="utf-8")
    assert load_tasks(empty_file) == []

    whitespace_file = tmp_path / "whitespace.json"
    whitespace_file.write_text("   \n\t  \n", encoding="utf-8")
    assert load_tasks(whitespace_file) == []


def test_save_and_load_roundtrip_vietnamese(tmp_path: Path) -> None:
    """Save rồi load trả về danh sách bằng ban đầu và file thô không chứa mã escape unicode."""
    path = tmp_path / "todo.json"
    original_tasks = [
        Task(id=1, title="Mua sữa tươi", done=False, created_at="2026-09-27T10:00:00+00:00"),
        Task(id=2, title="Viết báo cáo & nấu cơm", done=True, created_at="2026-09-27T11:00:00+00:00"),
    ]

    save_tasks(path, original_tasks)
    loaded_tasks = load_tasks(path)

    assert loaded_tasks == original_tasks

    raw_content = path.read_text(encoding="utf-8")
    assert "Mua sữa tươi" in raw_content
    assert "Viết báo cáo & nấu cơm" in raw_content
    assert "\\u" not in raw_content
    assert raw_content.endswith("\n")

    parsed = json.loads(raw_content)
    assert parsed["version"] == 1
    assert len(parsed["tasks"]) == 2


def test_save_creates_parent_directories(tmp_path: Path) -> None:
    """Save vào thư mục con chưa tồn tại thì tự động tạo thư mục cha."""
    nested_path = tmp_path / "a" / "b" / "todo.json"
    assert not nested_path.parent.exists()

    save_tasks(nested_path, [Task(id=1, title="Công việc test")])

    assert nested_path.exists()
    assert len(load_tasks(nested_path)) == 1


def test_save_leaves_no_temporary_files(tmp_path: Path) -> None:
    """Sau khi save thành công, trong thư mục chỉ có file todo.json, không còn file tạm."""
    dir_path = tmp_path / "data"
    file_path = dir_path / "todo.json"

    save_tasks(file_path, [Task(id=1, title="Test file tạm")])

    files_in_dir = list(dir_path.iterdir())
    assert files_in_dir == [file_path]


def test_save_cleans_up_temp_file_on_failure(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Nếu xảy ra lỗi trong quá trình lưu (ví dụ replace lỗi), file tạm phải được dọn dẹp."""
    import os

    dir_path = tmp_path / "fail_data"
    file_path = dir_path / "todo.json"

    def broken_replace(src: Path, dst: Path) -> None:
        raise OSError("Mô phỏng lỗi khi thay thế file")

    monkeypatch.setattr(os, "replace", broken_replace)

    with pytest.raises(OSError, match="Mô phỏng lỗi khi thay thế file"):
        save_tasks(file_path, [Task(id=1, title="Test lỗi")])

    # Kiểm tra không có file tạm nào còn sót lại trong thư mục
    if dir_path.exists():
        temp_files = [f for f in dir_path.iterdir() if f.name != "todo.json"]
        assert temp_files == []


@pytest.mark.parametrize(
    "corrupt_content",
    [
        "{not json",
        "[]",
        "null",
        "123",
        '"a string"',
        "{}",
        '{"version": 1}',
        '{"tasks": {}}',
        '{"tasks": "not a list"}',
        '{"tasks": 123}',
        '{"tasks": [{"id": 1}]}',  # thiếu title
        '{"tasks": [{"title": "task"}]}',  # thiếu id
        '{"tasks": [{"id": 0, "title": "task"}]}',  # id <= 0
        '{"tasks": [{"id": "1", "title": "task"}]}',  # id không phải int
        '{"tasks": [{"id": true, "title": "task"}]}',  # id là bool
        '{"tasks": [{"id": 1, "title": 123}]}',  # title không phải str
        '{"tasks": [{"id": 1, "title": "task", "done": "yes"}]}',  # done không phải bool
        '{"tasks": [{"id": 1, "title": "a"}, {"id": 1, "title": "b"}]}',  # id trùng lặp
        "[" * 100000,  # JSON lồng quá sâu
    ],
)
def test_corrupted_file_raises_storage_error(tmp_path: Path, corrupt_content: str) -> None:
    """Các trường hợp file hỏng đều raise StorageError có chứa đường dẫn file trong thông điệp."""
    file_path = tmp_path / "corrupt.json"
    file_path.write_text(corrupt_content, encoding="utf-8")

    with pytest.raises(StorageError) as exc_info:
        load_tasks(file_path)

    assert str(file_path) in str(exc_info.value)


def test_invalid_utf8_file_raises_storage_error(tmp_path: Path) -> None:
    """File không phải UTF-8 hợp lệ raise StorageError có chứa đường dẫn file."""
    file_path = tmp_path / "invalid_utf8.json"
    file_path.write_bytes(b"\xff\xfe{")

    with pytest.raises(StorageError) as exc_info:
        load_tasks(file_path)

    assert str(file_path) in str(exc_info.value)

