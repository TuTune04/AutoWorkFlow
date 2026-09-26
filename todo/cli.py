from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys
from typing import Optional, Union

from todo import __version__
from todo.service import TodoError, TodoList
from todo.storage import StorageError


def resolve_path(cli_file: Optional[Union[str, Path]] = None) -> Path:
    """Xác định đường dẫn file dữ liệu todo.

    Thứ tự ưu tiên:
    1. Tham số cli_file (--file) nếu có.
    2. Biến môi trường TODO_FILE nếu có.
    3. Mặc định: Path.home() / ".todo.json".

    Mở rộng '~' bằng expanduser().
    """
    if cli_file is not None:
        return Path(cli_file).expanduser()
    env_file = os.environ.get("TODO_FILE")
    if env_file:
        return Path(env_file).expanduser()
    return Path.home() / ".todo.json"


def build_parser() -> argparse.ArgumentParser:
    """Xây dựng bộ phân tích tham số dòng lệnh cho ứng dụng todo."""
    parser = argparse.ArgumentParser(prog="todo")
    parser.add_argument("--file", help="Đường dẫn tới file lưu trữ dữ liệu JSON", default=None)
    parser.add_argument("--version", action="version", version=f"todo {__version__}")

    subparsers = parser.add_subparsers(dest="command", required=True)

    # Subcommand: add
    add_parser = subparsers.add_parser("add", help="Thêm công việc mới")
    add_parser.add_argument("title", nargs="+", help="Tiêu đề công việc")

    # Subcommand: list
    list_parser = subparsers.add_parser("list", help="Liệt kê danh sách công việc")
    list_group = list_parser.add_mutually_exclusive_group()
    list_group.add_argument("--pending", action="store_true", help="Chỉ liệt kê công việc chưa hoàn thành")
    list_group.add_argument("--done", action="store_true", help="Chỉ liệt kê công việc đã hoàn thành")

    # Subcommand: done
    done_parser = subparsers.add_parser("done", help="Đánh dấu công việc đã hoàn thành")
    done_parser.add_argument("id", type=int, help="ID công việc")

    # Subcommand: undone
    undone_parser = subparsers.add_parser("undone", help="Bỏ đánh dấu công việc đã hoàn thành")
    undone_parser.add_argument("id", type=int, help="ID công việc")

    # Subcommand: edit
    edit_parser = subparsers.add_parser("edit", help="Sửa tiêu đề công việc")
    edit_parser.add_argument("id", type=int, help="ID công việc")
    edit_parser.add_argument("title", nargs="+", help="Tiêu đề mới của công việc")

    # Subcommand: delete
    delete_parser = subparsers.add_parser("delete", help="Xoá công việc")
    delete_parser.add_argument("id", type=int, help="ID công việc")

    # Subcommand: clear
    subparsers.add_parser("clear", help="Xoá tất cả công việc đã hoàn thành")

    return parser


def main(argv: Optional[list[str]] = None) -> int:
    """Điểm vào dòng lệnh chính của ứng dụng todo."""
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        path = resolve_path(args.file)
        todo_list = TodoList(path)

        if args.command == "add":
            title = " ".join(args.title)
            task = todo_list.add(title)
            print(f"Đã thêm #{task.id}: {task.title}")
            return 0
        elif args.command == "list":
            if args.pending:
                status = "pending"
            elif args.done:
                status = "done"
            else:
                status = "all"

            tasks = todo_list.filter(status)
            if not tasks:
                print("Không có công việc nào.")
            else:
                for t in tasks:
                    print(f"[{'x' if t.done else ' '}] {t.id}. {t.title}")
            return 0
        elif args.command == "done":
            task = todo_list.complete(args.id)
            print(f"Đã hoàn thành #{task.id}: {task.title}")
            return 0
        elif args.command == "undone":
            task = todo_list.uncomplete(args.id)
            print(f"Đã bỏ đánh dấu #{task.id}: {task.title}")
            return 0
        elif args.command == "edit":
            title = " ".join(args.title)
            task = todo_list.edit(args.id, title)
            print(f"Đã sửa #{task.id}: {task.title}")
            return 0
        elif args.command == "delete":
            task = todo_list.delete(args.id)
            print(f"Đã xoá #{task.id}: {task.title}")
            return 0
        elif args.command == "clear":
            count = todo_list.clear_done()
            print(f"Đã xoá {count} công việc đã hoàn thành.")
            return 0
        else:
            return 2
    except (TodoError, StorageError) as exc:
        print(f"Lỗi: {exc}", file=sys.stderr)
        return 1
