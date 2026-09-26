from pathlib import Path
import pytest

from todo.models import Task
from todo.service import TodoError, TodoList
from todo.storage import StorageError


def test_add_sequential_ids_and_max_plus_one_rule(tmp_path: Path) -> None:
    """add ba lần -> id 1, 2, 3; sau đó delete(2) rồi add -> id mới là 4 (quy tắc max+1)."""
    file_path = tmp_path / "todo.json"
    todo = TodoList(file_path)

    t1 = todo.add("Task 1")
    t2 = todo.add("Task 2")
    t3 = todo.add("Task 3")

    assert t1.id == 1
    assert t2.id == 2
    assert t3.id == 3
    assert [t.id for t in todo.tasks] == [1, 2, 3]

    deleted = todo.delete(2)
    assert deleted.id == 2
    assert [t.id for t in todo.tasks] == [1, 3]

    t4 = todo.add("Task 4")
    assert t4.id == 4
    assert [t.id for t in todo.tasks] == [1, 3, 4]


def test_add_title_stripping_and_empty_validation(tmp_path: Path) -> None:
    """add('   ') raise TodoError; add('  abc  ') lưu title 'abc'."""
    file_path = tmp_path / "todo.json"
    todo = TodoList(file_path)

    with pytest.raises(TodoError, match="Tiêu đề không được rỗng"):
        todo.add("   ")

    with pytest.raises(TodoError, match="Tiêu đề không được rỗng"):
        todo.add("")

    with pytest.raises(TodoError, match="Tiêu đề không được rỗng"):
        todo.add("\t \n  ")

    task = todo.add("  abc  ")
    assert task.title == "abc"
    assert task.id == 1
    assert task.done is False
    assert task.created_at != ""
    assert todo.tasks[0].title == "abc"


@pytest.mark.parametrize("action", ["complete", "uncomplete", "edit", "delete", "get"])
def test_operations_with_nonexistent_id_raise_todo_error(tmp_path: Path, action: str) -> None:
    """complete/uncomplete/edit/delete/get với id không tồn tại raise TodoError."""
    file_path = tmp_path / "todo.json"
    todo = TodoList(file_path)

    todo.add("Task tồn tại")

    nonexistent_id = 999
    with pytest.raises(TodoError, match=f"Không tìm thấy công việc #{nonexistent_id}"):
        if action == "complete":
            todo.complete(nonexistent_id)
        elif action == "uncomplete":
            todo.uncomplete(nonexistent_id)
        elif action == "edit":
            todo.edit(nonexistent_id, "Tiêu đề mới")
        elif action == "delete":
            todo.delete(nonexistent_id)
        elif action == "get":
            todo.get(nonexistent_id)


def test_changes_persisted_across_instances(tmp_path: Path) -> None:
    """Thay đổi được lưu bền: tạo TodoList(path) mới đọc lại thấy đúng trạng thái."""
    file_path = tmp_path / "todo.json"
    todo1 = TodoList(file_path)

    t1 = todo1.add("Mua sữa")
    t2 = todo1.add("Viết báo cáo")
    t3 = todo1.add("Tập thể dục")

    # Kiểm tra sau khi add
    todo2 = TodoList(file_path)
    assert len(todo2.tasks) == 3
    assert [t.id for t in todo2.tasks] == [1, 2, 3]
    assert [t.title for t in todo2.tasks] == ["Mua sữa", "Viết báo cáo", "Tập thể dục"]

    # Kiểm tra sau khi complete
    todo2.complete(2)
    todo3 = TodoList(file_path)
    assert todo3.get(2).done is True
    assert todo3.get(1).done is False

    # Kiểm tra sau khi uncomplete
    todo3.uncomplete(2)
    todo4 = TodoList(file_path)
    assert todo4.get(2).done is False

    # Kiểm tra sau khi edit
    todo4.edit(1, "Mua sữa đặc")
    todo5 = TodoList(file_path)
    assert todo5.get(1).title == "Mua sữa đặc"

    # Kiểm tra sau khi delete
    todo5.delete(2)
    todo6 = TodoList(file_path)
    assert len(todo6.tasks) == 2
    assert [t.id for t in todo6.tasks] == [1, 3]

    # Kiểm tra sau khi clear_done
    todo6.complete(1)
    todo6.clear_done()
    todo7 = TodoList(file_path)
    assert len(todo7.tasks) == 1
    assert todo7.tasks[0].id == 3


