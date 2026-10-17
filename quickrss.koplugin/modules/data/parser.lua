-- QuickRSS: Parser Module
-- HTTP fetcher + XML parser that normalises RSS 2.0 and Atom feeds into a
-- flat article list.
--
-- Public API:
--   Parser.fetchFeed(url) → articles, or nil, error
--   Parser.parse(raw_xml) → { feed_title, articles = { article, … } }, or nil, error
--     article = { title, link, date, content, image_url,
--                 author, categories = { … }, summary, language }   (missing strings are "")

local logger = require("logger")

local Parser = {}

-- ── _fetchRaw ─────────────────────────────────────────────────────────────────
-- Synchronous HTTPS GET. Returns (body_string, nil) on success or
-- (nil, error_string) on failure.

local function _fetchRaw(url)
    local https      = require("ssl.https")
    local ltn12      = require("ltn12")
    local socketutil = require("socketutil")
    local sink = {}
    socketutil:set_timeout(
        socketutil.LARGE_BLOCK_TIMEOUT,
        socketutil.LARGE_TOTAL_TIMEOUT
    )
    local ok, code, _, status = https.request{
        url  = url,
        sink = ltn12.sink.table(sink),
    }
    socketutil:reset_timeout()

    if not ok then return nil, tostring(code) end
    if code ~= 200 then
        return nil, "HTTP " .. tostring(code) .. " – " .. tostring(status)
    end
    return table.concat(sink), nil
end

-- ── Text helpers ─────────────────────────────────────────────────────────────

-- Encode a Unicode code point as a UTF-8 string.
local function utf8char(cp)
    if cp < 0x80 then
        return string.char(cp)
    elseif cp < 0x800 then
        return string.char(
            0xC0 + math.floor(cp / 0x40),
            0x80 + cp % 0x40)
    elseif cp < 0x10000 then
        return string.char(
            0xE0 + math.floor(cp / 0x1000),
            0x80 + math.floor(cp / 0x40) % 0x40,
            0x80 + cp % 0x40)
    elseif cp < 0x110000 then
        return string.char(
            0xF0 + math.floor(cp / 0x40000),
            0x80 + math.floor(cp / 0x1000) % 0x40,
            0x80 + math.floor(cp / 0x40) % 0x40,
            0x80 + cp % 0x40)
    end
    return ""
end

-- Decode HTML/XML numeric and named character entities.
local function decodeEntities(s)
    if not s or s == "" then return s end
    s = s:gsub("&#(%d+);", function(n)
        local cp = tonumber(n)
        return cp and cp >= 32 and utf8char(cp) or ""
    end)
    s = s:gsub("&#[xX](%x+);", function(h)
        local cp = tonumber(h, 16)
        return cp and cp >= 32 and utf8char(cp) or ""
    end)
    s = s:gsub("&nbsp;",  " ")
    s = s:gsub("&lt;",    "<")
    s = s:gsub("&gt;",    ">")
    s = s:gsub("&quot;",  '"')
    s = s:gsub("&apos;",  "'")
    s = s:gsub("&amp;",   "&")  -- must be last to avoid double-decoding
    return s
end

-- Extract the src URL of the first <img> element found in an HTML string.
local function firstImageUrl(html)
    if not html then return nil end
    return html:match('<img[^>]+src%s*=%s*"(https?://[^"]+)"')
        or html:match("<img[^>]+src%s*=%s*'(https?://[^']+)'")
end

-- ── fetchFeed ────────────────────────────────────────────────────────
-- Download and parse one feed.  Returns its articles (newest first, as the
-- feed lists them) or nil, error.
function Parser.fetchFeed(url)
    url = url:match("^https?://") and url or ("https://" .. url)
    logger.info("QuickRSS fetching:", url)
    local raw_xml, err = _fetchRaw(url)
    if not raw_xml then return nil, err end
    local result, parse_err = Parser.parse(raw_xml)
    if not result then return nil, tostring(parse_err) end
    return result.articles
end

-- ── parse helpers ─────────────────────────────────────────────────────────────

-- Extract the best thumbnail URL for an item, preferring explicit media
-- namespace / enclosure declarations over scraping the HTML body.
local function extractThumbnailUrl(raw, content)
    -- <media:thumbnail url="..."/>
    local mt = raw["media:thumbnail"]
    if type(mt) == "table" and mt._attr and mt._attr.url then
        return mt._attr.url
    end
    -- <media:content url="..." medium="image"> or type="image/..."
    local mc = raw["media:content"]
    if type(mc) == "table" and mc._attr and mc._attr.url then
        local med  = mc._attr.medium or ""
        local mime = mc._attr.type   or ""
        if med == "image" or mime:match("^image/") then
            return mc._attr.url
        end
    end
    -- <enclosure url="..." type="image/..."/>  (RSS 2.0)
    local enc = raw.enclosure
    if type(enc) == "table" and enc._attr and enc._attr.url then
        if (enc._attr.type or ""):match("^image/") then
            return enc._attr.url
        end
    end
    -- Fall back to first remote <img> found in the HTML body
    return firstImageUrl(content)
end

-- Safely coerce a value that may be a string or a single-element table to a
-- string.  simpleTreeHandler sometimes wraps plain text in a 1-element table.
local function toStr(v)
    if type(v) == "string" then return v end
    if type(v) == "table"  then return toStr(v[1]) end
    return ""
end

