# Phase 13 — PDF render → image

## Mục tiêu

Render PDF page thành PNG để gửi sang vision model. Ruby thuần KHÔNG có PDF renderer — phải dùng external binary. Phase 13 detect + wrap `pdftoppm` (Poppler), với fallback rõ ràng nếu không có.

## Phạm vi

### File MỚI

- `vbo_sk_agent/io/pdf_render.rb`
- `vbo_sk_agent/io.rb` — namespace
- `test/io/pdf_render_test.rb`

### File SỬA

- `vbo_sk_agent/llm.rb` — KHÔNG động (io khác namespace llm)

## API thiết kế

```ruby
# vbo_sk_agent/io/pdf_render.rb
require 'open3'
require 'tmpdir'

module VBO::SkAgent::IO
  module PdfRender
    class PdfToolNotFound < StandardError; end
    class PdfRenderError < StandardError; end

    # Probe binary `pdftoppm` from Poppler có trên PATH không
    def self.available?
      return @available unless @available.nil?
      stdout, _, status = Open3.capture3('pdftoppm', '-v')
      @available = status.success? || stdout.include?('pdftoppm')
    rescue Errno::ENOENT
      @available = false
    end

    # Reset cache — để test re-probe
    def self.reset!
      @available = nil
    end

    # Render PDF → PNG cho từng page
    # @param pdf_path [String]
    # @param out_dir [String, nil] tmp dir nếu nil
    # @param dpi [Integer] default 150 (đủ đọc text)
    # @param first_page [Integer, nil] 1-indexed
    # @param last_page [Integer, nil] inclusive
    # @return [Array<String>] absolute paths của các PNG đã render
    def self.render_pages(pdf_path, out_dir: nil, dpi: 150, first_page: nil, last_page: nil)
      raise PdfToolNotFound, 'pdftoppm not found on PATH (install Poppler)' unless available?
      raise ArgumentError, "PDF not found: #{pdf_path}" unless File.exist?(pdf_path)

      out_dir ||= Dir.mktmpdir('vbo-pdf-')
      stem = File.join(out_dir, 'page')

      args = ['pdftoppm', '-png', '-r', dpi.to_s]
      args.concat(['-f', first_page.to_s]) if first_page
      args.concat(['-l', last_page.to_s]) if last_page
      args.concat([pdf_path, stem])

      _, stderr, status = Open3.capture3(*args)
      raise PdfRenderError, "pdftoppm failed: #{stderr}" unless status.success?

      Dir.glob(File.join(out_dir, 'page-*.png')).sort
    end

    # Render only first N pages (convenient for vision)
    def self.render_first_pages(pdf_path, n: 3, dpi: 150)
      render_pages(pdf_path, dpi: dpi, first_page: 1, last_page: n)
    end

    # User-facing install hint
    def self.install_hint
      case RUBY_PLATFORM
      when /mingw|mswin/
        'Windows: cài Poppler từ https://github.com/oschwartz10612/poppler-windows/releases, ' \
        'extract, thêm `bin/` vào PATH. Hoặc `winget install poppler` nếu có.'
      when /darwin/
        'macOS: brew install poppler'
      else
        'Linux: apt install poppler-utils  (hoặc dnf install poppler-utils)'
      end
    end
  end
end
```

## Test cases (≥5)

1. `available?` mock `Open3.capture3` trả status success → true
2. `available?` raise Errno::ENOENT → false
3. `available?` cache — gọi 2 lần chỉ probe 1 lần. `reset!` xóa cache
4. `render_pages` khi `available?` false → raise `PdfToolNotFound` với message hint
5. `render_pages` PDF không tồn tại → raise ArgumentError
6. `render_pages` happy path: mock `Open3.capture3` success + tạo file giả `page-01.png` trong tmp → trả array có 1 path
7. `render_pages` `pdftoppm` exit non-zero → raise `PdfRenderError` với stderr trong message
8. `install_hint` trên Windows → text chứa 'Poppler'

## Acceptance criteria

- [ ] `bundle exec rake test` xanh
- [ ] `bundle exec rake build` không bundle test/
- [ ] KHÔNG yêu cầu pdftoppm thật khi chạy test (toàn mock)
- [ ] Code gracefully handle khi binary không có — error message hướng dẫn cài

## Constraint

- KHÔNG dùng gem `pdf-reader`, `prawn`, `combine_pdf` — không render được, hoặc nặng dependency
- KHÔNG dùng `mini_magick` — phụ thuộc ImageMagick + bigger overhead
- KHÔNG bundle Poppler binary vào `.rbz` — quá lớn (50+ MB), license, cross-platform
- User cài Poppler 1 lần — em viết `BUILDING.md` ghi rõ
- Tmp dir cleanup: caller responsibility (return path, không tự xóa) — phase 16 (UI upload) sẽ wrap finally cleanup

## Tham chiếu

- pdftoppm man: https://manpages.ubuntu.com/manpages/jammy/man1/pdftoppm.1.html
- Poppler Windows builds: https://github.com/oschwartz10612/poppler-windows/releases

## Out of scope

- Auto download Poppler → phase sau (nếu cần) hoặc tài liệu cài
- Render specific page region → không cần phase này
- Convert PDF → multimodal message (compose) → phase 16 (UI upload + agent loop)
