# Phase 07 — Rakefile + GitHub Action build .rbz

## Mục tiêu

Repo `hoivn1/vbo-sk-agent` (fork) chưa có build system. Upstream package `.rbz` thủ công. Phase này thêm Rakefile (build cục bộ) + GitHub Action (auto build khi push tag) để release ổn định, version-controlled.

## Bối cảnh

`.rbz` là file zip đổi đuôi, chứa:
```
vbo_sk_agent.rb        ← root loader (entry point cho Sketchup.register_extension)
vbo_sk_agent/          ← module folder
  loader.rb
  bridge.rb
  bridge/command.rb
  config.rb
  mcp/
  skills/
  skills_loader.rb
  templates/
  ui/
  icons/
  vbo_sk_agent.rb        ← KHÔNG có file này — root loader nằm ngoài, không trong folder
```

Version hiện tại: `PLUGIN_VERSION = '1.2.0'` (xem `vbo_sk_agent.rb:4`).

## Phạm vi

### File MỚI

- `Rakefile` — task `build`, `clean`, `version`, `lint` (lint chỉ là placeholder)
- `.github/workflows/build.yml` — workflow CI: trigger trên push tag `v*` (ví dụ `v1.2.1-vbo.1`), checkout, build .rbz, attach asset vào release
- `.gitignore` — append `/build/`, `*.rbz`, `pkg/`
- `BUILDING.md` — hướng dẫn build local + release flow
- `scripts/sync-version.rb` — Ruby script đọc `vbo_sk_agent.rb`, sync version sang `vbo_sk_agent/extension.json` nếu có (không tạo file mới — chỉ sync nếu đã tồn tại)

### File KHÔNG sửa

- Bất kỳ file nào trong `vbo_sk_agent/` (logic plugin)
- `vbo_sk_agent.rb` (entry)
- `LICENSE`, `README.md`

## Rakefile

```ruby
# Rakefile
require 'rake/clean'
require 'rubygems/package'
require 'zip'

EXTENSION_NAME = 'vbo_sk_agent'
VERSION = File.read('vbo_sk_agent.rb').match(/PLUGIN_VERSION\s*=\s*'([^']+)'/)[1]
BUILD_DIR = 'build'
RBZ_FILE = "#{BUILD_DIR}/#{EXTENSION_NAME}_v#{VERSION}.rbz"

CLEAN.include(BUILD_DIR)
CLEAN.include('*.rbz')

desc 'Show resolved version from vbo_sk_agent.rb'
task :version do
  puts VERSION
end

desc "Build #{EXTENSION_NAME}.rbz into #{BUILD_DIR}/"
task :build => :clean do
  mkdir_p BUILD_DIR
  files = ['vbo_sk_agent.rb'] + Dir.glob("#{EXTENSION_NAME}/**/*").reject { |f| File.directory?(f) }
  Zip::File.open(RBZ_FILE, Zip::File::CREATE) do |zip|
    files.each do |f|
      next if f.match?(/\.(rbz|zip|tmp)$/)
      next if File.basename(f).start_with?('.')
      zip.add(f, f)
    end
  end
  puts "Built #{RBZ_FILE} (#{File.size(RBZ_FILE)} bytes, #{files.length} files)"
end

desc 'Lint placeholder (no-op for phase 7)'
task :lint do
  puts 'lint: ok (placeholder)'
end

task :default => :build
```

**Lưu ý**: `rubyzip` gem cần trong Gemfile. Tạo `Gemfile`:
```ruby
source 'https://rubygems.org'
gem 'rubyzip', '~> 2.3'
gem 'rake', '~> 13.0'
```

Cộng thêm `Gemfile.lock` (Codex chạy `bundle install` xong commit cả file lock).

## GitHub Action

```yaml
# .github/workflows/build.yml
name: Build .rbz

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
          bundler-cache: true
      - name: Build .rbz
        run: bundle exec rake build
      - name: Show artifact info
        run: ls -la build/
      - name: Upload as workflow artifact
        uses: actions/upload-artifact@v4
        with:
          name: rbz
          path: build/*.rbz
      - name: Attach to GitHub Release (only on tag)
        if: startsWith(github.ref, 'refs/tags/v')
        uses: softprops/action-gh-release@v2
        with:
          files: build/*.rbz
          generate_release_notes: true
```

