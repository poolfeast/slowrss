![banner](assets/quickrss_banner.png)

An RSS/Atom fetcher for [KOReader](https://github.com/koreader/koreader). It turns every article in your feeds into a self-contained HTML file in a folder on your device. You read them in KOReader's own reader, so fonts, gestures, menus, dictionary lookup, highlights and reading status all work exactly as they do for a book.

## Features

- **One menu, one job.** Tools → QuickRSS → *Fetch articles* downloads all feeds and writes the new articles. A progress message shows what it's doing; tap it to abort.
- **Folders that follow your OPML.** Each feed gets its own folder, and OPML groups become parent folders: a feed in `<outline text="Tech">` lands in `Tech/<feed name>/`.
- **History that fills up.** Feeds only publish their latest handful of items. Articles stay in the folder after they leave the feed, so a feed's folder grows up to *Articles per feed* over successive fetches; beyond that the oldest files are deleted.
- **Title filters.** Per feed, keep or skip articles by keywords in the title (set in the OPML file, see below).
- **Self-contained files.** Images are embedded in the article file in their original quality (no stray image files in your folders); formats KOReader cannot display, such as AVIF or HEIC, are left out. Relative links are made absolute, so tapping a link gives you KOReader's normal link dialog with Show QR code.
- **Book metadata.** Each article carries the post's author, the feed name as series, its categories as keywords, its summary as description, and its lead image as cover, so KOReader's Book information and the cover browser show them. In the cover browser, *Detailed list with cover images and metadata* shows each cover next to its title and author.
- **No hidden database.** The files are the state. An article whose file exists is not fetched again, and only articles newer than the newest one on disk are written, so an older article you delete stays deleted. Files removed by the limit lose their KOReader metadata and history entry too.
- **Offline reading.** Everything is fetched up front; nothing is downloaded when you open an article.
- **Built from KOReader's own parts.** Menus, dialogs, progress messages, XML parsing, HTML helpers and file deletion all use KOReader's built-in modules, so the plugin is small and looks like the rest of KOReader.

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

1. **Add feeds**: Tools → QuickRSS → *Feeds* → *Add feed*. Name, URL, an optional folder such as `Tech/News`, and optional title filters. Tap a feed to edit or delete it. Or drop an OPML file at `koreader/quickrss/feeds.opml` (see below).
2. **Fetch**: Tools → QuickRSS → *Fetch articles*. When it finishes you get a summary with an *Open folder* button.
3. **Read**: open the articles folder in the file browser (Tools → QuickRSS → *Go to articles folder*). Files are named after the article title; a recurring title gets its date appended. Each file's date is the article's publish date, so sort by date to read newest first.

Deleting a file in the file browser tells QuickRSS you are done with that article; it will not be re-created on the next fetch. The exceptions: if you delete the newest article in a folder while it is still in the feed, or empty the folder, the next fetch writes them again.

### Settings

Tools → QuickRSS → *Settings*:

| Setting | Default | Description |
|---|---|---|
| Articles per feed | 20 | Maximum articles kept in each feed folder. The folder fills up to this number over successive fetches; older files are deleted beyond it. |
| Embed images | On | Embed images and covers. Images are kept at their original size, so image-heavy posts can be several MB; turn this off for much smaller files. |
| Articles folder | `koreader/quickrss/articles` | Where article files are written. Existing files stay where they are. |

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

Set them in the feed's edit dialog on the device, or add `quickrssInclude` and/or `quickrssExclude` to a feed's outline. Each is a `|`-separated list of keywords, matched case-insensitively anywhere in the title. With `quickrssInclude`, only titles containing at least one keyword are kept; `quickrssExclude` drops titles containing any keyword. Other RSS readers ignore these attributes.

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
nix flake check         # luacheck + unit tests (run inside KOReader's Lua environment)
nix develop             # shell with koreader and luacheck
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
├── main.lua                  Tools menu: fetch, feeds, settings, go-to-folder
├── _meta.lua                 Plugin metadata
└── modules/data/
    ├── fetcher.lua           One fetch: download, filter, write, trim
    ├── parser.lua            RSS / Atom parsing with KOReader's XML lexer
    ├── html.lua              Builds the article HTML
    ├── article_doc.lua       Writes article files with their cover and metadata sidecar
    ├── images.lua            Downloads images and keeps the formats KOReader can show
    ├── http.lua              HTTPS GET with redirects and retries
    ├── opml.lua              OPML with folders and title filters
    ├── filter.lua            Title include / exclude filter
    ├── dates.lua             Feed date parsing
    └── config.lua            Settings and feed list persistence
spec/                         Unit tests and the headless smoke test
```
