![banner](assets/quickrss_banner.png)

An RSS/Atom fetcher for [KOReader](https://github.com/koreader/koreader). It turns every article in your feeds into a self-contained HTML file in a folder on your device. You read them in KOReader's own reader, so fonts, gestures, menus, dictionary lookup, highlights and reading status all work exactly as they do for a book.

## Features

- **One menu, one job.** Tools → QuickRSS → *Fetch articles* downloads all feeds and writes the new articles. A progress message shows what it's doing; tap it to abort.
- **Folders that follow your OPML.** Each feed gets its own folder, and OPML groups become parent folders: a feed in `<outline text="Tech">` lands in `Tech/<feed name>/`.
- **History that fills up.** Feeds only publish their latest handful of items. Articles stay in the folder after they leave the feed, so a feed's folder grows up to *Articles per feed* over successive fetches; beyond that the oldest files are deleted.
- **Title filters.** Per feed, keep or skip articles by keywords in the title (set in the OPML file, see below).
- **Self-contained files.** Images are embedded in the article file (no stray image files in your folders) and relative links are made absolute, so tapping a link gives you KOReader's normal link dialog with Copy and Show QR code.
- **Full-text extraction.** Truncated feeds are completed through a [FiveFilters](https://fivefilters.org/) instance (the public one by default, or your own). Can be turned off.
- **No hidden database.** The files are the state. An article whose file exists is not fetched again, and only articles newer than the newest one on disk are written, so an older article you delete stays deleted. Files removed by the limit lose their KOReader metadata and history entry too.
- **Offline reading.** Everything is fetched up front; nothing is downloaded when you open an article.

## Installation

Copy `quickrss.koplugin/` into your KOReader plugins folder and restart KOReader:

| Platform | Path |
|---|---|
| Linux desktop | `~/.config/koreader/plugins/` |
| Kindle | `/mnt/us/extensions/koreader/plugins/` |
| Kobo | `.adds/koreader/plugins/` |
| PocketBook | `applications/koreader/plugins/` |

With Nix: `nix build github:poolfeast/slowreader` gives you the plugin directory under `result/`, and `nix build .#zip` builds the release archive.

## Usage

1. **Add feeds**: Tools → QuickRSS → *Feeds* → *+ Add Feed*. Name, URL and an optional folder such as `Tech/News`. Or drop an OPML file at `koreader/quickrss/feeds.opml` (see below).
2. **Fetch**: Tools → QuickRSS → *Fetch articles*. When it finishes you get a summary with an *Open folder* button.
3. **Read**: open the articles folder in the file browser (Tools → QuickRSS → *Go to articles folder*). Files are named after the article title; a recurring title gets its date appended. Each file's date is the article's publish date, so sort by date to read newest first.

Deleting a file in the file browser tells QuickRSS you are done with that article; it will not be re-created on the next fetch. The exceptions: if you delete the newest article in a folder while it is still in the feed, or empty the folder, the next fetch writes them again.

### Settings

Tools → QuickRSS → *Settings*:

| Setting | Default | Description |
|---|---|---|
| Articles per feed | 20 | Maximum articles kept in each feed folder. The folder fills up to this number over successive fetches; older files are deleted beyond it. |
| Article images | On | Embed images in articles. Off gives much smaller files. |
| Full-text extraction | On | Complete truncated articles through the extraction service. |
| Extraction URL | FiveFilters public instance | URL of a self-hosted FiveFilters instance. |
| Custom DNS routing | Off | Resolve hosts through Google and Cloudflare DNS instead of the device resolver. |
| Articles folder | `koreader/quickrss/articles` | Where article files are written. Existing files stay where they are. |

### Custom DNS routing

If feeds or images fail to load even though the device is connected to WiFi, try *Custom DNS routing*. On some e-readers (notably Kobo) the built-in resolver stops working reliably after a while; this setting bypasses it.

## OPML

Feeds are stored as a standard OPML file at `koreader/quickrss/feeds.opml`. Edit it in a text editor or replace it with an export from another reader (Feedly, NewsBlur, Miniflux, …). Nested outlines are folders:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<opml version="1.0">
  <head><title>QuickRSS Feeds</title></head>
  <body>
    <outline text="Ars Technica" type="rss" xmlUrl="https://feeds.arstechnica.com/arstechnica/index"/>
    <outline text="Making">
      <outline text="Hackaday" type="rss" xmlUrl="https://hackaday.com/blog/feed/"/>
    </outline>
  </body>
</opml>
```

produces

```
articles/
├── Ars Technica/
│   └── Some headline.html
└── Making/
    └── Hackaday/
        └── Another headline.html
```

Changes made on the device are written back to the same file.

### Title filters

Add `quickrssInclude` and/or `quickrssExclude` to a feed's outline. Each is a `|`-separated list of keywords, matched case-insensitively anywhere in the title. With `quickrssInclude`, only titles containing at least one keyword are kept; `quickrssExclude` drops titles containing any keyword. Other RSS readers ignore these attributes.

```xml
<outline text="Ars Technica" type="rss" xmlUrl="https://feeds.arstechnica.com/arstechnica/index"
         quickrssInclude="space|nasa|rocket" quickrssExclude="deals|sponsored"/>
```

## Development

The repository is a Nix flake.

```bash
nix run                 # install the plugin into ~/.config/koreader and start KOReader
KO_HOME=/tmp/ko nix run # same, with a throwaway KOReader data directory
nix run .#smoke         # headless fetch of two live feeds, opens an article, saves screenshots
nix flake check         # luacheck + unit tests
nix develop             # shell with koreader, luajit, luacheck
luajit spec/run.lua     # unit tests only
```

`nix run` snapshots the git tree, so `git add` new files before running.

## Data storage

Everything lives in `quickrss/` inside the KOReader data directory (`~/.config/koreader/` on Linux, `koreader/` on devices):

| File / Directory | Contents |
|---|---|
| `feeds.opml` | Feed list |
| `settings.lua` | Settings |
| `articles/` | The article files (default location) |

## Project structure

```
quickrss.koplugin/
├── main.lua                  Menu entry, fetch progress UI, go-to-folder
├── _meta.lua                 Plugin metadata
└── modules/
    ├── ui/
    │   ├── feed_list.lua     Feed management popup (add / remove, folders)
    │   ├── settings.lua      Settings popup
    │   ├── settings_row.lua  Shared settings row builder
    │   └── icons.lua         Icon glyphs
    ├── data/
    │   ├── fetcher.lua       One fetch: download, filter, write, trim
    │   ├── parser.lua        RSS / Atom fetching and parsing, full-text extraction
    │   ├── html.lua          Builds the article HTML (pure Lua)
    │   ├── article_doc.lua   Writes and removes article files
    │   ├── images.lua        Downloads images as data: URIs
    │   ├── opml.lua          OPML with folders (pure Lua)
    │   ├── dates.lua         Feed date parsing (pure Lua)
    │   ├── text.lua          Hashing, escaping, sanitising, title filter (pure Lua)
    │   └── config.lua        Settings and feed list persistence
    └── lib/                  Third-party XML parser and the custom DNS resolver
spec/                         Unit tests for the pure modules and the headless smoke test
```
