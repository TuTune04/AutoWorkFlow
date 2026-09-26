# Tiến độ dự án

## Task 1: Dựng khung dự án và cấu hình pytest
- **Trạng thái**: Hoàn thành
- **Các việc đã làm**:
  - Cập nhật [.gitignore](file:///Users/thai/project4fun/automaticWorkFlow/.gitignore): thêm `.venv/`, `__pycache__/`, `.pytest_cache/`, `*.pyc`.
  - Tạo cấu hình [pyproject.toml](file:///Users/thai/project4fun/automaticWorkFlow/pyproject.toml) với package metadata (`todo-cli`, `0.1.0`), dependency `pytest>=7` và cấu hình pytest (`testpaths = ["tests"]`, `pythonpath = ["."]`).
  - Tạo [todo/__init__.py](file:///Users/thai/project4fun/automaticWorkFlow/todo/__init__.py) chứa `__version__ = "0.1.0"`.
  - Tạo [tests/test_smoke.py](file:///Users/thai/project4fun/automaticWorkFlow/tests/test_smoke.py) với hàm test `test_version` kiểm tra version.
  - Khởi tạo môi trường ảo Python `.venv` (`python3 -m venv .venv`).
  - Cài đặt `pytest>=7` vào môi trường ảo (`.venv/bin/python -m pip install -q "pytest>=7"`).
  - Chạy kiểm thử `.venv/bin/python -m pytest -q` và pass 1/1 test.

## Task 2: Model `Task`
- **Trạng thái**: Hoàn thành
- **Các việc đã làm**:
  - Tạo [todo/models.py](file:///Users/thai/project4fun/automaticWorkFlow/todo/models.py):
    - Định nghĩa dataclass `Task` với các trường `id: int`, `title: str`, `done: bool = False`, `created_at: str = ""`.
    - Triển khai phương thức `to_dict(self) -> dict` trả về dict với đúng 4 key: `id`, `title`, `done`, `created_at`.
    - Triển khai classmethod `from_dict(cls, data: dict) -> Task` xác thực dữ liệu đầu vào: kiểm tra `ValueError` khi dữ liệu không phải dict, thiếu key `id` hoặc `title`, `id` không phải int hoặc là bool hoặc `<= 0`, `title` không phải str, `done` không phải bool, `created_at` không phải str; điền giá trị mặc định `done=False`, `created_at=""` khi thiếu.
    - Triển khai hàm `now_iso() -> str` trả về thời gian hiện tại UTC theo định dạng ISO 8601 (`datetime.now(timezone.utc).isoformat(timespec="seconds")`).
  - Tạo [tests/test_models.py](file:///Users/thai/project4fun/automaticWorkFlow/tests/test_models.py):
    - Kiểm tra round-trip `Task.from_dict(t.to_dict()) == t`.
    - Kiểm tra các key và giá trị trả về từ `to_dict()`.
    - Kiểm tra giá trị mặc định của `from_dict` khi thiếu `done` và `created_at`.
    - Kiểm tra raise `ValueError` đối với các trường hợp dữ liệu sai bằng `pytest.mark.parametrize`.
    - Kiểm tra `now_iso()` parse được bằng `datetime.fromisoformat` và có `tzinfo` khác `None`.
  - Chạy kiểm thử `.venv/bin/python -m pytest -q` và toàn bộ 32 tests đều pass.

## Task 3: Lưu trữ JSON (`storage.py`)
- **Trạng thái**: Hoàn thành
- **Các việc đã làm**:
  - Tạo [todo/storage.py](file:///Users/thai/project4fun/automaticWorkFlow/todo/storage.py):
    - Định nghĩa ngoại lệ `StorageError(Exception)`.
    - Triển khai hàm `load_tasks(path: pathlib.Path) -> list[Task]`: trả về `[]` nếu file không tồn tại hoặc rỗng/chỉ chứa khoảng trắng; raise `StorageError` (kèm đường dẫn file trong thông điệp) nếu JSON không hợp lệ, không phải object, thiếu trường `tasks`, `tasks` không phải danh sách, phần tử không hợp lệ với `Task.from_dict`, hoặc trùng lặp `id`.
    - Triển khai hàm `save_tasks(path: pathlib.Path, tasks: list[Task]) -> None`: tự động tạo thư mục cha (`parents=True, exist_ok=True`); ghi nguyên tử qua file tạm (`tempfile.NamedTemporaryFile` cùng thư mục cha, `flush` + `os.fsync`, `os.replace`); dọn dẹp file tạm nếu xảy ra lỗi; định dạng `{"version": 1, "tasks": [...]}` với `ensure_ascii=False, indent=2`, UTF-8 và kết thúc bằng newline.
  - Tạo [tests/test_storage.py](file:///Users/thai/project4fun/automaticWorkFlow/tests/test_storage.py):
    - Kiểm tra `load_tasks` với file không tồn tại trả về `[]` và không tạo file.
    - Kiểm tra file 0 byte và file chỉ chứa khoảng trắng trả về `[]`.
    - Kiểm tra round-trip save và load với tiếng Việt có dấu, file thô không chứa ký tự escape `\u`, kết thúc bằng newline, và cấu trúc version/tasks hợp lệ.
    - Kiểm tra `save_tasks` tự động tạo cây thư mục cha khi chưa tồn tại.
    - Kiểm tra sau khi save không còn file tạm nào trong thư mục.
    - Kiểm tra cơ chế dọn dẹp file tạm khi thao tác lưu gặp sự cố (mock `os.replace`).
    - Kiểm tra `StorageError` và thông điệp chứa đường dẫn file đối với các trường hợp file hỏng (JSON lồng quá sâu, sai định dạng, id trùng) bằng `pytest.mark.parametrize`.
    - Kiểm tra xử lý file không phải UTF-8 hợp lệ raise `StorageError` có chứa đường dẫn file.
  - Chạy kiểm thử `.venv/bin/python -m pytest -q` và toàn bộ 58 tests đều pass.

## Task 4: Logic nghiệp vụ (`service.py`)
- **Trạng thái**: Hoàn thành
- **Các việc đã làm**:
  - Cập nhật [todo/service.py](file:///Users/thai/project4fun/automaticWorkFlow/todo/service.py):
    - Định nghĩa ngoại lệ `TodoError(Exception)` biểu diễn lỗi nghiệp vụ.
    - Triển khai lớp `TodoList`:
      - `__init__(self, path: pathlib.Path)`: lưu đường dẫn `self.path`, gọi `load_tasks` để `StorageError` lan ra ngoài nếu dữ liệu lưu trữ bị lỗi/hỏng; khởi tạo cấu trúc map task theo id.
      - Property `tasks -> list[Task]`: trả về bản sao danh sách và bản sao từng `Task` (dùng `dataclasses.replace`) theo thứ tự `id` tăng dần, chỉnh sửa các phần tử hay list trả về không làm thay đổi dữ liệu nội bộ.
      - Phương thức `_commit(self, new_tasks: dict[int, Task]) -> None`: lưu trạng thái mới ra file (`save_tasks`) trước, chỉ khi thành công mới cập nhật `self._tasks` trong bộ nhớ; nếu lưu thất bại trạng thái bộ nhớ được giữ nguyên (rollback).
      - `_get(self, task_id: int) -> Task`: lấy object nội bộ dùng cho các thao tác nội bộ.
      - `get(task_id: int) -> Task`: tìm và trả về bản sao `Task` theo id; raise `TodoError(f"Không tìm thấy công việc #{task_id}")` nếu không tồn tại.
      - `add(title: str) -> Task`: loại bỏ khoảng trắng thừa hai đầu (`strip()`), raise `TodoError("Tiêu đề không được rỗng")` nếu rỗng; gán `id = max(id hiện có, default=0) + 1`, `created_at=now_iso()`; gọi `_commit` lưu file trước khi cập nhật bộ nhớ và trả về bản sao `Task` mới tạo.
      - `complete(task_id: int) -> Task`: tạo bản sao với `done=True`, gọi `_commit` lưu file và trả về bản sao `Task`.
      - `uncomplete(task_id: int) -> Task`: tạo bản sao với `done=False`, gọi `_commit` lưu file và trả về bản sao `Task`.
      - `edit(task_id: int, new_title: str) -> Task`: kiểm tra task tồn tại, loại bỏ khoảng trắng tiêu đề mới, raise `TodoError("Tiêu đề không được rỗng")` nếu rỗng, tạo bản sao với tiêu đề mới, gọi `_commit` lưu file và trả về bản sao `Task`.
      - `delete(task_id: int) -> Task`: gọi `_commit` lưu trạng thái mới đã bỏ task, và trả về bản sao `Task` đã xoá.
      - `clear_done() -> int`: gọi `_commit` xoá tất cả các công việc có `done=True`, và trả về số lượng công việc đã xoá.
      - `filter(status: str) -> list[Task]`: lọc theo trạng thái `"all"`, `"pending"`, `"done"`, raise `ValueError` nếu trạng thái không hợp lệ; trả về danh sách các bản sao `Task`.
  - Cập nhật [tests/test_service.py](file:///Users/thai/project4fun/automaticWorkFlow/tests/test_service.py):
    - Kiểm tra chuỗi sinh id và quy tắc max+1 (`add` 3 lần -> 1, 2, 3; `delete(2)` rồi `add` -> id 4).
    - Kiểm tra `add` với chuỗi rỗng / toàn khoảng trắng raise `TodoError("Tiêu đề không được rỗng")`, và chuỗi có khoảng trắng hai đầu được strip chuẩn xác.
    - Kiểm tra các thao tác `complete`, `uncomplete`, `edit`, `delete`, `get` với id không tồn tại đều raise `TodoError` bằng `pytest.mark.parametrize`.
    - Kiểm tra tính bền vững của dữ liệu qua nhiều instance `TodoList(path)` độc lập sau mỗi thao tác thêm, sửa, đổi trạng thái, xoá và dọn dẹp task.
    - Kiểm tra hàm `clear_done` trả đúng số lượng task đã xoá, dọn dẹp sạch các task `done=True` và giữ lại task chưa hoàn thành.
    - Kiểm tra hàm `filter` với `"all"`, `"pending"`, `"done"` và raise `ValueError` với giá trị không hợp lệ.
    - Kiểm tra `tasks` property trả về bản sao danh sách độc lập, sắp xếp tăng dần theo id.
    - Kiểm tra `__init__` để `StorageError` lan ra ngoài khi file JSON hỏng.
    - Kiểm tra hỗ trợ unicode tiếng Việt có dấu và kiểu trả về của các phương thức.
    - Kiểm tra `test_tasks_items_are_copies`: đảm bảo `todo.tasks` và `todo.get(id)` trả về các bản sao độc lập, thay đổi thuộc tính trên object trả về không làm thay đổi dữ liệu nội bộ.
    - Kiểm tra `test_state_unchanged_when_save_fails`: kiểm tra tính toàn vẹn và rollback trạng thái trong bộ nhớ cho các thao tác `add`, `complete`, `edit`, `delete`, `clear_done` khi `save_tasks` ném lỗi ngoại lệ (`OSError`).
  - Chạy kiểm thử `.venv/bin/python -m pytest -q` và toàn bộ 80 tests đều pass.

## Task 5: CLI — khung, lệnh `add` và `list`
- **Trạng thái**: Hoàn thành
- **Các việc đã làm**:
  - Tạo [todo/cli.py](file:///Users/thai/project4fun/automaticWorkFlow/todo/cli.py):
    - Triển khai hàm `resolve_path(cli_file: Optional[Union[str, Path]] = None) -> Path`: ưu tiên tham số `cli_file` (`--file`) -> biến môi trường `TODO_FILE` -> đường dẫn mặc định `Path.home() / ".todo.json"`. Hỗ trợ mở rộng `~` bằng `expanduser()`.
    - Triển khai hàm `build_parser() -> argparse.ArgumentParser`: thiết lập parser với `prog="todo"`, tuỳ chọn `--file`, cờ `--version` hiển thị version dự án (`todo 0.1.0`), yêu cầu subcommand bắt buộc (`dest="command"`, `required=True`).
    - Cấu hình subcommand `add`: nhận `title` dạng danh sách từ (`nargs="+"`), nối lại bằng dấu cách, gọi `todo_list.add(title)` và in `Đã thêm #<id>: <title>`.
    - Cấu hình subcommand `list`: hỗ trợ hai cờ loại trừ lẫn nhau `--pending` và `--done` (mặc định hiển thị tất cả), in thông báo `Không có công việc nào.` khi danh sách rỗng, hoặc in từng công việc theo định dạng chuẩn `f"[{'x' if t.done else ' '}] {t.id}. {t.title}"`.
    - Triển khai hàm `main(argv: Optional[list[str]] = None) -> int`: điều phối lệnh, bắt các lỗi ngoại lệ `TodoError` và `StorageError`, in thông báo lỗi `Lỗi: <msg>` ra stderr và trả về mã thoát `1`.
  - Tạo [todo/__main__.py](file:///Users/thai/project4fun/automaticWorkFlow/todo/__main__.py): hỗ trợ thực thi module trực tiếp qua `python -m todo` và thoát mã theo kết quả trả về của hàm `main()`.
  - Tạo [tests/conftest.py](file:///Users/thai/project4fun/automaticWorkFlow/tests/conftest.py): cung cấp fixture `todo_file(tmp_path, monkeypatch)` trả về đường dẫn file tạm và cấu hình các biến môi trường `TODO_FILE` cùng `HOME` trỏ tới `tmp_path` để cô lập kiểm thử, không can thiệp vào file thật của người dùng.
  - Tạo [tests/test_cli.py](file:///Users/thai/project4fun/automaticWorkFlow/tests/test_cli.py):
    - Kiểm tra thứ tự ưu tiên của `resolve_path` (`--file` ghi đè `TODO_FILE`, `TODO_FILE` ghi đè mặc định `Path.home() / ".todo.json"`).
    - Kiểm tra mở rộng `~` từ cả CLI arg và biến môi trường `TODO_FILE`.
    - Kiểm tra cờ `--version` in đúng `todo 0.1.0` và thoát mã 0.
    - Kiểm tra không truyền subcommand gây ra `SystemExit` với mã 2.
    - Kiểm tra lệnh `add` thêm công việc thành công, in thông báo chuẩn stdout và dữ liệu được ghi vào JSON file.
    - Kiểm tra lệnh `add` với tiêu đề rỗng/khoảng trắng trả về mã 1 và stderr bắt đầu bằng `Lỗi: `.
    - Kiểm tra lệnh `list` với danh sách rỗng in `Không có công việc nào.`.
    - Kiểm tra lệnh `list`, `list --pending`, `list --done` in chuẩn định dạng và lọc đúng trạng thái sau khi thêm và hoàn thành công việc.
    - Kiểm tra lệnh `list --done` khi chưa có task nào hoàn thành in `Không có công việc nào.`.
    - Kiểm tra truyền đồng thời `--pending` và `--done` bị từ chối với mã 2.
    - Kiểm tra tuỳ chọn `--file` ghi đè `TODO_FILE` và ghi đúng vào file chỉ định.
    - Kiểm tra xử lý file hỏng: lệnh `list` và `add` trả về mã 1, stderr bắt đầu bằng `Lỗi: ` và chứa đường dẫn file, nội dung file hỏng không bị ghi đè.
    - Kiểm tra chạy subprocess qua `sys.executable -m todo --file <path> add abc` thành công với returncode 0.
  - Chạy kiểm thử `.venv/bin/python -m pytest -q` và toàn bộ 93 tests đều pass.



