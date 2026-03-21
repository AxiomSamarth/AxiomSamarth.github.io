#!/usr/bin/env ruby
# frozen_string_literal: true

# Removes Medium RSS tracking beacons from _posts/*.md

root = File.expand_path("..", __dir__)
Dir.glob(File.join(root, "_posts", "*.md")).each do |path|
  s = File.read(path, encoding: "UTF-8")
  n = s.gsub(%r{<img[^>]*src="https://medium\.com/_/stat[^"]*"[^>]*/?>}i, "")
  File.write(path, n) if n != s
end

puts "Stripped Medium stat pixels where present."
