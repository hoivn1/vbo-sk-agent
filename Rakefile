require 'rake/clean'
require 'rubygems/package'
require 'zip'

EXTENSION_NAME = 'vbo_sk_agent'
ENTRY_FILE = 'vbo_sk_agent.rb'
BUILD_DIR = 'build'

def plugin_version
  loader = File.read(ENTRY_FILE)
  match = loader.match(/PLUGIN_VERSION\s*=\s*'([^']+)'/)
  raise "Cannot find PLUGIN_VERSION in #{ENTRY_FILE}" unless match

  match[1]
end

VERSION = plugin_version
RBZ_FILE = File.join(BUILD_DIR, "#{EXTENSION_NAME}_v#{VERSION}.rbz")

CLEAN.include(BUILD_DIR)
CLEAN.include('*.rbz')

desc 'Show resolved version from vbo_sk_agent.rb'
task :version do
  puts VERSION
end

desc "Build #{EXTENSION_NAME}.rbz into #{BUILD_DIR}#{File::SEPARATOR}"
task build: :clean do
  mkdir_p BUILD_DIR

  files = [ENTRY_FILE]
  files += Dir.glob(File.join(EXTENSION_NAME, '**', '*')).reject { |path| File.directory?(path) }
  files.sort!

  Zip::File.open(RBZ_FILE, create: true) do |zip|
    files.each do |path|
      next if path.match?(/\.(rbz|zip|tmp)\z/i)
      next if path.split(/[\\\/]/).any? { |segment| segment.start_with?('.') }

      zip.add(path.tr('\\', '/'), path)
    end
  end

  puts "Built #{RBZ_FILE} (#{File.size(RBZ_FILE)} bytes)"
end

desc 'Lint placeholder (no-op for phase 7)'
task :lint do
  puts 'lint: ok (placeholder)'
end

task default: :build