def test_clear_done(tmp_path: Path) -> None:
    """clear_done trả đúng số lượng và chỉ còn task chưa xong."""
    file_path = tmp_path / "todo.json"
    todo = TodoList(file_path)

    todo.add("Task 1")
    todo.add("Task 2")
    todo.add("Task 3")
    todo.add("Task 4")

    todo.complete(1)
    todo.complete(3)

    removed_count = todo.clear_done()
    assert removed_count == 2
    assert [t.id for t in todo.tasks] == [2, 4]
    assert all(not t.done for t in todo.tasks)

    # Khi không còn task nào done, clear_done trả về 0 và giữ nguyên
    assert todo.clear_done() == 0
    assert [t.id for t in todo.tasks] == [2, 4]

    # Khi hoàn thành hết, clear_done trả về toàn bộ
    todo.complete(2)
    todo.complete(4)
    assert todo.clear_done() == 2
    assert todo.tasks == []


def test_filter_valid_and_invalid_status(tmp_path: Path) -> None:
    """filter('pending'), filter('done'), filter('all') trả đúng; filter('xyz') raise ValueError."""
    file_path = tmp_path / "todo.json"
    todo = TodoList(file_path)

    todo.add("Việc 1")
    todo.add("Việc 2")
    todo.add("Việc 3")

    todo.complete(2)

    all_tasks = todo.filter("all")
    assert [t.id for t in all_tasks] == [1, 2, 3]

    pending_tasks = todo.filter("pending")
    assert [t.id for t in pending_tasks] == [1, 3]

    done_tasks = todo.filter("done")
    assert [t.id for t in done_tasks] == [2]

    # filter với giá trị không hợp lệ
    with pytest.raises(ValueError):
        todo.filter("xyz")

    with pytest.raises(ValueError):
        todo.filter("ALL")

    with pytest.raises(ValueError):
        todo.filter("")


def test_tasks_property_returns_independent_sorted_copy(tmp_path: Path) -> None:
    """tasks property trả về list độc lập được sắp xếp theo id tăng dần."""
    file_path = tmp_path / "todo.json"
    todo = TodoList(file_path)

    todo.add("Task 1")
    todo.add("Task 2")

    tasks_copy = todo.tasks
    assert len(tasks_copy) == 2

    # Sửa đổi list copy không ảnh hưởng tới tasks nội bộ
    tasks_copy.append(Task(id=99, title="Fake task"))
    assert len(todo.tasks) == 2

    tasks_copy.clear()
    assert len(todo.tasks) == 2


def test_edit_empty_title_validation(tmp_path: Path) -> None:
    """edit với tiêu đề rỗng raise TodoError và không sửa đổi tiêu đề hiện tại."""
    file_path = tmp_path / "todo.json"
    todo = TodoList(file_path)

    task = todo.add("Tiêu đề gốc")

    with pytest.raises(TodoError, match="Tiêu đề không được rỗng"):
        todo.edit(task.id, "   ")

    assert todo.get(task.id).title == "Tiêu đề gốc"

    # Sửa hợp lệ với khoảng trắng xung quanh
    updated = todo.edit(task.id, "   Tiêu đề mới   ")
    assert updated.title == "Tiêu đề mới"
    assert todo.get(task.id).title == "Tiêu đề mới"