-- Ensure a value that may be a table of items OR a single item is always
-- returned as an array.  simpleTreeHandler reduces 1-element vectors.
local function toArray(v)
    if type(v) ~= "table" then return {} end
    -- A vector has integer keys 1..n; a single reduced item has string keys.
    if v[1] ~= nil then return v end
    return { v }  -- wrap the single item so callers can always ipairs()
end

-- Single elements come back as a string or a table, repeated ones as an array.
local function list(v)
    if type(v) == "string" then return { v } end
    return toArray(v)
end

local function stripTags(html)
    return (decodeEntities(html:gsub("<[^>]+>", " ")):gsub("%s+", " "):match("^%s*(.-)%s*$"))
end

-- RSS: <dc:creator>, or <author> as "mail@example.com (Name)".  Atom: <author><name>.
local function authorOf(raw, is_atom)
    if is_atom then
        local a = list(raw.author)[1]
        return a and toStr(a.name) or ""
    end
    local a = toStr(raw["dc:creator"])
    if a == "" then a = toStr(raw.author) end
    return a:match("%((.-)%)%s*$") or a
end

-- RSS: <category>Text</category>.  Atom: <category term="Text"/>.
local function categoriesOf(raw)
    local out = {}
    for _, c in ipairs(list(raw.category)) do
        local text = type(c) == "table" and c._attr and c._attr.term or toStr(c)
        text = decodeEntities(text)
        if text ~= "" then table.insert(out, text) end
    end
    return out
end

-- ── parse ─────────────────────────────────────────────────────────────────────
-- Convert a raw RSS 2.0 or Atom XML string into a normalised result table.
-- Returns (result_table, nil) on success, (nil, error_string) on failure.
function Parser.parse(raw_xml)
    local xmlParser     = require("modules/lib/xml").xmlParser
    local treeHandler   = require("modules/lib/handler").simpleTreeHandler

    -- Strip the UTF-8 BOM that some feeds prepend (xml.lua doesn't handle it)
    raw_xml = raw_xml:gsub("^\xef\xbb\xbf", "", 1)

    local handler = treeHandler()
    local ok, err = pcall(function()
        xmlParser(handler):parse(raw_xml)
    end)
    if not ok then
        logger.warn("QuickRSS XML parse error:", err)
        return nil, tostring(err)
    end

    local tree = handler.root
    local feed_title, raw_items, is_atom

    -- ── Detect feed format ──────────────────────────────────────────────────
    local language
    if tree.rss and tree.rss.channel then
        local ch  = tree.rss.channel
        feed_title = toStr(ch.title)
        raw_items  = toArray(ch.item)
        language   = toStr(ch.language)
    elseif tree.feed then
        is_atom    = true
        feed_title = toStr(tree.feed.title)
        raw_items  = toArray(tree.feed.entry)
        language   = tree.feed._attr and tree.feed._attr["xml:lang"] or ""
    else
        return nil, "Unrecognised feed format"
    end

    logger.info("QuickRSS parsed feed:", feed_title, "items:", #raw_items)

    -- ── Normalise each item/entry ───────────────────────────────────────────
    local articles = {}
    for _, raw in ipairs(raw_items) do
        local title, link, content, summary

        if is_atom then
            title   = toStr(raw.title)
            -- Atom <link> may be a single {_attr={href=…}} or an array of them
            -- when the entry has multiple <link> elements (e.g. alternate + self).
            if type(raw.link) == "table" then
                if raw.link._attr then
                    -- Single <link>
                    link = raw.link._attr.href or ""
                elseif raw.link[1] then
                    -- Multiple <link> elements: prefer rel="alternate"
                    link = ""
                    for _, l in ipairs(raw.link) do
                        if type(l) == "table" and l._attr then
                            if l._attr.rel == "alternate" or not l._attr.rel then
                                link = l._attr.href or ""
                                break
                            end
                        end
                    end
                    -- Fall back to first link if no alternate found
                    if link == "" and type(raw.link[1]) == "table"
                                  and raw.link[1]._attr then
                        link = raw.link[1]._attr.href or ""
                    end
                else
                    link = ""
                end
            else
                link = toStr(raw.link)
            end
            -- Atom full text may be in <content> or <summary>
            content = toStr(raw.content ~= nil and raw.content or raw.summary)
            summary = raw.content ~= nil and toStr(raw.summary) or ""
        else
            title   = toStr(raw.title)
            link    = toStr(raw.link)
            -- RSS full text is in <content:encoded>; fall back to <description>
            content = toStr(raw["content:encoded"] ~= nil
                            and raw["content:encoded"]
                            or  raw.description)
            summary = raw["content:encoded"] ~= nil and toStr(raw.description) or ""
        end

        -- Publication date: pubDate (RSS) or published/updated (Atom)
        local date = is_atom
            and toStr(raw.published or raw.updated or "")
            or  toStr(raw.pubDate or "")

        -- Decode HTML entities in the title (e.g. &#8217; → ')
        title = decodeEntities(title)
        -- Cap title length to prevent memory issues with malformed feeds.
        if #title > 500 then title = title:sub(1, 499) .. "…" end

        table.insert(articles, {
            title     = title,
            link      = link,
            date      = date,
            content   = content,
            image_url = extractThumbnailUrl(raw, content),
            author     = decodeEntities(authorOf(raw, is_atom)),
            categories = categoriesOf(raw),
            summary    = stripTags(summary),
            language   = language,
        })
    end

    return { feed_title = feed_title, articles = articles }, nil
end

return Parser
