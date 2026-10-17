-- QuickRSS: Text helpers
-- Pure Lua (no KOReader dependencies) so it can be unit-tested with plain
-- luajit.  Shared by the parser, the fetcher and the HTML builder.
--
-- Public API:
--   Text.hash(s)              → stable 8-char hex digest (djb2)
--   Text.escapeHtml(s)        → s with the five XML special characters escaped
--   Text.sanitizeHtml(html)   → html without script/style/iframe/… and event handlers
--   Text.titleMatches(title, include, exclude) → whether a title passes a feed's filter

local Text = {}

-- Non-cryptographic hash → stable 8-char hex string.
function Text.hash(s)
    local h = 5381
    for i = 1, #s do
        h = ((h * 33) + s:byte(i)) % 0x100000000
    end
    return string.format("%08x", h)
end

-- Escape the five XML/HTML special characters.
function Text.escapeHtml(s)
    local r = (s or "")
        :gsub("&",  "&amp;")
        :gsub("<",  "&lt;")
        :gsub(">",  "&gt;")
        :gsub('"',  "&quot;")
        :gsub("'",  "&#39;")
    return r
end

-- Remove unsafe HTML: block-level dangerous tags (script, iframe, …) and
-- inline event handlers / javascript: URLs.
function Text.sanitizeHtml(html)
    if type(html) ~= "string" or html == "" then return html end
    for _, tag in ipairs({"script", "style", "iframe", "object", "embed", "noscript"}) do
        -- [%s%S]- crosses newlines inside block-tag content
        html = html:gsub("<" .. tag .. "[^>]*>[%s%S]-</" .. tag .. ">", "")
        html = html:gsub("<" .. tag .. "[^>]*/>", "")
    end
    -- Event handler attributes (onclick=, onload=, …)
    html = html:gsub("%s+on[%w_%-]+%s*=%s*\"[^\"]*\"", "")
    html = html:gsub("%s+on[%w_%-]+%s*=%s*'[^']*'", "")
    -- Neutralise javascript: href/src values
    html = html:gsub("(href%s*=%s*\")javascript:[^\"]*\"", "%1\"")
    html = html:gsub("(href%s*=%s*')javascript:[^']*'",    "%1'")
    html = html:gsub("(src%s*=%s*\")javascript:[^\"]*\"",  "%1\"")
    html = html:gsub("(src%s*=%s*')javascript:[^']*'",     "%1'")
    return html
end

-- Filters are "|"-separated keywords matched case-insensitively anywhere in
-- the title.  An empty include list lets everything through.
local function hasKeyword(title, list)
    for keyword in list:gmatch("[^|]+") do
        keyword = keyword:match("^%s*(.-)%s*$"):lower()
        if keyword ~= "" and title:find(keyword, 1, true) then return true end
    end
    return false
end

function Text.titleMatches(title, include, exclude)
    title = (title or ""):lower()
    if include ~= "" and not hasKeyword(title, include) then return false end
    return not hasKeyword(title, exclude)
end

return Text
