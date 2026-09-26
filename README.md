# todo-cli — Ứng dụng quản lý công việc dòng lệnh

Ứng dụng CLI quản lý công việc (todo list) đơn giản, nhẹ và tin cậy được viết bằng Python. Dữ liệu công việc được lưu trữ dưới định dạng JSON nguyên tử và chỉ sử dụng thư viện chuẩn của Python.

---

## 1. Yêu cầu hệ thống

- **Python**: phiên bản ≥ 3.10.
- Không có dependency bên ngoài khi chạy ứng dụng; dependency duy nhất cho môi trường phát triển (dev) là `pytest`.

---

## 2. Cài đặt và thiết lập môi trường

Khởi tạo môi trường ảo (virtualenv) và cài đặt `pytest`:

```bash
# Tạo môi trường ảo .venv
python3 -m venv .venv

# Cài đặt pytest vào môi trường ảo
.venv/bin/python -m pip install -q "pytest>=7"
```

---

## 3. Cách chọn file dữ liệu

Ứng dụng xác định vị trí file lưu trữ dữ liệu JSON theo thứ tự ưu tiên sau:

1. **Tuỳ chọn `--file PATH`**: Chỉ định trực tiếp file dữ liệu qua tham số dòng lệnh.
   ```bash
   .venv/bin/python -m todo --file ./my_tasks.json list
   ```
2. **Biến môi trường `TODO_FILE`**: Thiết lập đường dẫn thông qua biến môi trường.
   ```bash
   export TODO_FILE=~/tasks.json
   .venv/bin/python -m todo list
   ```
3. **Mặc định**: Nếu không cung cấp `--file` hay `TODO_FILE`, ứng dụng sẽ lưu vào `~/.todo.json`.

*(Hỗ trợ mở rộng ký tự `~` thành thư mục home của người dùng)*

---

## 4. Bảng các lệnh và ví dụ sử dụng

Cú pháp thực thi chung:

```bash
.venv/bin/python -m todo [--file PATH] <lệnh> [tham số...]
```

| Lệnh | Cú pháp | Mô tả | Ví dụ |
| :--- | :--- | :--- | :--- |
| `add` | `todo add <tiêu đề...>` | Thêm một công việc mới vào danh sách | `.venv/bin/python -m todo add Mua sữa tươi` |
| `list` | `todo list [--pending \| --done]` | Liệt kê danh sách công việc (mặc định tất cả; `--pending` chỉ việc chưa hoàn thành; `--done` chỉ việc đã xong) | `.venv/bin/python -m todo list`<br>`.venv/bin/python -m todo list --pending`<br>`.venv/bin/python -m todo list --done` |
| `done` | `todo done <id>` | Đánh dấu công việc có ID tương ứng là đã hoàn thành | `.venv/bin/python -m todo done 1` |
| `undone` | `todo undone <id>` | Bỏ đánh dấu đã hoàn thành cho công việc có ID tương ứng | `.venv/bin/python -m todo undone 1` |
| `edit` | `todo edit <id> <tiêu đề mới...>` | Chỉnh sửa tiêu đề của công việc | `.venv/bin/python -m todo edit 1 Mua sữa tươi tiệt trùng` |
| `delete` | `todo delete <id>` | Xoá bỏ một công việc khỏi danh sách theo ID | `.venv/bin/python -m todo delete 1` |
| `clear` | `todo clear` | Xoá tất cả các công việc đã hoàn thành | `.venv/bin/python -m todo clear` |

---

## 5. Chạy kiểm thử

Kiểm thử toàn bộ hệ thống bằng lệnh pytest:

```bash
.venv/bin/python -m pytest -q
```
