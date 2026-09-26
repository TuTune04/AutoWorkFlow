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