## BUILDING.md (nội dung tối thiểu)

```markdown
# Building `vbo_sk_agent`

## Local build

\`\`\`bash
bundle install
bundle exec rake build
\`\`\`

Output: `build/vbo_sk_agent_v<version>.rbz`

## Release flow

1. Bump `PLUGIN_VERSION` trong `vbo_sk_agent.rb`
2. Commit + push
3. Tag: `git tag v1.2.1-vbo.1 && git push --tags`
4. CI build + attach .rbz vào GitHub Release tự động

## Tag convention

- `v<upstream_version>-vbo.<n>` cho release downstream của fork
  (vd `v1.2.0-vbo.1` = fork dựa trên upstream 1.2.0, lần release thứ 1)
- Khi rebase upstream lên 1.3.0 thì bắt đầu lại `v1.3.0-vbo.1`
```

## .gitignore (append, KHÔNG ghi đè)

```
# Build artifacts
/build/
*.rbz
pkg/

# Bundle
.bundle/
vendor/bundle/
```

## scripts/sync-version.rb

```ruby
#!/usr/bin/env ruby
# Sync PLUGIN_VERSION từ vbo_sk_agent.rb sang vbo_sk_agent/extension.json (nếu tồn tại)
require 'json'

root = File.expand_path('..', __dir__)
loader = File.read(File.join(root, 'vbo_sk_agent.rb'))
version = loader.match(/PLUGIN_VERSION\s*=\s*'([^']+)'/)[1]

ext_json_path = File.join(root, 'vbo_sk_agent', 'extension.json')
unless File.exist?(ext_json_path)
  puts "No extension.json — skip sync"
  exit 0
end

data = JSON.parse(File.read(ext_json_path))
old_version = data['version']
data['version'] = version
File.write(ext_json_path, JSON.pretty_generate(data) + "\n")
puts "Synced extension.json version: #{old_version} → #{version}"
```

## Acceptance criteria

- [ ] `bundle install` thành công
- [ ] `bundle exec rake version` in ra `1.2.0`
- [ ] `bundle exec rake build` tạo `build/vbo_sk_agent_v1.2.0.rbz`
- [ ] File `.rbz` mở được (test: `unzip -l build/vbo_sk_agent_v1.2.0.rbz | head -20` thấy `vbo_sk_agent.rb` ở root + folder `vbo_sk_agent/`)
- [ ] `bundle exec rake clean` xóa `build/`
- [ ] `.github/workflows/build.yml` valid YAML (test bằng `actionlint` nếu có, nếu không skip)
- [ ] `.gitignore` có thêm các entry mới, KHÔNG xóa entry cũ
- [ ] `BUILDING.md` đúng nội dung
- [ ] Không ghi đè bất kỳ file nào trong `vbo_sk_agent/`

## Test cách

```bash
bundle install
bundle exec rake version          # → 1.2.0
bundle exec rake build             # → build/vbo_sk_agent_v1.2.0.rbz
unzip -l build/vbo_sk_agent_v1.2.0.rbz | head -10
bundle exec rake clean             # → xóa build/
```

## Constraint

- KHÔNG dùng gem ngoài rubyzip + rake
- KHÔNG cần CI cho test (chưa có test framework Ruby trong repo) — chỉ build + release
- File CI chỉ trigger trên `tags` `v*` và `workflow_dispatch` — KHÔNG trigger trên mọi push (tốn CI minutes free)
- Upload artifact chỉ giữ 90 ngày (default GitHub) — đó là OK
- Phải xử lý đường dẫn cross-platform — KHÔNG hard-code `/` (dùng `File.join`)
- `rake build` phải idempotent — chạy 2 lần liên tiếp ra cùng file
- Bundler config: KHÔNG check in `vendor/bundle`

## Out of scope

- Test framework (minitest/rspec) — chưa cần
- Lint/Rubocop — phase sau
- Sign extension cho SketchUp — yêu cầu Trimble dev account, chưa cần
