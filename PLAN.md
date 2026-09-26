# PLAN.md — Ứng dụng todo dòng lệnh (Python + JSON + pytest)

TEST_CMD: .venv/bin/python -m pytest -q

## Tổng quan

Ứng dụng CLI quản lý công việc (todo), dữ liệu lưu trong một file JSON.

- Ngôn ngữ: Python ≥ 3.10, **chỉ dùng thư viện chuẩn** (argparse, json, dataclasses, pathlib, os, tempfile, datetime). Dependency duy nhất cho dev là `pytest`.
- Chạy app: `.venv/bin/python -m todo <lệnh> ...`
- Tất cả lệnh chạy từ thư mục gốc repo. Không đổi `TEST_CMD`.

### Cấu trúc thư mục đích

```
pyproject.toml
.gitignore
README.md
todo/
  __init__.py      # __version__ = "0.1.0"
  __main__.py      # python -m todo
  models.py        # dataclass Task
  storage.py       # đọc/ghi JSON
  service.py       # logic nghiệp vụ TodoList
  cli.py           # argparse, hàm main(argv) -> int
tests/
  conftest.py
  test_smoke.py
  test_models.py
  test_storage.py
  test_service.py
  test_cli.py
```

### Định dạng file JSON (cố định, mọi task phải tuân theo)

```json
{
  "version": 1,
  "tasks": [
    {"id": 1, "title": "Mua sữa", "done": false, "created_at": "2026-09-27T10:00:00+00:00"}
  ]
}
```

- `id`: số nguyên dương, duy nhất; id mới = `max(id hiện có, default=0) + 1`.
- `created_at`: chuỗi ISO 8601 có timezone UTC (`datetime.now(timezone.utc).isoformat(timespec="seconds")`).
- JSON ghi với `ensure_ascii=False, indent=2` và encoding UTF-8.

### Quy ước chung

- Mọi test dùng thư mục tạm của pytest (`tmp_path`), **không bao giờ** đọc/ghi file thật trong home của người dùng.
- Mã thoát CLI: `0` thành công, `1` lỗi nghiệp vụ (không tìm thấy id, tiêu đề rỗng, file hỏng), `2` lỗi cú pháp tham số (mặc định của argparse).
- Thông báo lỗi in ra **stderr** với tiền tố `Lỗi: `; kết quả bình thường in ra **stdout**.
- Không in traceback ra người dùng cho lỗi nghiệp vụ.

---

## Task 1: Dựng khung dự án và cấu hình pytest

**File tạo/sửa:**
- `pyproject.toml`: `[project]` name=`todo-cli`, version=`0.1.0`, `requires-python = ">=3.10"`; `[project.optional-dependencies] dev = ["pytest>=7"]`; `[tool.pytest.ini_options]` với `testpaths = ["tests"]` và `pythonpath = ["."]`.
- `todo/__init__.py`: chỉ chứa `__version__ = "0.1.0"`.
- `tests/test_smoke.py`: một test `test_version` import `todo` và assert `todo.__version__ == "0.1.0"`.
- `.gitignore`: thêm (nếu chưa có) các dòng `.venv/`, `__pycache__/`, `.pytest_cache/`, `*.pyc`. Giữ nguyên các dòng đã có.

**Việc cần làm:**
1. Tạo virtualenv: `python3 -m venv .venv`.
2. Cài pytest: `.venv/bin/python -m pip install -q "pytest>=7"`.
3. Chạy `.venv/bin/python -m pytest -q`.

**Acceptance criteria:**
- `.venv/bin/python -m pytest -q` thoát mã 0, có đúng 1 test pass.
- `.venv/` không bị commit (nằm trong `.gitignore`).

## Task 2: Model `Task`

**File tạo/sửa:** `todo/models.py`, `tests/test_models.py`

