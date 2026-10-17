-- QuickRSS: Feed parser
-- Downloads RSS 2.0 and Atom feeds and turns them into a flat article list,
-- using KOReader's XML lexer (luxl), as its OPDS plugin does.
--
-- Public API:
--   Parser.fetchFeed(url) → articles, or nil, error
--   Parser.parse(xml)     → articles, or nil, error
--     article = { title, link, date, content, image_url, author,
--                 categories = { … }, summary, language }   (missing strings are "")

local Http = require("modules/data/http")
local ffi  = require("ffi")
local luxl = require("luxl")
local util = require("util")

local Parser = {}

local function escapeMarkup(s)
    return (s:gsub("[&<>]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" }))
end

-- luxl is strict: it wants plain elements with text.  Turn CDATA and inline
-- (X)HTML inside content elements into escaped text, drop comments,
-- processing instructions and doctypes, and expand self-closing tags.
local function prepare(xml)
    xml = xml:gsub("^\239\187\191", "")
    xml = xml:gsub("<!%[CDATA%[(.-)%]%]>", escapeMarkup)
    xml = xml:gsub("<!%-%-.-%-%->", ""):gsub("<%?.-%?>", ""):gsub("<!DOCTYPE.->", "")
    xml = xml:gsub("<([%w:_%-]+)([^<>]-)/>", "<%1%2></%1>")
    for _, tag in ipairs({ "content:encoded", "content", "description", "summary" }) do
        xml = xml:gsub("(<" .. tag .. "%f[%s>][^>]*>)(.-)(</" .. tag .. ">)", function(open, inner, close)
            if inner:find("<", 1, true) then inner = escapeMarkup(inner) end
            return open .. inner .. close
        end)
    end
    return xml
end

-- Element tree of { name, attrs, text, children }.
local function buildTree(xml)
    local xlex = luxl.new(xml, #xml)
    local root = { name = "", attrs = {}, text = "", children = {} }
    local stack = { root }
    local attr_name
    for event, offset, size in xlex:Lexemes() do
        local top = stack[#stack]
        local txt = ffi.string(xlex.buf + offset, size)
        if event == luxl.EVENT_START then
            local node = { name = txt, attrs = {}, text = "", children = {} }
            table.insert(top.children, node)
            table.insert(stack, node)
        elseif event == luxl.EVENT_ATTR_NAME then
            attr_name = txt
        elseif event == luxl.EVENT_ATTR_VAL then
            top.attrs[attr_name] = util.htmlEntitiesToUtf8(txt)
        elseif event == luxl.EVENT_TEXT then
            top.text = top.text .. util.htmlEntitiesToUtf8(txt)
        elseif event == luxl.EVENT_END then
            table.remove(stack)
        end
    end
    return root
end

local function children(node, name)
    local out = {}
    for _, c in ipairs(node.children) do
        if c.name == name then table.insert(out, c) end
    end
    return out
end

local function child(node, name)
    return children(node, name)[1]
end

local function text(node, name)
    local c = child(node, name)
    return c and util.trim(c.text) or ""
end

-- Prefer explicit media declarations; fall back to the first remote <img>.
local function thumbnail(item, content)
    local t = child(item, "media:thumbnail")
    if t and t.attrs.url then return t.attrs.url end
    for _, name in ipairs({ "media:content", "enclosure" }) do
        local m = child(item, name)
        if m and m.attrs.url and (m.attrs.medium == "image" or (m.attrs.type or ""):match("^image/")) then
            return m.attrs.url
        end
    end
    return content:match('<img[^>]+src%s*=%s*"(https?://[^"]+)"')
        or content:match("<img[^>]+src%s*=%s*'(https?://[^']+)'")
end

local function categories(item, attr)
    local out = {}
    for _, c in ipairs(children(item, "category")) do
        local value = util.trim(attr and c.attrs[attr] or c.text)
        if value ~= "" then table.insert(out, value) end
    end
    return out
end

local function rssItem(item, language)
    local encoded = child(item, "content:encoded")
    local description = text(item, "description")
    local content = encoded and encoded.text or description
    -- <dc:creator>Name</dc:creator>, or <author>mail@example.com (Name)</author>
    local author = text(item, "dc:creator")
    if author == "" then
        author = text(item, "author")
        author = author:match("%((.-)%)%s*$") or author
    end
    return {
        title      = util.htmlEntitiesToUtf8(text(item, "title")),
        link       = text(item, "link"),
        date       = text(item, "pubDate"),
        content    = content,
        image_url  = thumbnail(item, content),
        author     = author,
        categories = categories(item),
        summary    = encoded and util.htmlToPlainText(description) or "",
        language   = language,
    }
end

local function atomEntry(entry, language)
    local link = ""
    for _, l in ipairs(children(entry, "link")) do
        if (l.attrs.rel or "alternate") == "alternate" then
            link = l.attrs.href or ""
            break
        end
    end
    local body = child(entry, "content")
    local summary = text(entry, "summary")
    local content = body and body.text or summary
    local author = child(entry, "author")
    local date = text(entry, "published")
    return {
        title      = util.htmlEntitiesToUtf8(text(entry, "title")),
        link       = link,
        date       = date ~= "" and date or text(entry, "updated"),
        content    = content,
        image_url  = thumbnail(entry, content),
        author     = author and text(author, "name") or "",
        categories = categories(entry, "term"),
        summary    = body and util.htmlToPlainText(summary) or "",
        language   = language,
    }
end

function Parser.parse(xml)
    local ok, root = pcall(buildTree, prepare(xml))
    if not ok then return nil, tostring(root) end
    local articles = {}
    local rss = child(root, "rss")
    local channel = rss and child(rss, "channel")
    local feed = child(root, "feed")
    if channel then
        local language = text(channel, "language")
        for _, item in ipairs(children(channel, "item")) do
            table.insert(articles, rssItem(item, language))
        end
    elseif feed then
        local language = feed.attrs["xml:lang"] or ""
        for _, entry in ipairs(children(feed, "entry")) do
            table.insert(articles, atomEntry(entry, language))
        end
    else
        return nil, "Unrecognised feed format"
    end
    return articles
end

function Parser.fetchFeed(url)
    url = url:match("^https?://") and url or ("https://" .. url)
    local body, err = Http.get(url)
    if not body then return nil, err end
    return Parser.parse(body)
end

return Parser
