---
name: autowf
description: Chạy pipeline tự động viết phần mềm theo từng task, không cần gói Claude trả phí — Codex viết PLAN.md, Antigravity (agy, Gemini) viết code cho từng task, Codex review diff + kết quả test rồi commit "Task N" (mọi commit chỉ mang tên người dùng). Dùng khi người dùng muốn "lên plan rồi để agent code", "chạy autowf/auto.sh", hoặc chạy tiếp/dừng một pipeline autowf. Không dùng cho việc sửa code thông thường trong một lần.
---

# autowf (Codex / Antigravity) — Codex lên plan, agy code, Codex review

Toàn bộ pipeline nằm trong `scripts/auto.sh` cạnh file SKILL.md này (gọi nó là `SCRIPT`; dùng đường dẫn tuyệt đối
của thư mục chứa SKILL.md bạn vừa đọc). Script tự làm mọi thứ: tạo branch `auto/*`, gọi `codex exec` viết plan,
gọi `agy -p` cho từng task, tự chạy `TEST_CMD`, gọi `codex exec` (sandbox chỉ đọc) review, sửa lại tối đa
`MAX_TRIES` vòng, rồi commit `Task N: <tiêu đề>`. Bộ agent đặt trong `defaults.env` cạnh SKILL.md.

**Vai trò của bạn chỉ là điều phối:** chạy script, trình plan cho người dùng duyệt, theo dõi, và xử lý khi script
dừng. Không tự viết PLAN.md hay code thay cho các agent, và không tự commit thay cho script (trừ khi ghi quyết định
của người dùng vào PLAN.md như bước 3 và 5).

**Quy tắc commit (bắt buộc):** mọi commit chỉ mang tác giả là người dùng (`GIT_USER_NAME`/`GIT_USER_EMAIL` trong
`.autowf.env` nếu có, không thì `git config user.name/user.email`). Không thêm `Co-Authored-By:` hay dòng
"Generated with ..." của Codex, ChatGPT, Gemini, Claude hay bất kỳ công cụ nào. Không đổi `git config user.*` và
không dùng `--author`. Script tự bỏ các trailer đó và dừng nếu chưa có tác giả hoặc tác giả trông như AI/bot.

## Nguyên tắc: hỏi ít nhất có thể

Cả quy trình **chỉ có tối đa hai lần hỏi**, mỗi lần một câu ngắn bằng văn bản rồi chờ trả lời: (a) xin phép cài
agent còn thiếu (nếu có), (b) duyệt plan (bỏ qua nếu người dùng nói "chạy luôn"). Không hỏi thêm chi tiết dự án khi
mô tả đã đủ — planner tự chọn giả định hợp lý; người dùng sửa lúc duyệt plan. Không hỏi "tiếp tục nhé?" giữa các bước.

## Chạy SCRIPT trong harness này

Script gọi lồng `codex exec` và `agy -p`: chúng cần mạng và ghi được vào `~/.codex`, `~/.gemini`. Vì vậy:

- **Codex:** chạy SCRIPT ngoài sandbox — xin quyền nâng cao (escalated / không sandbox) cho đúng lệnh SCRIPT.
  Trong sandbox `workspace-write` mặc định, lệnh `codex exec` lồng bên trong sẽ không gọi được API.
- **Antigravity:** lệnh SCRIPT phải được cho phép (allowlist hoặc người dùng duyệt khi được hỏi).
- Lệnh ngắn (`--check`, `--plan-only`, `--stop-after`) chạy trực tiếp và chờ kết quả.
- Pipeline (bước 4) có thể chạy hàng giờ, lâu hơn giới hạn thời gian một lệnh của harness: chạy tách nền
  `mkdir -p .auto-logs && setsid nohup SCRIPT > .auto-logs/pipeline.out 2>&1 < /dev/null &`, khoảng 30 giây sau
  đọc `.auto-logs/run.log` để chắc nó đang chạy. Nếu tiến trình bị harness dừng theo lệnh, đưa người dùng đúng một lệnh để chạy trong
  terminal của họ: `cd <repo đích> && SCRIPT`.

## 1. Bộ agent (không hỏi)

Mặc định: Codex viết plan, `agy` code, Codex (model `luna`) review. Chỉ khi người dùng yêu cầu đổi mới ghi vào
`.autowf.env` ở gốc repo đích (tạo nếu chưa có, giữ các dòng khác) — các biến ở đó thắng `defaults.env`:

```bash
CODER=gemini
REVIEW_MODEL=
```

Agent: `claude` | `codex` | `gemini` | `agy`; model rỗng = mặc định của agent (đổi agent mà không đặt model thì
model mặc định của vai trò đó bị bỏ). Codex báo sai model `luna` thì đặt `REVIEW_MODEL=` (mặc định của Codex) hoặc
đúng tên model người dùng muốn. Tác giả commit khác `git config`: `GIT_USER_NAME`, `GIT_USER_EMAIL`.

## 2. Kiểm tra môi trường

Chạy ở gốc repo đích (không phải thư mục skill). Repo đích chưa phải git repo thì cứ để script tự `git init`.