**Đặc tả:**
- `@dataclass class Task` với các field: `id: int`, `title: str`, `done: bool = False`, `created_at: str = ""`.
- `Task.to_dict(self) -> dict` trả về dict đúng 4 key `id, title, done, created_at`.
- `@classmethod Task.from_dict(cls, data: dict) -> Task`:
  - Thiếu key `id` hoặc `title` → raise `ValueError`.
  - `id` không phải `int` (hoặc là `bool`) hoặc `<= 0` → `ValueError`.
  - `title` không phải `str` → `ValueError`.
  - `done` thiếu → `False`; nếu có mà không phải `bool` → `ValueError`.
  - `created_at` thiếu → `""`.
- Hàm `now_iso() -> str` trả về thời gian hiện tại UTC dạng ISO như ở phần Tổng quan.

**Acceptance criteria (test trong `tests/test_models.py`):**
- Round-trip: `Task.from_dict(t.to_dict()) == t`.
- `from_dict` điền mặc định `done=False`, `created_at=""` khi thiếu.
- Mỗi trường hợp dữ liệu sai nêu trên đều raise `ValueError` (dùng `pytest.mark.parametrize`).
- `now_iso()` parse được bằng `datetime.fromisoformat` và có `tzinfo` khác `None`.

## Task 3: Lưu trữ JSON (`storage.py`)

**File tạo/sửa:** `todo/storage.py`, `tests/test_storage.py`

**Đặc tả:**
- `class StorageError(Exception)`.
- `load_tasks(path: pathlib.Path) -> list[Task]`:
  - File không tồn tại → trả về `[]` (không tạo file).
  - File rỗng (0 byte hoặc chỉ khoảng trắng) → `[]`.
  - JSON không hợp lệ, không phải object, thiếu key `tasks`, `tasks` không phải list, hoặc một phần tử làm `Task.from_dict` raise `ValueError` → raise `StorageError` với thông điệp chứa đường dẫn file.
  - Id trùng lặp trong file → `StorageError`.
- `save_tasks(path: pathlib.Path, tasks: list[Task]) -> None`:
  - Tạo thư mục cha nếu chưa có (`parents=True, exist_ok=True`).
  - Ghi **nguyên tử**: ghi vào file tạm cùng thư mục (`tempfile.NamedTemporaryFile(dir=..., delete=False)` hoặc `mkstemp`), `flush` + `os.fsync`, rồi `os.replace` sang `path`. Nếu lỗi thì xoá file tạm.
  - Nội dung đúng định dạng `{"version": 1, "tasks": [...]}`, `ensure_ascii=False, indent=2`, UTF-8, kết thúc bằng newline.

**Acceptance criteria (test trong `tests/test_storage.py`, dùng `tmp_path`):**
- Load file không tồn tại → `[]`, và file vẫn không tồn tại sau đó.
- Save rồi load trả về danh sách bằng danh sách ban đầu (kể cả tiêu đề tiếng Việt có dấu; kiểm tra file thô chứa nguyên chữ `"Mua sữa"` chứ không phải `\u`).
- Save vào `tmp_path / "a" / "b" / "todo.json"` tạo được thư mục cha.
- Sau khi save, trong thư mục không còn file tạm nào ngoài `todo.json`.
- Các trường hợp file hỏng (`"{not json"`, `"[]"`, `'{"tasks": {}}'`, task thiếu title, id trùng) đều raise `StorageError` (parametrize).

## Task 4: Logic nghiệp vụ (`service.py`)

**File tạo/sửa:** `todo/service.py`, `tests/test_service.py`

