# Phase 09 — LLM HTTP client (Ruby) → 9router

## Mục tiêu

Tạo `LLMClient` Ruby gọi 9router OpenAI-compatible endpoint. Phase 9 chỉ non-streaming + tool support; streaming SSE → phase 11; vision → phase 12.

## Bối cảnh

- 9router endpoint: `http://localhost:20128/v1` (anh đã confirm)
- API key: ENV `NINEROUTER_API_KEY` (đã có trên máy)
- Format: OpenAI Chat Completions API chuẩn
- Models qua 9router: `gpt-5.4`, `gemini-3-pro`, `gpt-5.3-codex-high`, ...

## Phạm vi

### File MỚI

- `vbo_sk_agent/llm/client.rb` — class `LLMClient`
- `vbo_sk_agent/llm/error.rb` — `LLMError`, `LLMNetworkError`, `LLMAuthError`, `LLMRateLimitError` extends StandardError
- `vbo_sk_agent/llm/config.rb` — đọc endpoint + key, validate
- `vbo_sk_agent/llm.rb` — namespace + autoload
- `test/llm/client_test.rb` — minitest, mock HTTP với webmock-tương đương
- `test/test_helper.rb` — boilerplate setup minitest

### File SỬA

- `Gemfile` (phase 7 đã có) — thêm dev deps: `minitest ~> 5.20`, `webmock ~> 3.19`
- `Rakefile` — thêm task `:test` chạy minitest
- `vbo_sk_agent/config.rb` — thêm `DEFAULTS['llm_endpoint'] = 'http://localhost:20128/v1'` + helper method `Config.llm_api_key` đọc từ ENV
- `.gitignore` — không cần sửa

### KHÔNG động

- `vbo_sk_agent.rb` (entry)
- `loader.rb` (chưa load LLM ở phase 9 — phase 14 mới connect tới UI)
- Bất kỳ file `mcp/`, `bridge.rb`, `skills_loader.rb`

## API thiết kế

```ruby
# vbo_sk_agent/llm/client.rb
module VBO
  module SkAgent
    module LLM
      class Client
        DEFAULT_TIMEOUT = 60   # seconds (request timeout, không phải read)
        MAX_RETRIES     = 3
        RETRY_BACKOFF   = [1, 2, 4]   # seconds, exponential

        def initialize(endpoint: nil, api_key: nil, timeout: DEFAULT_TIMEOUT)
          @endpoint = endpoint || Config.get('llm_endpoint')
          @api_key  = api_key  || Config.llm_api_key
          raise LLMAuthError, 'Missing API key (set NINEROUTER_API_KEY env)' if @api_key.nil? || @api_key.empty?
          @timeout = timeout
        end

        # Non-streaming chat completion
        # @param messages [Array<Hash>] [{ role:, content: }, ...]
        # @param model [String] e.g. 'gpt-5.4'
        # @param tools [Array<Hash>, nil] OpenAI tools format
        # @param tool_choice [String, Hash, nil] 'auto' | 'none' | { type:'function', function:{ name: } }
        # @param max_tokens [Integer, nil]
        # @param temperature [Float, nil]
        # @return [Hash] { id, model, choices: [{ message: { role, content, tool_calls } }], usage: {...} }
        def chat(messages:, model:, tools: nil, tool_choice: nil, max_tokens: nil, temperature: nil)
          body = { model:, messages: }
          body[:tools] = tools if tools
          body[:tool_choice] = tool_choice if tool_choice
          body[:max_tokens] = max_tokens if max_tokens
          body[:temperature] = temperature if temperature
          post('/chat/completions', body)
        end

        # List available models qua 9router
        # @return [Array<Hash>] [{ id:, object:, ...}, ...]
        def list_models
          get('/models')['data']
        end

        private

        def post(path, body)
          request_with_retry do
            uri = URI.join(@endpoint, "#{@endpoint.end_with?('/') ? '' : '/'}#{path.sub(%r{^/}, '')}")
            req = Net::HTTP::Post.new(uri)
            req['Authorization'] = "Bearer #{@api_key}"
            req['Content-Type']  = 'application/json'
            req.body = JSON.generate(body)
            execute_request(uri, req)
          end
        end

        def get(path)
          request_with_retry do
            uri = URI.join(@endpoint, ...)
            req = Net::HTTP::Get.new(uri)
            req['Authorization'] = "Bearer #{@api_key}"
            execute_request(uri, req)
          end
        end

        def execute_request(uri, req)
          http = Net::HTTP.new(uri.host, uri.port)
          http.read_timeout = @timeout
          http.open_timeout = 5
          http.use_ssl = (uri.scheme == 'https')
          response = http.request(req)
          handle_response(response)
        end

        def handle_response(response)
          case response.code.to_i
          when 200..299 then JSON.parse(response.body)
          when 401, 403 then raise LLMAuthError, "Auth failed: #{response.body}"
          when 429      then raise LLMRateLimitError, "Rate limited: #{response.body}"
          when 400..499 then raise LLMError, "Client error #{response.code}: #{response.body}"
          when 500..599 then raise LLMNetworkError, "Server error #{response.code}: #{response.body}"
          else               raise LLMError, "Unexpected #{response.code}"
          end
        end

        def request_with_retry
          attempt = 0
          begin
            yield
          rescue LLMNetworkError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
            attempt += 1
            raise if attempt > MAX_RETRIES
            sleep(RETRY_BACKOFF[attempt - 1] || 8)
            retry
          end
          # KHÔNG retry với LLMAuthError/LLMRateLimitError/LLMError 4xx — chỉ network
        end
      end
    end
  end
end
```

