# Scripts

Helpers for pulling **Medium** stories into this site’s Jekyll **`_posts/`** folder. The live site only shows what is committed there; Medium and GitHub Pages are not linked automatically.

## Prerequisites

- **Ruby** (3.x is fine) with Bundler for the site, plus gems available in your environment.
- **`import_medium_feed.rb`** uses **Nokogiri** (already pulled in via the site’s `github-pages` / Jekyll stack when you use `bundle exec` from the repo root, or install Nokogiri if you run plain `ruby` and hit a load error).
- Network access to `medium.com`.

On Windows, Ruby sometimes fails HTTPS verification when fetching URLs. For the RSS importer you can download the feed with **curl** and pass the file path (see below). The full importer uses `VERIFY_NONE` only inside the script for local tooling.

---

## `import_medium_full.rb` — full archive (API + body model)

Imports stories using Medium’s JSON APIs (`@username?format=json`, paginated profile stream, and `/_/api/posts/{id}`). Converts each post’s `bodyModel` into HTML for Jekyll.

**Important:** Medium often returns **HTTP 429** if you request too much at once. Prefer a **small daily batch** after you have saved the post-id list once.

### One-time: save all post IDs

When you are **not** rate limited (try another time of day if needed):

```bash
cd /path/to/axiomsamarth
ruby scripts/import_medium_full.rb --save-ids
```

This writes:

**`scripts/medium-post-ids.json`**

Re-run `--save-ids` occasionally if you want that file to include **new** Medium posts (or merge new IDs in by hand if you prefer).

### Daily (recommended): import a few missing posts

```bash
ruby scripts/import_medium_full.rb --batch 5
```

- Requires **`medium-post-ids.json`** (from `--save-ids` above).
- Skips posts that already exist under **`_posts/`** (it detects Medium’s post id from the filename, e.g. `…-12613b332d83.md`).
- Waits a few seconds between post requests to reduce 429s.
- If you still get **429**, stop and run the same command another day; the script reports roughly how many ids are still not imported.

### Other flags

| Flag | Meaning |
|------|--------|
| `--from-ids` | Use **`medium-post-ids.json`** instead of hitting the profile/stream APIs (same file **`--batch`** uses implicitly when present). |
| `--force` | Overwrite existing `_posts/*.md` files that match the same output name. |
| `--limit N` | Process at most **N** ids from the current list (after filters). |
| `--batch N` | Import at most **N** posts **not already on disk** (requires **`medium-post-ids.json`**). |

### After importing

1. Review generated files under **`_posts/`**.
2. **`git add`**, commit, and push so **GitHub Pages** rebuilds.

New Medium posts do **not** appear on this site until you import and deploy.

---

## `import_medium_feed.rb` — RSS (about 10 latest stories)

Medium’s user RSS feed (`https://medium.com/feed/@deyagondsamarth`) is easy to use but typically includes only the **most recent ~10** stories, not the full archive.

```bash
ruby scripts/import_medium_feed.rb [--force]
```

**Windows / SSL issues:** download the feed with curl, then import from the file:

```bash
curl.exe -sSL "https://medium.com/feed/@deyagondsamarth" -o scripts/medium-feed.xml
ruby scripts/import_medium_feed.rb scripts/medium-feed.xml [--force]
```

`medium-feed.xml` is listed in **`.gitignore`** so it is not committed by default.

RSS imports include `canonical_url` / `medium_original_url` in front matter and strip Medium’s 1×1 stat beacon when writing files.

---

## `strip_medium_tracking.rb`

Removes Medium RSS **tracking** `<img>` beacons from existing **`_posts/*.md`** files (safe to re-run).

```bash
ruby scripts/strip_medium_tracking.rb
```

---

## Files in this folder

| File | Role |
|------|------|
| **`medium-post-ids.json`** | Created by **`import_medium_full.rb --save-ids`**. List of Medium post ids for batch import. |
| **`medium-feed.xml`** | Optional local copy of the RSS feed (gitignored). |
| **`import_medium_full.rb`** | Full import via API + batch mode. |
| **`import_medium_feed.rb`** | Import via RSS (limited window). |
| **`strip_medium_tracking.rb`** | Clean tracking pixels from posts. |

Temporary `medium-*.json` files from debugging may appear here; you can delete them if you do not need them.