**Đặc tả:**
- `class TodoError(Exception)` — lỗi nghiệp vụ.
- `class TodoList`:
  - `__init__(self, path: pathlib.Path)`: lưu path, gọi `load_tasks` (để `StorageError` lan ra ngoài).
  - `tasks` (property) → list `Task` theo thứ tự id tăng dần (bản sao, sửa list trả về không ảnh hưởng nội bộ).
  - `add(title: str) -> Task`: `title.strip()`; rỗng → `TodoError("Tiêu đề không được rỗng")`; id = max+1; `created_at=now_iso()`; lưu file; trả Task mới.
  - `get(task_id: int) -> Task`: không có → `TodoError(f"Không tìm thấy công việc #{task_id}")`.
  - `complete(task_id) -> Task`, `uncomplete(task_id) -> Task`: đặt `done` tương ứng, lưu file.
  - `edit(task_id, new_title) -> Task`: strip, rỗng → `TodoError`; lưu file.
  - `delete(task_id) -> Task`: xoá và trả task đã xoá; lưu file.
  - `clear_done() -> int`: xoá mọi task `done=True`, trả số lượng đã xoá; lưu file.
  - `filter(status: str) -> list[Task]`: `status` ∈ `{"all", "pending", "done"}`, giá trị khác → `ValueError`.
- Mọi thao tác thay đổi dữ liệu phải gọi `save_tasks` ngay (tạo `TodoList` mới trên cùng path phải thấy thay đổi).

**Acceptance criteria (test trong `tests/test_service.py`):**
- `add` ba lần → id 1, 2, 3; sau đó `delete(2)` rồi `add` → id mới là 4 (quy tắc max+1).
- `add("   ")` raise `TodoError`; `add("  abc  ")` lưu title `"abc"`.
- `complete`/`uncomplete`/`edit`/`delete` với id không tồn tại raise `TodoError`.
- Thay đổi được lưu bền: tạo `TodoList(path)` mới đọc lại thấy đúng trạng thái.
- `clear_done` trả đúng số lượng và chỉ còn task chưa xong.
- `filter("pending")`, `filter("done")`, `filter("all")` trả đúng; `filter("xyz")` raise `ValueError`.

## Task 5: CLI — khung, lệnh `add` và `list`

**File tạo/sửa:** `todo/cli.py`, `todo/__main__.py`, `tests/conftest.py`, `tests/test_cli.py`

**Đặc tả:**
- `todo/cli.py`:
  - `resolve_path(cli_file: str | None) -> Path`: ưu tiên `--file` → biến môi trường `TODO_FILE` → mặc định `Path.home() / ".todo.json"`. Mở rộng `~` bằng `expanduser()`.
  - `build_parser() -> argparse.ArgumentParser` với `prog="todo"`, tuỳ chọn toàn cục `--file PATH`, `--version` (in `todo 0.1.0`), subcommand bắt buộc (`required=True`, `dest="command"`).
  - `main(argv: list[str] | None = None) -> int`: parse, dispatch, bắt `TodoError`/`StorageError` → in `Lỗi: <msg>` ra stderr, trả `1`.
  - Lệnh `add TITLE...`: nối các từ bằng dấu cách; in `Đã thêm #<id>: <title>`.
  - Lệnh `list [--pending | --done]` (hai cờ loại trừ nhau, mặc định all): mỗi dòng dạng `[ ] 1. Mua sữa` hoặc `[x] 2. Viết báo cáo` (định dạng chính xác: `f"[{'x' if t.done else ' '}] {t.id}. {t.title}"`). Danh sách rỗng → in `Không có công việc nào.`
- `todo/__main__.py`: `import sys; from todo.cli import main; sys.exit(main())`.
- `tests/conftest.py`: fixture `todo_file(tmp_path, monkeypatch)` trả `tmp_path / "todo.json"`, đồng thời `monkeypatch.setenv("TODO_FILE", str(path))` và `monkeypatch.setenv("HOME", str(tmp_path))` để không bao giờ chạm file thật.

