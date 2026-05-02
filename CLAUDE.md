# CLAUDE.md

This file guides Claude Code (claude.ai/code) when working in this repository.

## Repo identity

**Fork** của `vbosolution/vbo-sk-agent` (MIT). Mục tiêu fork: thêm Chat UI + LLM client (qua 9router) + agentic loop để dựng 3D thạch cao từ bản vẽ 2D.

Kế hoạch tổng: `../PROJECT_PLAN_V2.md` (workspace `mcpsketchup/`).

## Stack

- **Plugin language**: Ruby (SketchUp 2026 — Ruby 3.4) — KHÔNG có Gemfile cho phần plugin (zero gem install runtime); **chỉ build/CI** mới có Gemfile (rubyzip + rake)
- **UI**: HtmlDialog (CEF cũ — `fetch` SSE có thể fail, fallback long-poll), vanilla JS
- **MCP**: HTTP server port 7891 đã có sẵn, vendor `mcp-0.13.0` gem
- **LLM gateway** (sẽ thêm Sprint 3): 9router `http://localhost:20128/v1` OpenAI-compatible

## Workflow Codex

Repo này dùng CodexForgeMCP để delegate code:
- Spec: `specs/phase-NN-tên.md`
- Run: `mcp__codexforge__codex_run_phase` từ Claude session
- Review diff → `codex_commit` → merge `main` → push GitHub
- Branch convention: `vbo/<feature>` (ví dụ `vbo/chat-ui`, `vbo/llm-client`) khi viết tay
- Phase Codex: branch tự sinh `codexforge/phase-NN-...`

## Upstream sync

Định kỳ 1-2 tuần:
```bash
git fetch upstream
git rebase upstream/main
git push --force-with-lease
```

Tag fork dùng convention `v<upstream>-vbo.<n>` (vd `v1.2.0-vbo.1`).

## TUYỆT ĐỐI không sửa

- `vbo_sk_agent.rb` — entry point, signature contract upstream
- `vbo_sk_agent/mcp/vendor/*` — gem version lock
- `vbo_sk_agent/loader.rb` line 1-4 require order
- Action callback names trong `Dashboard` module (line 116-186) — JS contract

## Best practice cho fork

- **Tính năng mới ở namespace riêng**: `vbo_sk_agent/chat/`, `vbo_sk_agent/llm/`, `vbo_sk_agent/builders/` — KHÔNG nhồi vào `loader.rb` hay `bridge.rb` để tránh rebase conflict
- **Action callback mới**: tách ra `vbo_sk_agent/ui/dashboard_callbacks.rb` thay vì sửa `loader.rb`
- **Tool registry**: refactor `mcp/tools.rb` thành runtime-add-able để cả MCP server và ChatAgent dùng chung
- **Config key mới**: thêm vào `Config::DEFAULTS` OK, KHÔNG đổi default value của key cũ

## Tài liệu tham chiếu

- `references/SKAGENT_NOTES.md` (workspace `mcpsketchup/`) — bản đồ chi tiết: cấu trúc thư mục, lifecycle, callback pattern, điểm mở rộng
- `BUILDING.md` (sau phase 7) — cách build .rbz
- SketchUp Ruby API: https://ruby.sketchup.com/

## Tóm tắt 4 MCP tool sẵn có

| Tool | Mục đích |
|---|---|
| `execute_ruby` | Eval code trong TOPLEVEL_BINDING |
| `reload_file` | Bypass `file_loaded?` guard |
| `list_instances` | List SU instances + multi warning |
| `get_console_output` | Lấy stdout buffer |

Sprint 3+ sẽ mở rộng list này với LLM, vision, geometry, ceiling, paneling, takeoff tool.

## Quy ước commit

```
feat(chat-ui): thêm tab Chat với drag-drop file
feat(llm-client): Net::HTTP wrapper cho 9router
fix(bridge): edge case race khi parseResult dở dở
chore(rake): build .rbz idempotent
```

Conventional Commits, scope từ namespace (`chat-ui`, `llm-client`, `agent`, `builders`, `bridge`, `mcp`, `ui`, `rake`, `ci`, `docs`).
