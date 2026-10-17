-- QuickRSS: Article HTML builder
-- Pure Lua (no KOReader dependencies).  Produces the self-contained HTML file
-- that KOReader opens for an article: a header with title, source and date,
-- then the body with images embedded as data: URIs and links made absolute.
-- Everything else (fonts, margins, justification) is the reader's business.
--
-- Public API:
--   Html.filename(article, disambiguate)  → "Title.html" or "Title (YYYY-MM-DD).html" (not yet filesystem-safe)
--   Html.canonical(link)                  → the <link rel="canonical"> tag identifying the article
--   Html.document(article, opts)          → html string
--     opts.images   include images at all
--     opts.embed    function(url) → "data:image/…;base64,…", or nil when the image
--                   could not be fetched or is a format the reader cannot show
--   Html.absolutizeLinks(html, base_url)  → html with relative hrefs resolved against base_url
--   Html.stripLeadingTitle(html, title)   → html without a leading heading equal to title

local Dates = require("modules/data/dates")
local md5   = require("ffi/sha2").md5
local url   = require("socket.url")
local util  = require("util")

local Html = {}

local function escape(s)
    return (util.htmlEscape(s or ""))
end

local CSS = [[
.meta { font-size: 0.85em; color: #555555; margin: 0 0 0.8em; }
figure { text-align: center; margin: 0.5em 0; }
hr { border: none; border-top: 1px solid #999999; margin: 0.8em 0 1em; }
]]

-- The file name is the title.  A recurring title ("Weekly links") gets the
-- date, or the link hash when undated, to tell the articles apart.
function Html.filename(article, disambiguate)
    local title = (article.title or ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
    if title == "" then title = md5(article.link):sub(1, 8) end
    if disambiguate then
        title = title .. " (" .. (Dates.iso(article.date) or md5(article.link):sub(1, 8)) .. ")"
    end
    return title .. ".html"
end

-- First thing in <head>, so the fetcher can tell which article a file holds
-- by reading only its first bytes.
function Html.canonical(link)
    return '<link rel="canonical" href="' .. escape(link) .. '"/>'
end

-- Remove the first <h1/h2/h3> whose plain text matches title.  Feeds often
-- repeat the article title as the first heading of the body, which is
-- redundant next to our own <h1>.
function Html.stripLeadingTitle(html, title)
    if not title or title == "" then return html end
    local function norm(s)
        return s
            :gsub("<[^>]+>", "")
            :gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
            :gsub("&quot;", '"'):gsub("&#39;", "'"):gsub("&[^;]+;", "")
            :gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
    end
    local title_norm = norm(title):lower()
    local result = html:gsub("<[hH][123][^>]*>([%s%S]-)</[hH][123]>",
        function(inner)
            if norm(inner):lower() == title_norm then return "" end
        end, 1)
    return result
end

-- Fragments stay as they are so in-article footnotes keep working.
local function absolutize(href, base)
    if href:match("^#") or base == "" then return href end
    return url.absolute(base, href)
end

-- Relative links inside a standalone file would point nowhere; resolve them
-- against the article URL so the reader's link dialog gets a usable URL.
function Html.absolutizeLinks(html, base_url)
    if not base_url or base_url == "" then return html end
    return (html:gsub("([Hh][Rr][Ee][Ff]%s*=%s*)([\"'])(.-)%2", function(attr, quote, href)
        return attr .. quote .. absolutize(href, base_url) .. quote
    end))
end

local function escPat(s)
    return (s:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1"))
end

-- The lead image usually also appears in the body, often as another CDN size
-- variant ("photo-640x427.jpg" vs "photo-1152x648.jpg").  Remove every variant
-- so it is not shown twice.
local function stripLeadImageVariants(html, image_url)
    local base = image_url:match("^([^?#]+)") or image_url
    local stem = base:match("^(.-)%-%d+x%d+%.[^./]+$") or base:match("^(.+)%.[^./]+$")
    if stem and stem ~= "" then base = stem end
    local ep = escPat(base)
    html = html:gsub('<[Ii][Mm][Gg][^>]*[Ss][Rr][Cc]%s*=%s*"' .. ep .. '[^"]*"[^>]*/?>', "")
    html = html:gsub("<[Ii][Mm][Gg][^>]*[Ss][Rr][Cc]%s*=%s*'" .. ep .. "[^']*'[^>]*/?>", "")
    return html
end

-- Swap each image's source for the embedded data, keeping the publisher's
-- attributes: the reader already shrinks images wider than the page.  Images
-- that cannot be embedded are removed rather than left as broken boxes.
local function embedImages(html, base_url, opts)
    return (html:gsub("<[Ii][Mm][Gg][^>]*>", function(tag)
        if not opts.images then return "" end
        local pre, quote, src, post = tag:match("^(.-[Ss][Rr][Cc]%s*=%s*)([\"'])(.-)%2(.*)$")
        if not src then return "" end
        if src:match("^data:image/") then return tag end
        local data_uri = opts.embed(absolutize(src, base_url))
        if not data_uri then return "" end
        return pre .. quote .. data_uri .. quote .. post
    end))
end

function Html.document(article, opts)
    local parts = {}

    local lead = opts.images and article.image_url and opts.embed(article.image_url)
    if lead then
        table.insert(parts, '<div class="banner"><img src="' .. lead .. '"/></div>')
    end

    table.insert(parts, "<h1>" .. escape(article.title) .. "</h1>")

    local meta = {}
    for _, part in ipairs({ article.source, article.author }) do
        if part and part ~= "" then table.insert(meta, escape(part)) end
    end
    local date = Dates.display(article.date)
    if date then table.insert(meta, escape(date)) end
    if #meta > 0 then
        table.insert(parts, '<p class="meta">' .. table.concat(meta, " &#183; ") .. "</p>")
    end
    table.insert(parts, "<hr/>")

    local body = article.content or ""
    body = Html.stripLeadingTitle(body, article.title)
    if lead then
        body = stripLeadImageVariants(body, article.image_url)
    end
    body = Html.absolutizeLinks(body, article.link)
    body = embedImages(body, article.link, opts)
    table.insert(parts, body)

    return table.concat({
        "<!DOCTYPE html>",
        '<html>',
        "<head>",
        Html.canonical(article.link),
        '<meta charset="utf-8"/>',
        "<title>" .. escape(article.title) .. "</title>",
        "<style>" .. CSS .. "</style>",
        "</head>",
        "<body>",
        table.concat(parts, "\n"),
        "</body>",
        "</html>",
        "",
    }, "\n")
end

return Html