def test_init_propagates_storage_error(tmp_path: Path) -> None:
    """__init__ gọi load_tasks và để StorageError lan ra ngoài nếu file hỏng."""
    corrupted_file = tmp_path / "corrupted.json"
    corrupted_file.write_text("{broken json", encoding="utf-8")

    with pytest.raises(StorageError):
        TodoList(corrupted_file)


def test_tasks_property_sorts_by_id_ascending(tmp_path: Path) -> None:
    """tasks property luôn sắp xếp theo id tăng dần kể cả khi dữ liệu file không theo thứ tự."""
    from todo.storage import save_tasks

    file_path = tmp_path / "todo.json"
    raw_tasks = [
        Task(id=5, title="Task 5"),
        Task(id=2, title="Task 2"),
        Task(id=8, title="Task 8"),
        Task(id=1, title="Task 1"),
    ]
    save_tasks(file_path, raw_tasks)

    todo = TodoList(file_path)
    assert [t.id for t in todo.tasks] == [1, 2, 5, 8]


def test_file_not_created_until_first_mutation(tmp_path: Path) -> None:
    """Khởi tạo TodoList với file chưa tồn tại không tạo file cho đến khi có thao tác thay đổi."""
    file_path = tmp_path / "sub" / "todo.json"
    todo = TodoList(file_path)
    assert not file_path.exists()
    assert todo.tasks == []

    todo.add("Task đầu tiên")
    assert file_path.exists()
    assert len(todo.tasks) == 1


def test_method_return_types_and_vietnamese(tmp_path: Path) -> None:
    """Kiểm tra kiểu trả về của các phương thức và hỗ trợ unicode tiếng Việt."""
    file_path = tmp_path / "todo.json"
    todo = TodoList(file_path)

    added = todo.add("Mua sữa chua & bánh mì")
    assert isinstance(added, Task)
    assert added.id == 1
    assert added.title == "Mua sữa chua & bánh mì"

    completed = todo.complete(1)
    assert isinstance(completed, Task)
    assert completed.done is True

    uncompleted = todo.uncomplete(1)
    assert isinstance(uncompleted, Task)
    assert uncompleted.done is False

    edited = todo.edit(1, "Nấu cơm tối")
    assert isinstance(edited, Task)
    assert edited.title == "Nấu cơm tối"

    deleted = todo.delete(1)
    assert isinstance(deleted, Task)
    assert deleted.id == 1
    assert deleted.title == "Nấu cơm tối"
    assert todo.tasks == []


def test_tasks_items_are_copies(tmp_path: Path) -> None:
    """todo.tasks và todo.get trả về bản sao, sửa các thuộc tính không ảnh hưởng nội bộ."""
    file_path = tmp_path / "todo.json"
    todo = TodoList(file_path)
    todo.add("a")

    todo.tasks[0].done = True
    todo.get(1).title = "x"

    assert todo.get(1).done is False
    assert todo.get(1).title == "a"


@pytest.mark.parametrize("operation", ["add", "complete", "edit", "delete", "clear_done"])
def test_state_unchanged_when_save_fails(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, operation: str) -> None:
    """Khi save_tasks gặp lỗi, trạng thái trong bộ nhớ không bị thay đổi (rollback)."""
    file_path = tmp_path / "todo.json"
    todo = TodoList(file_path)
    todo.add("Task 1")
    todo.add("Task 2")
    todo.complete(2)

    snapshot = [t.to_dict() for t in todo.tasks]

    def mock_save_tasks(path, tasks):
        raise OSError("Lỗi ghi đĩa")

    monkeypatch.setattr("todo.service.save_tasks", mock_save_tasks)

    with pytest.raises(OSError):
        if operation == "add":
            todo.add("Task 3")
        elif operation == "complete":
            todo.complete(1)
        elif operation == "edit":
            todo.edit(1, "Tiêu đề mới")
        elif operation == "delete":
            todo.delete(1)
        elif operation == "clear_done":
            todo.clear_done()

    assert [t.to_dict() for t in todo.tasks] == snapshot
