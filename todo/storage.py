import json
import os
import pathlib
import tempfile

from todo.models import Task


class StorageError(Exception):
    """Lỗi khi đọc hoặc ghi file lưu trữ công việc."""


def load_tasks(path: pathlib.Path) -> list[Task]:
    """Đọc danh sách công việc từ file JSON.

    - File không tồn tại -> [] (không tạo file).
    - File rỗng (0 byte hoặc chỉ khoảng trắng) -> [].
    - JSON không hợp lệ, không phải object, thiếu key tasks, tasks không phải list,
      hoặc phần tử không hợp lệ, hoặc id trùng lặp -> raise StorageError.
    """
    path = pathlib.Path(path)

    if not path.exists():
        return []

    if path.is_dir():
        raise StorageError(f"Đường dẫn lưu trữ {path} là một thư mục, không phải file.")

    try:
        content = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as e:
        raise StorageError(f"Không thể đọc file {path}: {e}") from e

    if not content.strip():
        return []

    try:
        data = json.loads(content)
    except (json.JSONDecodeError, RecursionError) as e:
        raise StorageError(f"File {path} chứa JSON không hợp lệ: {e}") from e

    if not isinstance(data, dict):
        raise StorageError(f"Dữ liệu trong file {path} không phải là JSON object.")

    if "tasks" not in data:
        raise StorageError(f"File {path} thiếu trường 'tasks'.")

    tasks_raw = data["tasks"]
    if not isinstance(tasks_raw, list):
        raise StorageError(f"Trường 'tasks' trong file {path} không phải là danh sách.")

    tasks: list[Task] = []
    seen_ids: set[int] = set()

    for item in tasks_raw:
        try:
            task = Task.from_dict(item)
        except ValueError as e:
            raise StorageError(f"Dữ liệu công việc trong file {path} không hợp lệ: {e}") from e

        if task.id in seen_ids:
            raise StorageError(f"Phát hiện id trùng lặp #{task.id} trong file {path}.")

        seen_ids.add(task.id)
        tasks.append(task)

    return tasks


def save_tasks(path: pathlib.Path, tasks: list[Task]) -> None:
    """Lưu danh sách công việc vào file JSON theo cách nguyên tử.

    - Tạo thư mục cha nếu chưa có.
    - Ghi vào file tạm cùng thư mục, flush + fsync, rồi replace sang path.
    - Nếu có lỗi, đảm bảo file tạm bị xoá.
    """
    path = pathlib.Path(path)
    parent_dir = path.parent
    parent_dir.mkdir(parents=True, exist_ok=True)

    data = {
        "version": 1,
        "tasks": [t.to_dict() for t in tasks],
    }
    content = json.dumps(data, ensure_ascii=False, indent=2) + "\n"

    tmp_file = tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=parent_dir,
        delete=False,
        prefix=f".{path.name}.tmp.",
    )
    tmp_path = pathlib.Path(tmp_file.name)

    try:
        tmp_file.write(content)
        tmp_file.flush()
        os.fsync(tmp_file.fileno())
        tmp_file.close()
        os.replace(tmp_path, path)
    except BaseException:
        if not tmp_file.closed:
            tmp_file.close()
        try:
            tmp_path.unlink(missing_ok=True)
        except OSError:
            pass
        raise
