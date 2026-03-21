#!/usr/bin/env ruby
# frozen_string_literal: true

# Imports posts from a Medium user's RSS feed into Jekyll _posts.
# Medium exposes https://medium.com/feed/@username — no HTML scraping required.
#
# Usage:
#   ruby scripts/import_medium_feed.rb [--force]
#   ruby scripts/import_medium_feed.rb path/to/feed.xml [--force]
#
# If the first argument is a file, it is used instead of fetching (helps when Ruby SSL fails on Windows).

require "fileutils"
require "nokogiri"
require "open-uri"
require "time"
require "yaml"

FEED_URL = "https://medium.com/feed/@deyagondsamarth"
POSTS_DIR = File.expand_path("../_posts", __dir__)
ARGS = ARGV.reject { |a| a == "--force" }
FORCE = ARGV.include?("--force")
FEED_FILE = ARGS.find { |a| File.file?(File.expand_path(a, Dir.pwd)) }

CONTENT_NS = { "content" => "http://purl.org/rss/1.0/modules/content/" }.freeze

def slug_from_link(link)
  return if link.nil? || link.empty?

  uri = URI.parse(link)
  path = uri.path.to_s.delete_suffix("/")
  seg = path.split("/").last
  seg = seg.sub(/\?.*\z/, "")
  seg&.gsub(/[^a-zA-Z0-9\-_.]/, "-")&.gsub(/-+/, "-")&.gsub(/\A-|\-\z/, "")
end

def strip_html(html)
  return "" if html.nil? || html.empty?

  Nokogiri::HTML.fragment(html).text.gsub(/\s+/, " ").strip
end

def excerpt(html, max = 200)
  text = strip_html(html)
  return text if text.length <= max

  "#{text[0, max].strip}…"
end

FileUtils.mkdir_p(POSTS_DIR)

xml = if FEED_FILE
  path = File.expand_path(FEED_FILE, Dir.pwd)
  puts "Reading #{path} …"
  File.read(path, encoding: "UTF-8")
else
  puts "Fetching #{FEED_URL} …"
  URI.open(
    FEED_URL,
    "User-Agent" => "Mozilla/5.0 (compatible; JekyllMediumImport/1.0; +#{FEED_URL})"
  ).read
end

doc = Nokogiri::XML(xml)
items = doc.xpath("//item")
puts "Found #{items.size} items."

imported = 0
skipped = 0

items.each do |item|
  title = item.at_xpath("title")&.text&.strip
  link = item.at_xpath("link")&.text&.strip
  pub_el = item.at_xpath("pubDate")&.text
  encoded = item.at_xpath("content:encoded", CONTENT_NS)&.text

  next if title.nil? || title.empty?
  next if encoded.nil? || encoded.strip.empty?

  slug = slug_from_link(link)
  if slug.nil? || slug.empty?
    warn "Skip (no slug): #{title.inspect}"
    skipped += 1
    next
  end

  begin
    time = Time.parse(pub_el.to_s)
  rescue ArgumentError
    warn "Skip (bad date): #{title.inspect}"
    skipped += 1
    next
  end

  date = time.utc.to_date
  basename = "#{date}-#{slug}.md"
  path = File.join(POSTS_DIR, basename)

  if File.exist?(path) && !FORCE
    skipped += 1
    next
  end

  categories = item.xpath("category").map(&:text).map(&:strip).reject(&:empty?).uniq
  tags = categories.dup
  primary = tags.shift
  cats = primary ? [primary] : []

  fm = {
    "layout" => "post",
    "title" => title,
    "date" => date.to_s,
    "description" => excerpt(encoded, 200),
    "canonical_url" => link,
    "tags" => tags,
    "categories" => cats,
    "medium_original_url" => link,
  }

  yaml = fm.to_yaml(line_width: -1)
  body = encoded.strip.gsub(%r{<img[^>]*src="https://medium\.com/_/stat[^"]*"[^>]*/?>}i, "")
  File.write(path, "#{yaml}---\n\n#{body}\n", encoding: "UTF-8")
  puts "Wrote #{basename}"
  imported += 1
end

puts "Done. Imported: #{imported}, skipped (existing or errors): #{skipped}."
