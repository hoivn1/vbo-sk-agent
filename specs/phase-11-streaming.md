# Phase 11 — Streaming SSE parser cho LLM

## Mục tiêu

Phase 9 chỉ có non-streaming `chat()`. Phase 11 thêm `chat_stream()` để render token-by-token trong UI. CEF của HtmlDialog có thể không support `fetch` SSE → fallback long-poll = chunked HTTP read.

## Phạm vi

### File MỚI

- `vbo_sk_agent/llm/streaming.rb` — `Streaming` module với `parse_chunk`, `parse_event`
- `test/llm/streaming_test.rb`

### File SỬA

- `vbo_sk_agent/llm/client.rb` — thêm `chat_stream(messages:, model:, ...) { |chunk| ... }` block API
- `vbo_sk_agent/llm.rb` — autoload `Streaming`

### KHÔNG ĐỘNG

Như phase 9-10.

## API thiết kế

```ruby
# vbo_sk_agent/llm/streaming.rb
module VBO::SkAgent::LLM
  module Streaming
    # SSE event line:
    #   data: {"id":"...","object":"chat.completion.chunk","choices":[{"delta":{"content":"hello"}}]}
    #   data: [DONE]
    #
    # Parse 1 dòng đơn -> structured event
    # @return [Hash, :done, nil]   nil = empty/heartbeat, :done = stream end
    def self.parse_event(line)
      line = line.to_s.strip
      return nil if line.empty?
      return nil unless line.start_with?('data:')
      payload = line.sub(/^data:\s*/, '')
      return :done if payload == '[DONE]'
      JSON.parse(payload)
    rescue JSON::ParserError
      nil
    end

    # Parse 1 buffer text có thể chứa multiple events (mỗi event ngăn cách \n\n)
    # @yield [event] Hash hoặc :done
    # @return [String] phần buffer còn dở (chưa hết \n\n)
    def self.parse_chunk(buffer, &block)
      events = buffer.split("\n\n")
      remainder = events.last && !buffer.end_with?("\n\n") ? events.pop : ''

      events.each do |event_block|
        event_block.split("\n").each do |line|
          parsed = parse_event(line)
          yield parsed if parsed && block
        end
      end
      remainder
    end

    # Trích content delta từ event (OpenAI Chat Completions format)
    def self.extract_delta(event)
      return nil unless event.is_a?(Hash)
      event.dig('choices', 0, 'delta', 'content')
    end

    def self.extract_tool_call_delta(event)
      return nil unless event.is_a?(Hash)
      event.dig('choices', 0, 'delta', 'tool_calls')
    end

    def self.extract_finish_reason(event)
      return nil unless event.is_a?(Hash)
      event.dig('choices', 0, 'finish_reason')
    end
  end
end
```

```ruby
# Thêm vào vbo_sk_agent/llm/client.rb
class Client
  # ...

  # Streaming chat completion
  # @yield [Hash] event chunk: { type: :delta | :tool_call | :done, content: ..., tool_calls: ... }
  # @return [Hash] final accumulated message { role:, content:, tool_calls: }
  def chat_stream(messages:, model:, tools: nil, &block)
    body = { model:, messages:, stream: true }
    body[:tools] = tools if tools

    accumulated_content = +''
    accumulated_tool_calls = []

    request_with_retry do
      uri = build_uri('/chat/completions')
      req = Net::HTTP::Post.new(uri)
      req['Authorization'] = "Bearer #{@api_key}"
      req['Content-Type']  = 'application/json'
      req['Accept']        = 'text/event-stream'
      req.body = JSON.generate(body)

      buffer = +''
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.read_timeout = @timeout
        http.request(req) do |response|
          if response.code.to_i >= 400
            handle_response(response)   # raises
          end

          response.read_body do |chunk|
            buffer << chunk
            buffer = Streaming.parse_chunk(buffer) do |event|
              if event == :done
                yield({ type: :done }) if block
                next
              end
              if (delta = Streaming.extract_delta(event))
                accumulated_content << delta
                yield({ type: :delta, content: delta }) if block
              elsif (tcs = Streaming.extract_tool_call_delta(event))
                merge_tool_call_delta(accumulated_tool_calls, tcs)
                yield({ type: :tool_call, tool_calls: accumulated_tool_calls.dup }) if block
              end
            end
          end
        end
      end
    end

    {
      'role' => 'assistant',
      'content' => accumulated_content.empty? ? nil : accumulated_content,
      'tool_calls' => accumulated_tool_calls.empty? ? nil : accumulated_tool_calls,
    }.compact
  end

  private

  def merge_tool_call_delta(acc, deltas)
    deltas.each do |d|
      idx = d['index'] || acc.length
      acc[idx] ||= { 'id' => nil, 'type' => 'function', 'function' => { 'name' => '', 'arguments' => '' } }
      acc[idx]['id'] = d['id'] if d['id']
      acc[idx]['type'] = d['type'] if d['type']
      if (fn = d['function'])
        acc[idx]['function']['name'] += fn['name'] if fn['name']
        acc[idx]['function']['arguments'] += fn['arguments'] if fn['arguments']
      end
    end
  end
end
```

## Test cases (≥10)

1. `parse_event('data: {"choices":[{"delta":{"content":"hi"}}]}')` → hash đúng
2. `parse_event('data: [DONE]')` → `:done`
3. `parse_event('')` → `nil`
4. `parse_event(': heartbeat')` → `nil`
5. `parse_event('data: not-json')` → `nil`
6. `parse_chunk` với 2 event đầy đủ → yield 2 hash, return ''
7. `parse_chunk` với 1.5 event (cuối chưa đủ \n\n) → yield 1, return phần dở
8. `extract_delta` từ event valid → string
9. `extract_tool_call_delta` từ event có tool_calls → array
10. `chat_stream` mock HTTP: stub trả 3 chunk SSE → block được call 3 lần với type :delta, accumulate content đúng
11. `chat_stream` với tool calls split qua nhiều chunk → merge đúng (test edge case nhiều delta một tool)
12. `chat_stream` server trả 401 trước khi stream → raise LLMAuthError ngay, không call block

## Acceptance criteria

- [ ] `bundle exec rake test` xanh (≥ 10 test mới + cũ vẫn pass)
- [ ] `chat()` non-streaming vẫn hoạt động (không bị regression)
- [ ] Buffer parsing đúng — không mất event khi chunk cắt giữa dòng
- [ ] Tool call merge đúng khi argument split qua nhiều delta
- [ ] Block yield đồng bộ — caller có thể append vào UI ngay

## Constraint

- KHÔNG dùng eventmachine/async/concurrent-ruby
- Streaming phải hỗ trợ cancel — caller `break` trong block thì request stop. Codex tự handle (raise inside block hoặc Thread.kill — thiết kế thế nào tự lo, miễn không hang)
- Buffer encoding UTF-8 (`buffer = +''` đã default UTF-8 trong Ruby 3.x)
- `read_body do |chunk|` blocking IO — chấp nhận

## Out of scope

- UI render — phase 18
- Long-poll fallback (CEF) — chỉ làm khi phase 18 verify CEF không support SSE
