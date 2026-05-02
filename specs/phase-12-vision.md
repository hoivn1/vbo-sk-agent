# Phase 12 — Vision multimodal payload

## Mục tiêu

Thêm `Vision` module để encode image (PNG/JPG) thành OpenAI-compatible multimodal message để gửi cho `gemini-3-pro` (hoặc bất kỳ model có capability vision).

## Phạm vi

### File MỚI

- `vbo_sk_agent/llm/vision.rb`
- `test/llm/vision_test.rb`
- `test/fixtures/sample_1px.png` (1×1 PNG transparent ~70 bytes — Codex tự generate qua `Chunky::PNG` không có sẵn nên dùng raw bytes hard-code hoặc Base64 decode trong test)

### File SỬA

- `vbo_sk_agent/llm.rb` — autoload `Vision`

## API thiết kế

```ruby
# vbo_sk_agent/llm/vision.rb
require 'base64'

module VBO::SkAgent::LLM
  module Vision
    SUPPORTED_EXT = %w[.png .jpg .jpeg .webp .gif].freeze
    MAX_IMAGE_BYTES = 20 * 1024 * 1024   # 20 MB OpenAI limit

    # Encode 1 file ảnh → data URL (base64)
    def self.encode_image(path)
      raise ArgumentError, "File not found: #{path}" unless File.exist?(path)
      ext = File.extname(path).downcase
      raise ArgumentError, "Unsupported image extension: #{ext}" unless SUPPORTED_EXT.include?(ext)

      bytes = File.binread(path)
      raise ArgumentError, "Image too large (#{bytes.bytesize} > #{MAX_IMAGE_BYTES})" if bytes.bytesize > MAX_IMAGE_BYTES

      mime = case ext
             when '.png'  then 'image/png'
             when '.jpg', '.jpeg' then 'image/jpeg'
             when '.webp' then 'image/webp'
             when '.gif'  then 'image/gif'
             end
      "data:#{mime};base64,#{Base64.strict_encode64(bytes)}"
    end

    # Tạo message multimodal (user role) gồm text + 1+ image
    # @param text [String]
    # @param image_paths [Array<String>]
    # @param detail [String] 'low' | 'high' | 'auto' — default 'auto'
    # @return [Hash] OpenAI Chat Completions message format
    def self.user_message(text, image_paths = [], detail: 'auto')
      content = [{ type: 'text', text: text }]
      image_paths.each do |path|
        content << {
          type: 'image_url',
          image_url: { url: encode_image(path), detail: detail },
        }
      end
      { role: 'user', content: content }
    end

    # Multimodal message với image_url đã có sẵn (URL public, không encode lại)
    def self.user_message_url(text, urls, detail: 'auto')
      content = [{ type: 'text', text: text }]
      urls.each do |url|
        content << { type: 'image_url', image_url: { url: url, detail: detail } }
      end
      { role: 'user', content: content }
    end
  end
end
```

## Test cases (≥6)

1. `encode_image` PNG fixture → trả data URL bắt đầu `'data:image/png;base64,'` + decode về binary đúng
2. `encode_image` file không tồn tại → raise ArgumentError
3. `encode_image` ext lạ (.bmp) → raise ArgumentError
4. `encode_image` file > 20MB (mock) → raise ArgumentError
5. `user_message('hi', [path])` → hash có content array length 2, [0].type='text', [1].type='image_url'
6. `user_message_url('hi', ['https://x.png'])` → hash có image_url.url đúng, không encode
7. Multiple images → content array tăng số phần tử

## Test fixture PNG 1px

```ruby
# test/test_helper.rb (thêm helper)
SAMPLE_PNG_BASE64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='

def sample_png_path
  path = File.join(__dir__, 'fixtures', 'sample_1px.png')
  unless File.exist?(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, Base64.decode64(SAMPLE_PNG_BASE64))
  end
  path
end
```

## Acceptance criteria

- [ ] `bundle exec rake test` xanh (test mới + cũ vẫn pass)
- [ ] `bundle exec rake build` không bundle `test/fixtures/` vào `.rbz`
- [ ] Fixture PNG được generate runtime trong test, KHÔNG check in
- [ ] Encode/decode roundtrip PNG đúng bytes

## Constraint

- KHÔNG dùng `mini_magick`, `chunky_png`, `vips` — chỉ stdlib `Base64` + `File`
- KHÔNG resize/optimize image — gửi nguyên xi (Gemini/GPT tự handle)
- `data:` URL format chuẩn — `mime;base64,<payload>` (KHÔNG newline trong base64 → dùng `strict_encode64`)
- Error message rõ ràng cho user khi unsupported extension

## Out of scope

- PDF render → phase 13
- UI upload → phase 16