**Acceptance criteria (test trong `tests/test_cli.py`, gọi `main([...])` trực tiếp và dùng `capsys`):**
- `main(["add", "Mua", "sữa"])` trả 0, stdout chứa `Đã thêm #1: Mua sữa`, file JSON có 1 task.
- `main(["list"])` với file rỗng in `Không có công việc nào.`
- Sau 2 lần add và đánh dấu xong task 2 qua `TodoList` trực tiếp: `list` in đúng 2 dòng theo định dạng; `list --pending` chỉ in task 1; `list --done` chỉ in task 2.
- `main(["add", "   "])` trả 1, stderr bắt đầu bằng `Lỗi: `.
- `--file` ghi đè `TODO_FILE`: `main(["--file", str(other), "add", "x"])` ghi vào `other`, không ghi vào `todo_file`.
- `resolve_path(None)` khi không có `TODO_FILE` (dùng `monkeypatch.delenv`) trả `Path.home() / ".todo.json"`.
- Không có subcommand → `SystemExit` với code 2 (`pytest.raises(SystemExit)`).
- Một test chạy subprocess: `subprocess.run([sys.executable, "-m", "todo", "--file", str(path), "add", "abc"], capture_output=True, text=True, cwd=<gốc repo>)` có `returncode == 0`.

## Task 6: CLI — lệnh `done`, `undone`, `edit`, `delete`, `clear`

**File tạo/sửa:** `todo/cli.py`, `tests/test_cli.py`

**Đặc tả (thêm subcommand, tái dùng `TodoList`):**
- `done ID` → in `Đã hoàn thành #<id>: <title>`.
- `undone ID` → in `Đã bỏ đánh dấu #<id>: <title>`.
- `edit ID TITLE...` → nối từ bằng dấu cách, in `Đã sửa #<id>: <title mới>`.
- `delete ID` → in `Đã xoá #<id>: <title>`.
- `clear` → xoá mọi task đã xong, in `Đã xoá <n> công việc đã hoàn thành.`
- `ID` khai báo `type=int` trong argparse (không phải số → argparse thoát code 2).
- Id không tồn tại → stderr `Lỗi: Không tìm thấy công việc #<id>`, trả 1.

**Acceptance criteria (thêm test vào `tests/test_cli.py`):**
- Mỗi lệnh trên chạy thành công trả 0, in đúng thông điệp, và file JSON phản ánh thay đổi (đọc lại bằng `load_tasks`).
- `done 99`, `undone 99`, `edit 99 x`, `delete 99` đều trả 1 và stderr chứa `Không tìm thấy công việc #99`.
- `edit 1 "   "` trả 1.
- `done abc` → `SystemExit` code 2.
- `clear` khi không có task nào xong in `Đã xoá 0 công việc đã hoàn thành.`

## Task 7: Xử lý file JSON hỏng ở CLI và README

**File tạo/sửa:** `todo/cli.py` (nếu cần), `tests/test_cli.py`, `README.md`

**Đặc tả:**
- Khi file dữ liệu hỏng, mọi lệnh (kể cả `list`) in `Lỗi: ...` (thông điệp có đường dẫn file) ra stderr, trả 1, và **không ghi đè/sửa** file hỏng.
- `README.md` (tiếng Việt): mô tả ngắn, yêu cầu Python ≥ 3.10, cách tạo venv + cài pytest, bảng các lệnh (`add`, `list [--pending|--done]`, `done`, `undone`, `edit`, `delete`, `clear`) kèm ví dụ, cách chọn file dữ liệu (`--file`, `TODO_FILE`, mặc định `~/.todo.json`), cách chạy test bằng đúng `TEST_CMD`.

**Acceptance criteria:**
- Test: ghi `"{not json"` vào `todo_file`; `main(["list"])` và `main(["add", "x"])` đều trả 1, stderr bắt đầu bằng `Lỗi: ` và chứa `str(todo_file)`; nội dung file sau đó vẫn đúng là `"{not json"`.
- Test: `README.md` tồn tại ở gốc repo và chứa các chuỗi `TODO_FILE`, `--file`, `clear`, `.venv/bin/python -m pytest -q`.
- Toàn bộ `.venv/bin/python -m pytest -q` pass.
