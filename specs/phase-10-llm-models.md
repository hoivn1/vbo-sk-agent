# Phase 10 — Model registry + LLM config UI persist

## Mục tiêu

Phase 9 đã có `LLMClient`. Phase 10 thêm model registry (danh sách model có sẵn qua 9router) + persistence cho user chọn default model. Vẫn chưa wire UI — phase 14 mới làm dropdown.

## Phạm vi

### File MỚI

- `vbo_sk_agent/llm/models.rb` — module `VBO::SkAgent::LLM::Models` với danh sách static model + helper
- `test/llm/models_test.rb`

### File SỬA

- `vbo_sk_agent/llm.rb` — autoload `Models`
- `vbo_sk_agent/llm/config.rb` — thêm `default_model`, getter/setter qua `Sketchup.write_default`
- `vbo_sk_agent/config.rb` — thêm `LLM_DEFAULTS` merge: `'llm_default_model' => 'gpt-5.4'`

### KHÔNG ĐỘNG

- `vbo_sk_agent.rb`, `loader.rb`, `bridge.rb`, `mcp/`, `skills_loader.rb`, `skills/`, `ui/`
- `vbo_sk_agent/llm/client.rb` (phase 9)

## API thiết kế

```ruby
# vbo_sk_agent/llm/models.rb
module VBO::SkAgent::LLM
  module Models
    # Static catalog. KHÔNG fetch list_models từ 9router ở phase này
    # (phase 14 dashboard có nút refresh sẽ làm).
    CATALOG = [
      { id: 'gpt-5.4',             provider: 'codex',       capability: %i[chat tools],         vision: false, default_for: %i[chat reasoning] },
      { id: 'gpt-5.3-codex-high',  provider: 'codex',       capability: %i[chat tools],         vision: false, default_for: %i[code] },
      { id: 'gpt-5-codex',         provider: 'codex',       capability: %i[chat tools],         vision: false, default_for: [] },
      { id: 'gemini-3-pro',        provider: 'antigravity', capability: %i[chat tools vision],  vision: true,  default_for: %i[vision] },
      { id: 'gemini-3-flash',      provider: 'antigravity', capability: %i[chat],               vision: false, default_for: [] },
      { id: 'claude-sonnet-4-6',   provider: 'antigravity', capability: %i[chat tools],         vision: false, default_for: [] },
    ].freeze

    # Trả về list các id model
    def self.ids
      CATALOG.map { |m| m[:id] }
    end

    # Lookup metadata by id
    def self.find(id)
      CATALOG.find { |m| m[:id] == id }
    end

    # Lấy model mặc định cho purpose nhất định
    # @param purpose [Symbol] :chat | :reasoning | :code | :vision
    def self.default_for(purpose)
      CATALOG.find { |m| m[:default_for].include?(purpose) }&.dig(:id)
    end

    # Filter models có capability nhất định
    def self.with_capability(cap)
      CATALOG.select { |m| m[:capability].include?(cap) }.map { |m| m[:id] }
    end

    def self.vision_capable
      CATALOG.select { |m| m[:vision] }.map { |m| m[:id] }
    end
  end
end
```

```ruby
# Sửa vbo_sk_agent/llm/config.rb — thêm:
module VBO::SkAgent::LLM::Config
  module_function

  def default_model
    raw = Sketchup.read_default(VBO::SkAgent::Config::SECTION, 'llm_default_model')
    return raw if raw && Models.find(raw)
    Models.default_for(:chat) || 'gpt-5.4'
  end

  def default_model=(id)
    raise ArgumentError, "Unknown model: #{id}" unless Models.find(id)
    Sketchup.write_default(VBO::SkAgent::Config::SECTION, 'llm_default_model', id)
  end

  def vision_model
    Models.default_for(:vision) || 'gemini-3-pro'
  end

  def code_model
    Models.default_for(:code) || 'gpt-5.3-codex-high'
  end
end
```

## Test cases (test/llm/models_test.rb) — tối thiểu 6

1. `Models.ids` trả về array string non-empty
2. `Models.find('gpt-5.4')` trả về hash đúng
3. `Models.find('non-existent')` trả về nil
4. `Models.default_for(:chat)` trả về `'gpt-5.4'`
5. `Models.default_for(:vision)` trả về `'gemini-3-pro'`
6. `Models.with_capability(:vision)` chỉ chứa các id có vision=true
7. `Models.vision_capable` trả về list không rỗng
8. CATALOG immutable — `expect { Models::CATALOG << {} }` raise FrozenError

## Acceptance criteria

- [ ] `bundle exec rake test` xanh (test mới + test phase 9 vẫn pass)
- [ ] `bundle exec rake build` không gây thay đổi `.rbz` size lớn (chỉ +vài KB cho models.rb)
- [ ] `Models.find` không hit network — tất cả static
- [ ] Test KHÔNG đụng `Sketchup.read_default` (mock hoặc skip)

## Constraint

- KHÔNG thêm dependency mới
- KHÔNG fetch model list từ 9router ở phase này (defer phase 14)
- CATALOG phải `.freeze` deep — mỗi hash con cũng freeze để test #8 pass
- Tên model phải khớp chính xác `cx/`, `cc/` prefix khi 9router yêu cầu — **kiểm tra lại với env user**: 9router accept tên trần (vd `gpt-5.4`) hay phải có prefix (`cx/gpt-5.4`)? Spec ghi tên trần — Codex giữ tên trần, KHÔNG tự thêm prefix.

## Out of scope

- Dropdown UI → phase 14
- Refresh model list từ 9router → phase 14