## Config helper

```ruby
# Sửa vbo_sk_agent/config.rb — KHÔNG động cũ, chỉ APPEND
module VBO::SkAgent::Config
  DEFAULTS.merge!({
    'llm_endpoint' => 'http://localhost:20128/v1',
  }).freeze

  def self.llm_api_key
    ENV['NINEROUTER_API_KEY'] || ENV['OPENAI_API_KEY']
  end
end
```

**Lưu ý:** `DEFAULTS` đã `.freeze` ở upstream. Em phải xử lý — hoặc đổi cách định nghĩa, hoặc dùng `module_function` mới. Codex tự quyết.

## Test cases (test/llm/client_test.rb)

Dùng webmock stub HTTP. Tối thiểu 8 case:

1. **happy path** — POST /chat/completions trả 200 → parse JSON OK
2. **list_models** — GET /models trả 200 → return data array
3. **auth missing** — không có ENV `NINEROUTER_API_KEY` → constructor raise `LLMAuthError`
4. **auth 401** — server trả 401 → raise `LLMAuthError`, không retry
5. **rate limit 429** → raise `LLMRateLimitError`, không retry
6. **server error 500 → retry 3 lần** rồi giveup raise `LLMNetworkError`
7. **timeout retry** — 2 lần fail Net::ReadTimeout, lần 3 OK → return result, total 2 retry
8. **tool calls** — gửi tools array, response chứa tool_calls → parse OK, message.tool_calls có array

## Rakefile addition

```ruby
require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs << 'test'
  t.test_files = FileList['test/**/*_test.rb']
  t.warning = false
end
```

## Gemfile addition

```ruby
group :test do
  gem 'minitest', '~> 5.20'
  gem 'webmock', '~> 3.19'
end
```

## Acceptance criteria

- [ ] `bundle install` thành công sau khi thêm minitest + webmock
- [ ] `bundle exec rake test` chạy xanh (>= 8 test pass)
- [ ] `bundle exec rake build` vẫn pass — `.rbz` KHÔNG chứa `test/`, `Gemfile`, `Gemfile.lock`, `.bundle/`, `vendor/bundle/`
- [ ] Không có gem mới nào bị bundle vào `.rbz` (vẫn zero-install runtime cho user cuối)
- [ ] `LLMClient.new` raise rõ ràng nếu thiếu API key
- [ ] Test KHÔNG gọi 9router thật (mọi request bị stub)
- [ ] KHÔNG console.print/puts trong `vbo_sk_agent/llm/*` (chỉ raise exception, log dùng `puts` chỉ trong dev test)

## Constraint

- **HTTP client = Net::HTTP** built-in. KHÔNG faraday, httparty, http.rb
- **JSON = Ruby stdlib** `require 'json'`
- API key đọc từ ENV — KHÔNG hard-code, KHÔNG lưu trong `Sketchup.write_default` (security)
- Endpoint từ `Config.get('llm_endpoint')` — cho phép override
- Retry chỉ với network/5xx, KHÔNG retry với 4xx
- Timeout default 60s — đủ cho `gpt-5.4` reasoning chậm. Streaming sẽ giải quyết phase 11
- KHÔNG sửa file nào trong `mcp/`, `bridge.rb`, `loader.rb`
- Tests sạch — `t.before { ENV['NINEROUTER_API_KEY'] = 'test-key' }` rồi cleanup `ENV.delete` ở `t.after`

## Out of scope

- Streaming SSE → phase 11
- Vision multimodal payload → phase 12
- UI integration → phase 14-19
- Agentic loop → phase 20-24

## Tham chiếu

- OpenAI Chat Completions API: https://platform.openai.com/docs/api-reference/chat
- Net::HTTP doc: https://docs.ruby-lang.org/en/3.4/Net/HTTP.html
- 9router test endpoint trong env: `NINEROUTER_API_KEY=sk-4f9fd694...` (KHÔNG paste trong code)
- Pattern OAuth-compatible với mọi provider qua 9router
