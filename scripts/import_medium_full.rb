#!/usr/bin/env ruby
# frozen_string_literal: true

# Imports public stories from a Medium profile via Medium's JSON APIs
# (profile stream + per-post payload). RSS alone only returns ~10 items.
#
# Medium returns HTTP 429 if you request too much too fast. For a full archive,
# use a slow daily batch instead of one big run.
#
# Usage:
#   # One-time (when not rate limited): save all post ids to scripts/medium-post-ids.json
#   ruby scripts/import_medium_full.rb --save-ids
#
#   # A few posts per day (skips posts already in _posts/ by Medium post id in filename)
#   ruby scripts/import_medium_full.rb --batch 5
#
#   # Full run (hits profile API + every post — likely to 429)
#   ruby scripts/import_medium_full.rb [--force] [--limit N]
#
#   # Use cached ids without --batch (still imports all missing unless --limit)
#   ruby scripts/import_medium_full.rb --from-ids
#
# Requires network access to medium.com. VERIFY_NONE for HTTPS (local tooling only).

require "cgi"
require "fileutils"
require "json"
require "net/http"
require "openssl"
require "set"
require "time"
require "uri"
require "yaml"

USERNAME = "deyagondsamarth"
POSTS_DIR = File.expand_path("../_posts", __dir__)
IDS_CACHE = File.expand_path("medium-post-ids.json", __dir__)
FORCE = ARGV.include?("--force")
SAVE_IDS = ARGV.include?("--save-ids")
FROM_IDS = ARGV.include?("--from-ids")
LIMIT = (i = ARGV.index("--limit")) && ARGV[i + 1] ? ARGV[i + 1].to_i : nil
BATCH = (i = ARGV.index("--batch")) && ARGV[i + 1] ? ARGV[i + 1].to_i : nil

def http_get(url, retries: 12)
  uri = URI(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  req = Net::HTTP::Get.new(uri)
  req["User-Agent"] = "Mozilla/5.0 (compatible; JekyllMediumFullImport/1.0)"
  req["Accept"] = "application/json"
  res = http.request(req)

  if res.code == "429" && retries.positive?
    wait = 25 + (12 - retries) * 12 + rand(15)
    warn "    rate limited, sleeping #{wait}s …"
    sleep(wait)
    return http_get(url, retries: retries - 1)
  end

  raise "HTTP #{res.code} for #{url}" unless res.code == "200"

  body = res.body.dup.force_encoding("UTF-8")
  body.sub!(/\A\]\)\}while\(1\);<\/x>/, "")
  JSON.parse(body)
end

def html_escape(s)
  CGI.escapeHTML(s.to_s)
end

