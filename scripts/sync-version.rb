#!/usr/bin/env ruby
# Sync PLUGIN_VERSION from vbo_sk_agent.rb to vbo_sk_agent/extension.json if it exists.
require 'json'

root = File.expand_path('..', __dir__)
loader_path = File.join(root, 'vbo_sk_agent.rb')
loader = File.read(loader_path)
match = loader.match(/PLUGIN_VERSION\s*=\s*'([^']+)'/)

unless match
  warn "Cannot find PLUGIN_VERSION in #{loader_path}"
  exit 1
end

version = match[1]
ext_json_path = File.join(root, 'vbo_sk_agent', 'extension.json')

unless File.exist?(ext_json_path)
  puts 'No extension.json - skip sync'
  exit 0
end

data = JSON.parse(File.read(ext_json_path))
old_version = data['version']
data['version'] = version
File.write(ext_json_path, JSON.pretty_generate(data) + "\n")

puts "Synced extension.json version: #{old_version} -> #{version}"
