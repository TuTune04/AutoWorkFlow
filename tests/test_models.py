from datetime import datetime
import pytest
from todo.models import Task, now_iso


def test_round_trip():
    """Kiểm tra round-trip: Task.from_dict(t.to_dict()) == t."""
    tasks = [
        Task(id=1, title="Mua sữa", done=False, created_at="2026-09-27T10:00:00+00:00"),
        Task(id=2, title="Viết báo cáo", done=True, created_at="2026-09-27T11:00:00+00:00"),
        Task(id=3, title="Task không có thời gian", done=False, created_at=""),
        Task(id=4, title="Task đã xong không có thời gian", done=True, created_at=""),
    ]
    for t in tasks:
        assert Task.from_dict(t.to_dict()) == t


def test_to_dict_keys():
    """Task.to_dict trả về dict đúng 4 key: id, title, done, created_at."""
    t = Task(id=1, title="Test", done=False, created_at="2026-09-27T10:00:00+00:00")
    d = t.to_dict()
    assert set(d.keys()) == {"id", "title", "done", "created_at"}
    assert d == {
        "id": 1,
        "title": "Test",
        "done": False,
        "created_at": "2026-09-27T10:00:00+00:00",
    }


def test_from_dict_defaults():
    """from_dict điền mặc định done=False, created_at='' khi thiếu."""
    data = {"id": 1, "title": "Mua sữa"}
    task = Task.from_dict(data)
    assert task.id == 1
    assert task.title == "Mua sữa"
    assert task.done is False
    assert task.created_at == ""

    # Chỉ có done, thiếu created_at
    task_done = Task.from_dict({"id": 2, "title": "Đi chợ", "done": True})
    assert task_done.id == 2
    assert task_done.title == "Đi chợ"
    assert task_done.done is True
    assert task_done.created_at == ""

    # Chỉ có created_at, thiếu done
    task_created = Task.from_dict(
        {"id": 3, "title": "Học bài", "created_at": "2026-09-27T10:00:00+00:00"}
    )
    assert task_created.id == 3
    assert task_created.title == "Học bài"
    assert task_created.done is False
    assert task_created.created_at == "2026-09-27T10:00:00+00:00"


@pytest.mark.parametrize(
    "invalid_data",
    [
        # Không phải dict
        None,
        "not a dict",
        123,
        [1, 2, 3],
        # Thiếu key id
        {"title": "Mua sữa"},
        # Thiếu key title
        {"id": 1},
        # Thiếu cả hai
        {},
        # id không phải int (hoặc là bool)
        {"id": True, "title": "Mua sữa"},
        {"id": False, "title": "Mua sữa"},
        {"id": "1", "title": "Mua sữa"},
        {"id": 1.5, "title": "Mua sữa"},
        {"id": None, "title": "Mua sữa"},
        # id <= 0
        {"id": 0, "title": "Mua sữa"},
        {"id": -1, "title": "Mua sữa"},
        {"id": -100, "title": "Mua sữa"},
        # title không phải str
        {"id": 1, "title": 123},
        {"id": 1, "title": True},
        {"id": 1, "title": None},
        {"id": 1, "title": ["Mua sữa"]},
        {"id": 1, "title": {"title": "Mua sữa"}},
        # done có nhưng không phải bool
        {"id": 1, "title": "Mua sữa", "done": "False"},
        {"id": 1, "title": "Mua sữa", "done": 1},
        {"id": 1, "title": "Mua sữa", "done": 0},
        {"id": 1, "title": "Mua sữa", "done": None},
        # created_at có nhưng không phải str
        {"id": 1, "title": "Mua sữa", "created_at": 12345},
        {"id": 1, "title": "Mua sữa", "created_at": None},
        {"id": 1, "title": "Mua sữa", "created_at": True},
    ],
)
def test_from_dict_invalid_data(invalid_data):
    """Mỗi trường hợp dữ liệu sai đều raise ValueError."""
    with pytest.raises(ValueError):
        Task.from_dict(invalid_data)


def test_now_iso():
    """now_iso() parse được bằng datetime.fromisoformat và có tzinfo khác None."""
    iso_str = now_iso()
    assert isinstance(iso_str, str)
    dt = datetime.fromisoformat(iso_str)
    assert dt.tzinfo is not None