# Recursive markup application (nested bold/italic/links).
def apply_markups(text, markups)
  return html_escape(text) if markups.nil? || markups.empty?

  markups = markups.reject { |m| m["start"].nil? || m["end"].nil? }
  return html_escape(text) if markups.empty?

  m = markups.min_by { |x| [x["start"], x["end"] - x["start"]] }
  inner_m = markups.select do |x|
    x != m && x["start"] >= m["start"] && x["end"] <= m["end"]
  end
  rel_inner = inner_m.map do |x|
    {
      "start" => x["start"] - m["start"],
      "end" => x["end"] - m["start"],
      "type" => x["type"],
      "href" => x["href"],
    }
  end

  before = html_escape(text[0...m["start"]])
  mid_text = text[m["start"]...m["end"]]
  mid_html = apply_markups(mid_text, rel_inner)
  wrapped = case m["type"]
            when 1 then "<strong>#{mid_html}</strong>"
            when 2 then "<em>#{mid_html}</em>"
            when 3
              href = html_escape(m["href"].to_s)
              %(<a href="#{href}" rel="noopener noreferrer">#{mid_html}</a>)
            else
              mid_html
            end

  tail_m = markups.reject do |x|
    x == m || (x["start"] >= m["start"] && x["end"] <= m["end"])
  end
  tail_text = text[m["end"]..] || ""
  tail_shifted = tail_m.map do |x|
    {
      "start" => x["start"] - m["end"],
      "end" => x["end"] - m["end"],
      "type" => x["type"],
      "href" => x["href"],
    }
  end
  before + wrapped + apply_markups(tail_text, tail_shifted)
end

def image_src(metadata)
  id = metadata["id"]
  return nil if id.nil? || id.to_s.empty?

  "https://cdn-images-1.medium.com/max/2048/#{id}"
end

def list_item_inner(p)
  apply_markups(p["text"].to_s, p["markups"] || [])
end

def render_paragraph(p)
  t = p["type"]
  text = p["text"].to_s
  markups = p["markups"] || []

  case t
  when 1
    "<p>#{apply_markups(text, markups)}</p>"
  when 2
    "<p>#{apply_markups(text, markups)}</p>"
  when 3
    "<h3>#{apply_markups(text, markups)}</h3>"
  when 4
    meta = p["metadata"] || {}
    src = image_src(meta)
    return "" unless src

    cap = apply_markups(text, markups)
    cap_html = cap.strip.empty? ? "" : "<figcaption>#{cap}</figcaption>"
    %(<figure><img alt="" src="#{html_escape(src)}" loading="lazy" />#{cap_html}</figure>)
  when 6
    "<blockquote><p>#{apply_markups(text, markups)}</p></blockquote>"
  when 7
    "<blockquote><p>#{apply_markups(text, markups)}</p></blockquote>"
  when 8
    "<pre><code>#{html_escape(text)}</code></pre>"
  when 9
    "<li>#{list_item_inner(p)}</li>"
  when 10
    "<li>#{list_item_inner(p)}</li>"
  when 11
    # Mixtape / embed — skip placeholder
    ""
  when 13
    "<h4>#{apply_markups(text, markups)}</h4>"
  when 14
    "<p>#{apply_markups(text, markups)}</p>"
  else
    text.strip.empty? ? "" : "<p>#{apply_markups(text, markups)}</p>"
  end
end

def render_body_model(body_model)
  paras = body_model["paragraphs"] || []
  out = []
  i = 0
  while i < paras.size
    p = paras[i]
    t = p["type"]
    if t == 9
      items = []
      while i < paras.size && paras[i]["type"] == 9
        items << list_item_inner(paras[i])
        i += 1
      end
      out << "<ul>\n#{items.map { |x| "<li>#{x}</li>" }.join("\n")}\n</ul>"
      next
    elsif t == 10
      items = []
      while i < paras.size && paras[i]["type"] == 10
        items << list_item_inner(paras[i])
        i += 1
      end
      out << "<ol>\n#{items.map { |x| "<li>#{x}</li>" }.join("\n")}\n</ol>"
      next
    end

    frag = render_paragraph(p)
    out << frag unless frag.empty?
    i += 1
  end
  html = out.join("\n")
  html.gsub(%r{<img[^>]*src="https://medium\.com/_/stat[^"]*"[^>]*/?>}i, "")
end

def excerpt_from_html(html)
  text = html.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
  return text if text.length <= 200

  "#{text[0, 200].strip}…"
end

def collect_post_ids(profile_json)
  ids = Set.new
  payload = profile_json["payload"] || {}

  (payload["streamItems"] || []).each do |item|
    pid = item.dig("postPreview", "postId")
    ids << pid if pid
  end
  (payload.dig("references", "Post") || {}).each_key { |id| ids << id }

  paging = payload["paging"]
  while paging && paging["next"]
    n = paging["next"]
    path = paging["path"]
    q = URI.encode_www_form(
      "limit" => n["limit"],
      "to" => n["to"],
      "source" => n["source"],
      "page" => n["page"]
    )
    url = "#{path}?#{q}"
    url = "https://medium.com#{url}" unless url.start_with?("http")
    data = http_get(url)
    pl = data["payload"] || {}
    (pl["streamItems"] || []).each do |item|
      pid = item.dig("postPreview", "postId")
      ids << pid if pid
    end
    (pl.dig("references", "Post") || {}).each_key { |id| ids << id }
    paging = pl["paging"]
    warn "  … #{ids.size} post ids so far"
    sleep 0.6
  end

  ids.to_a
end

# Medium post id is the last `-hex` segment before `.md` in Jekyll filenames we generate.
def post_ids_already_imported
  Set.new.tap do |s|
    Dir.glob(File.join(POSTS_DIR, "*.md")).each do |f|
      base = File.basename(f, ".md")
      s << m[1] if (m = base.match(/-([a-f0-9]{11,12})\z/i))
    end
  end
end

FileUtils.mkdir_p(POSTS_DIR)

if BATCH && BATCH.positive? && !SAVE_IDS && !File.file?(IDS_CACHE)
  warn <<~MSG

    --batch needs a post-id list at:
      #{IDS_CACHE}

    Create it once when Medium is not rate limiting:
      ruby scripts/import_medium_full.rb --save-ids

    Then run a few posts per day:
      ruby scripts/import_medium_full.rb --batch #{BATCH}
  MSG
  exit 1
end

use_cache = (FROM_IDS && File.file?(IDS_CACHE)) || (BATCH && BATCH.positive? && File.file?(IDS_CACHE))

ids =
  if use_cache
    warn "Loading post ids from #{IDS_CACHE} …"
    JSON.parse(File.read(IDS_CACHE, encoding: "UTF-8"))
  else
    warn "Fetching profile @#{USERNAME} …"
    profile = http_get("https://medium.com/@#{USERNAME}?format=json")
    user_id = profile.dig("payload", "user", "userId")
    raise "Could not read user id" unless user_id

    warn "Collecting post ids (user #{user_id}) …"
    collect_post_ids(profile)
  end

ids = ids.first(LIMIT) if LIMIT && LIMIT.positive?

unless FORCE
  already = post_ids_already_imported
  before = ids.size
  ids = ids.reject { |id| already.include?(id.to_s) }
  warn "Skipping #{before - ids.size} posts already present under _posts/"
end

if BATCH && BATCH.positive?
  ids = ids.first(BATCH)
  warn "Batch mode: will fetch at most #{ids.size} post(s) this run."
end

warn "Total posts to process this run: #{ids.size}"

if SAVE_IDS
  File.write(IDS_CACHE, JSON.pretty_generate(ids), encoding: "UTF-8")
  warn "Saved #{ids.size} ids to #{IDS_CACHE}"
  exit 0
end

if ids.empty?
  puts "Nothing to import — every id in the list already has a matching file under _posts/, or the list is empty."
  exit 0
end

imported = 0
skipped = 0

ids.each do |post_id|
  data = http_get("https://medium.com/_/api/posts/#{post_id}")
  post = data.dig("payload", "value")
  unless post
    warn "Skip #{post_id}: no payload"
    skipped += 1
    next
  end

  body_model = post.dig("content", "bodyModel")
  unless body_model
    warn "Skip #{post_id}: no bodyModel"
    skipped += 1
    next
  end

  title = post["title"].to_s.strip
  unique_slug = post["uniqueSlug"].to_s.strip
  canonical = post["webCanonicalUrl"].to_s.strip
  canonical = "https://medium.com/@#{USERNAME}/#{unique_slug}" if canonical.empty?

  published = post["firstPublishedAt"] || post["latestPublishedAt"]
  time = Time.at(published.to_f / 1000.0).utc
  date = time.to_date

  basename = "#{date}-#{unique_slug}.md"
  path = File.join(POSTS_DIR, basename)

  if File.exist?(path) && !FORCE
    skipped += 1
    next
  end

  tags = (post.dig("virtuals", "tags") || []).map { |tg| tg["slug"] }.compact
  primary = tags.shift
  cats = primary ? [primary] : []

  html = render_body_model(body_model)
  desc = excerpt_from_html(html)

  fm = {
    "layout" => "post",
    "title" => title,
    "date" => date.to_s,
    "description" => desc,
    "canonical_url" => canonical,
    "tags" => tags,
    "categories" => cats,
    "medium_original_url" => canonical,
  }

  yaml = fm.to_yaml(line_width: -1)
  File.write(path, "#{yaml}---\n\n#{html}\n", encoding: "UTF-8")
  puts "Wrote #{basename}"
  imported += 1
  sleep BATCH && BATCH.positive? ? 2.5 : 2.0
rescue StandardError => e
  warn "Error #{post_id}: #{e.message}"
  skipped += 1
  if BATCH && BATCH.positive? && e.message.include?("429")
    warn "Stopped early due to rate limiting. Run the same --batch command another day."
    break
  end
end

puts "Done. Imported: #{imported}, skipped: #{skipped}."
if BATCH && BATCH.positive? && File.file?(IDS_CACHE)
  remaining = JSON.parse(File.read(IDS_CACHE, encoding: "UTF-8")).reject { |id| post_ids_already_imported.include?(id.to_s) }
  warn "Roughly #{remaining.size} post(s) still not present under _posts/ (re-run --batch when ready)."
end
