from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any


def now_iso() -> str:
    """Trả về thời gian hiện tại UTC dạng chuỗi ISO 8601."""
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


@dataclass
class Task:
    id: int
    title: str
    done: bool = False
    created_at: str = ""

    def to_dict(self) -> dict[str, Any]:
        """Trả về dict chứa đúng 4 key: id, title, done, created_at."""
        return {
            "id": self.id,
            "title": self.title,
            "done": self.done,
            "created_at": self.created_at,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Task":
        """Khởi tạo Task từ dict dữ liệu.
        
        Raise ValueError nếu dữ liệu thiếu hoặc không hợp lệ.
        """
        if not isinstance(data, dict):
            raise ValueError("Dữ liệu phải là dictionary")

        if "id" not in data or "title" not in data:
            raise ValueError("Thiếu trường 'id' hoặc 'title'")

        task_id = data["id"]
        if isinstance(task_id, bool) or not isinstance(task_id, int) or task_id <= 0:
            raise ValueError(f"id không hợp lệ: {task_id!r}")

        title = data["title"]
        if not isinstance(title, str):
            raise ValueError(f"title không hợp lệ: {title!r}")

        if "done" in data:
            done = data["done"]
            if not isinstance(done, bool):
                raise ValueError(f"done không hợp lệ: {done!r}")
        else:
            done = False

        if "created_at" in data:
            created_at = data["created_at"]
            if not isinstance(created_at, str):
                raise ValueError(f"created_at không hợp lệ: {created_at!r}")
        else:
            created_at = ""

        return cls(id=task_id, title=title, done=done, created_at=created_at)