- `SCRIPT --check` — in bộ agent, kiểm tra agent đã cài chưa, tác giả commit, PLAN.md, git và git hook. Thiếu agent
  thì hỏi **một lần** xin cài tất cả agent còn thiếu, được đồng ý thì cài:
  - Codex CLI: `npm i -g @openai/codex`; Gemini CLI: `npm i -g @google/gemini-cli`.
  - Antigravity CLI (`agy`): người dùng tự cài; quyền lệnh của agy nằm trong `~/.gemini/config/config.json`
    (preflight của script in đúng quy tắc còn thiếu — trình nguyên văn cho người dùng).
- Đăng nhập: thử trước (`codex login status`); chỉ khi chưa đăng nhập mới nhờ người dùng chạy `codex login`
  (trong Codespaces/container: `codex login --device-auth`). Người dùng dán URL
  `http://127.0.0.1:1455/auth/callback?...` thì gửi nó tới tiến trình `codex login` đang chờ bằng `curl '<URL>'`.
- `git status --porcelain` phải sạch. Chỉ khi không sạch mới hỏi người dùng muốn commit hay stash; không tự quyết.

## 3. Viết plan (chỉ khi chưa có PLAN.md)

Mô tả dự án lấy từ yêu cầu của người dùng; chỉ hỏi khi không có. Mô tả ngắn thì tự bổ sung giả định hợp lý (stack
đơn giản, không phụ thuộc ngoài, có test chạy được) vào mô tả gửi cho planner.

- Người dùng muốn chạy luôn: chạy `SCRIPT "<mô tả dự án>"` theo cách chạy pipeline ở trên — viết plan rồi code luôn.
- Mặc định: `SCRIPT --plan-only "<mô tả dự án>"` (có thể mất vài phút). Trình bày ngắn `TEST_CMD`, danh sách
  `## Task N`, giả định đáng chú ý, rồi hỏi **một câu**: chạy luôn hay sửa gì. Đồng ý (kể cả "ok", "chạy đi") là
  chạy bước 4 ngay. Nếu sửa: sửa PLAN.md theo ý họ, giữ đúng định dạng (dòng `TEST_CMD: ...`, heading
  `## Task N: <tiêu đề>` đánh số liên tục từ 1), `git commit -am "PLAN.md: <thay đổi>"` (message một dòng, không
  trailer co-author), rồi chạy bước 4 luôn — không hỏi duyệt lại.

Đã có PLAN.md thì bỏ qua bước này (task đã có commit "Task N" sẽ được bỏ qua — chạy tiếp được).

## 4. Chạy pipeline

Chạy `SCRIPT` theo mục "Chạy SCRIPT trong harness này". Khi người dùng hỏi tiến độ: `tail .auto-logs/run.log` hoặc
`git log --oneline`. Muốn dừng: `SCRIPT --stop-after` (dừng sau khi task hiện tại xong; huỷ: `--no-stop-after`).

## 5. Khi script kết thúc

Đọc `.auto-logs/summary.md` (mã thoát ở cuối `.auto-logs/pipeline.out` hoặc dòng "Kết thúc" trong summary) và báo:

| Mã | Ý nghĩa | Việc cần làm |
|---|---|---|
| 0 | Xong hết (hoặc dừng theo `--stop-after`) | Tóm tắt các task, nits trong `.auto-logs/nits.md`, branch `auto/*` để người dùng merge |
| 1 | Task FAIL sau khi hết số vòng sửa (hoặc chưa có tác giả commit hợp lệ) | Trình `REVIEW.md` + log `.auto-logs/task<N>-*`; đề xuất làm rõ/chia nhỏ task trong PLAN.md, hoặc sửa tay rồi `SCRIPT --adopt N` |
| 2 | Cầu dao (agent không sửa file, rời branch, lệnh bị từ chối...) | Trình thông báo lỗi và "Cách xử lý" script in ra |
| 3 | Chờ hết hạn mức quá `MAX_WAIT_HOURS` | Báo giờ reset; chạy lại sau |
| 4 | Không gọi được reviewer | Kiểm tra Codex đăng nhập / mạng / tên model (`REVIEW_MODEL`) |
| 5 | Preflight chưa đạt (đăng nhập agy, quyền lệnh, ghi file, git hook) | Trình báo cáo và quy tắc cần thêm vào `~/.gemini/config/config.json` |
| 6 | Dịch vụ trong `REQUIRE_CMD` chưa chạy | Nhờ người dùng bật dịch vụ |
| 7 | plan-gap: PLAN.md thiếu một quyết định | Trình các lựa chọn reviewer nêu, **hỏi người dùng quyết**, ghi vào đúng phần Task đó trong PLAN.md (không đổi heading), commit, rồi chạy lại bước 4 |

Sau khi xử lý xong, chạy lại `SCRIPT` — task đã commit được bỏ qua.

## Cấu hình

Thứ tự ưu tiên: mặc định của script < `defaults.env` của skill < `.autowf.env` ở repo đích < biến môi trường.
Hay dùng: `PLANNER`/`CODER`/`REVIEWER` và `*_MODEL`, `FALLBACK_CODER`, `GIT_USER_NAME`, `GIT_USER_EMAIL`,
`AGY_ALLOWED_CMDS` (lệnh agy được dùng — phải khớp allowlist của agy), `AGY_ALLOW_MCP`, `MAX_TRIES` (3),
`MAX_WAIT_HOURS` (6), `REQUIRE_CMD`, `NTFY_TOPIC`. Xem đủ bằng `SCRIPT --help`.
