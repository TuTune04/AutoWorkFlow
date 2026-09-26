import pathlib
from dataclasses import replace

from todo.models import Task, now_iso
from todo.storage import load_tasks, save_tasks


class TodoError(Exception):
    """Lỗi nghiệp vụ của ứng dụng quản lý công việc."""


class TodoList:
    """Quản lý danh sách công việc và thực hiện các thao tác nghiệp vụ."""

    def __init__(self, path: pathlib.Path) -> None:
        self.path = pathlib.Path(path)
        # Gọi load_tasks trực tiếp để StorageError lan ra ngoài nếu file hỏng
        loaded_tasks = load_tasks(self.path)
        self._tasks: dict[int, Task] = {t.id: t for t in loaded_tasks}

    @property
    def tasks(self) -> list[Task]:
        """Danh sách các task theo thứ tự id tăng dần.

        Trả về bản sao danh sách và bản sao các task để thao tác sửa đổi không ảnh hưởng nội bộ.
        """
        return [replace(self._tasks[tid]) for tid in sorted(self._tasks.keys())]

    def _commit(self, new_tasks: dict[int, Task]) -> None:
        """Ghi trạng thái mới ra file trước, chỉ khi thành công mới cập nhật vào bộ nhớ."""
        save_tasks(self.path, [new_tasks[k] for k in sorted(new_tasks)])
        self._tasks = new_tasks

    def _save(self) -> None:
        """Lưu trạng thái công việc hiện tại vào file."""
        save_tasks(self.path, self.tasks)

    def _get(self, task_id: int) -> Task:
        """Lấy object Task nội bộ theo id. Dùng cho các phương thức nội bộ."""
        if isinstance(task_id, bool) or not isinstance(task_id, int):
            raise TodoError(f"Không tìm thấy công việc #{task_id}")

        if task_id not in self._tasks:
            raise TodoError(f"Không tìm thấy công việc #{task_id}")

        return self._tasks[task_id]

    def get(self, task_id: int) -> Task:
        """Lấy thông tin công việc theo id.

        Trả về bản sao của Task để sửa đổi không ảnh hưởng tới trạng thái nội bộ.
        Nếu không tìm thấy -> raise TodoError(f"Không tìm thấy công việc #{task_id}").
        """
        return replace(self._get(task_id))

    def add(self, title: str) -> Task:
        """Thêm một công việc mới.

        - Tiêu đề được strip khoảng trắng.
        - Nếu rỗng -> raise TodoError("Tiêu đề không được rỗng").
        - id mới = max(id hiện có, default=0) + 1.
        - created_at được sinh tự động theo chuẩn ISO UTC.
        - Lưu vào file trước khi cập nhật bộ nhớ; trả về bản sao của Task mới.
        """
        stripped_title = title.strip() if isinstance(title, str) else ""
        if not stripped_title:
            raise TodoError("Tiêu đề không được rỗng")

        new_id = max(self._tasks.keys(), default=0) + 1
        new_task = Task(id=new_id, title=stripped_title, done=False, created_at=now_iso())
        new_tasks = dict(self._tasks)
        new_tasks[new_id] = new_task
        self._commit(new_tasks)
        return replace(new_task)

    def complete(self, task_id: int) -> Task:
        """Đánh dấu công việc đã hoàn thành (done=True), lưu file và trả về bản sao Task."""
        task = self._get(task_id)
        updated_task = replace(task, done=True)
        new_tasks = dict(self._tasks)
        new_tasks[task_id] = updated_task
        self._commit(new_tasks)
        return replace(updated_task)

    def uncomplete(self, task_id: int) -> Task:
        """Bỏ đánh dấu công việc đã hoàn thành (done=False), lưu file và trả về bản sao Task."""
        task = self._get(task_id)
        updated_task = replace(task, done=False)
        new_tasks = dict(self._tasks)
        new_tasks[task_id] = updated_task
        self._commit(new_tasks)
        return replace(updated_task)

    def edit(self, task_id: int, new_title: str) -> Task:
        """Sửa tiêu đề công việc và lưu file.

        - Tiêu đề được strip khoảng trắng; nếu rỗng -> raise TodoError("Tiêu đề không được rỗng").
        - Nếu không tìm thấy công việc -> raise TodoError(f"Không tìm thấy công việc #{task_id}").
        - Trả về bản sao của Task sau khi sửa.
        """
        task = self._get(task_id)
        stripped_title = new_title.strip() if isinstance(new_title, str) else ""
        if not stripped_title:
            raise TodoError("Tiêu đề không được rỗng")

        updated_task = replace(task, title=stripped_title)
        new_tasks = dict(self._tasks)
        new_tasks[task_id] = updated_task
        self._commit(new_tasks)
        return replace(updated_task)

    def delete(self, task_id: int) -> Task:
        """Xoá công việc theo id, lưu file và trả về bản sao task đã xoá."""
        task = self._get(task_id)
        new_tasks = dict(self._tasks)
        new_tasks.pop(task_id)
        self._commit(new_tasks)
        return replace(task)

    def clear_done(self) -> int:
        """Xoá mọi công việc đã hoàn thành (done=True), lưu file và trả về số lượng đã xoá."""
        new_tasks = {tid: t for tid, t in self._tasks.items() if not t.done}
        removed_count = len(self._tasks) - len(new_tasks)
        self._commit(new_tasks)
        return removed_count

    def filter(self, status: str) -> list[Task]:
        """Lọc công việc theo trạng thái: 'all', 'pending', 'done'.

        Giá trị khác -> raise ValueError.
        """
        if status == "all":
            return self.tasks
        elif status == "pending":
            return [t for t in self.tasks if not t.done]
        elif status == "done":
            return [t for t in self.tasks if t.done]
        else:
            raise ValueError(f"Trạng thái '{status}' không hợp lệ. Phải là một trong: 'all', 'pending', 'done'.")
