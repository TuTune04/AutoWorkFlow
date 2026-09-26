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
