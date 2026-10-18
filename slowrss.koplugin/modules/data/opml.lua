-- SlowRSS: OPML Module
-- Pure Lua (no KOReader dependencies).  Reads and writes the standard OPML
-- feed-list format so subscriptions can be managed from a computer or
-- imported from another RSS reader.  Nested <outline> groups are folders:
-- a feed inside <outline text="Tech"> gets folder = "Tech", and its articles
-- are written to a "Tech/<feed name>" directory.
--
-- Feeds may carry SlowRSS settings as extra attributes, which other readers
-- ignore:  slowrssInclude="space|nasa"  slowrssExclude="deals|sponsored"
--          slowrssLimit="40" (articles to fetch; the default setting when absent)
--
-- Public API:
--   OPML.parse(content)        → { {name, url, folder, include, exclude, limit}, … }  missing strings are "", limit nil
--   OPML.serialize(feeds)      → OPML document string
--   OPML.read(path)            → feeds, or nil if the file does not exist
--   OPML.write(path, feeds)    → true on success, false on I/O error

local OPML = {}

local function unescAttr(s)
    return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"')
             :gsub("&apos;", "'"):gsub("&amp;", "&"))
end

local function escAttr(s)
    return (s or "")
        :gsub("&",  "&amp;")
        :gsub('"',  "&quot;")
        :gsub("'",  "&apos;")
        :gsub("<",  "&lt;")
        :gsub(">",  "&gt;")
end

local function getAttr(tag, name)
    local val = tag:match(name .. '%s*=%s*"([^"]*)"')
             or tag:match(name .. "%s*=%s*'([^']*)'")
    return val and unescAttr(val) or nil
end

-- Walk the <outline> tags in document order, keeping a stack of the folders
-- currently open.  Self-closing outlines with an xmlUrl are feeds; outlines
-- with children are folders.
function OPML.parse(content)
    local feeds = {}
    local stack = {}
    for closing, attrs in content:gmatch("<(/?)outline([^>]*)>") do
        if closing == "/" then
            table.remove(stack)
        else
            local self_closing = attrs:match("/%s*$") ~= nil
            local name = getAttr(attrs, "text") or getAttr(attrs, "title") or ""
            local url  = getAttr(attrs, "xmlUrl")
            if url and url ~= "" then
                table.insert(feeds, {
                    name    = name,
                    url     = url,
                    folder  = table.concat(stack, "/"),
                    include = getAttr(attrs, "slowrssInclude") or "",
                    exclude = getAttr(attrs, "slowrssExclude") or "",
                    limit   = tonumber(getAttr(attrs, "slowrssLimit") or ""),
                })
            end
            if not self_closing then
                table.insert(stack, name)
            end
        end
    end
    return feeds
end

-- Group feeds by folder path (in order of first appearance) and emit nested
-- outlines.
function OPML.serialize(feeds)
    local root = { folders = {}, order = {}, feeds = {} }
    for _, feed in ipairs(feeds) do
        local node = root
        if feed.folder and feed.folder ~= "" then
            for segment in feed.folder:gmatch("[^/]+") do
                if not node.folders[segment] then
                    node.folders[segment] = { folders = {}, order = {}, feeds = {} }
                    table.insert(node.order, segment)
                end
                node = node.folders[segment]
            end
        end
        table.insert(node.feeds, feed)
    end

    local lines = {
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<opml version="1.0">',
        "  <head><title>SlowRSS Feeds</title></head>",
        "  <body>",
    }
    local function emit(node, indent)
        for _, feed in ipairs(node.feeds) do
            local filter = ""
            if feed.include ~= "" then filter = filter .. string.format(' slowrssInclude="%s"', escAttr(feed.include)) end
            if feed.exclude ~= "" then filter = filter .. string.format(' slowrssExclude="%s"', escAttr(feed.exclude)) end
            if feed.limit then filter = filter .. string.format(' slowrssLimit="%d"', feed.limit) end
            table.insert(lines, string.format('%s<outline text="%s" title="%s" type="rss" xmlUrl="%s"%s/>',
                indent, escAttr(feed.name), escAttr(feed.name), escAttr(feed.url), filter))
        end
        for _, name in ipairs(node.order) do
            table.insert(lines, string.format('%s<outline text="%s" title="%s">',
                indent, escAttr(name), escAttr(name)))
            emit(node.folders[name], indent .. "  ")
            table.insert(lines, indent .. "</outline>")
        end
    end
    emit(root, "    ")
    table.insert(lines, "  </body>")
    table.insert(lines, "</opml>")
    return table.concat(lines, "\n") .. "\n"
end

function OPML.read(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return OPML.parse(content)
end

function OPML.write(path, feeds)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(OPML.serialize(feeds))
    f:close()
    return true
end

return OPML
