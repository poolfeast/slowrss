-- SlowRSS: Date helpers
-- Pure Lua (no KOReader dependencies).  Feeds publish dates as RFC 822
-- (RSS pubDate) or ISO-8601 (Atom published/updated); everything here
-- accepts either.
--
-- Public API:
--   Dates.parse(raw)              → Unix timestamp, or nil when unparseable
--   Dates.iso(raw)                → "YYYY-MM-DD", or nil when unparseable
--   Dates.display(raw)            → short human-readable form, or nil when empty

local Dates = {}

local MONTHS = {
    Jan=1, Feb=2, Mar=3, Apr=4, May=5, Jun=6,
    Jul=7, Aug=8, Sep=9, Oct=10, Nov=11, Dec=12,
}

-- Parse an RSS pubDate or Atom ISO-8601 date string into a Unix timestamp.
function Dates.parse(raw)
    if not raw or raw == "" then return nil end
    -- Atom ISO-8601: "2026-03-01T12:00:00Z" or "2026-03-01T12:00:00+00:00"
    local y, m, d, H, M, S = raw:match("(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)")
    if y then
        return os.time{ year=tonumber(y), month=tonumber(m), day=tonumber(d),
                         hour=tonumber(H), min=tonumber(M), sec=tonumber(S) }
    end
    -- RSS pubDate: "Mon, 01 Mar 2026 12:00:00 +0000"
    d, m, y, H, M, S = raw:match("(%d+)%s+(%a+)%s+(%d%d%d%d)%s+(%d%d):(%d%d):(%d%d)")
    if d and MONTHS[m] then
        return os.time{ year=tonumber(y), month=MONTHS[m], day=tonumber(d),
                         hour=tonumber(H), min=tonumber(M), sec=tonumber(S) }
    end
    -- Date-only fallback: "2026-03-01"
    y, m, d = raw:match("(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if y then
        return os.time{ year=tonumber(y), month=tonumber(m), day=tonumber(d),
                         hour=0, min=0, sec=0 }
    end
    return nil
end

-- "YYYY-MM-DD" for EPUB metadata.
function Dates.iso(raw)
    if not raw or raw == "" then return nil end
    local y, m, d = raw:match("(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if y then return y .. "-" .. m .. "-" .. d end
    d, m, y = raw:match("(%d+)%s+(%a+)%s+(%d%d%d%d)")
    if d and MONTHS[m] then
        return string.format("%s-%02d-%02d", y, MONTHS[m], tonumber(d))
    end
    return nil
end

-- Short human-readable date for cards and the article header:
-- "Mon, 01 Jan 2024 00:00:00 +0000" → "01 Jan 2024", "2024-01-01T…" → "2024-01-01".
-- Anything unrecognised is returned as-is so the user still sees what the feed sent.
function Dates.display(raw)
    if not raw or raw == "" then return nil end
    local d = raw:match("%a+,%s+(%d+%s+%a+%s+%d+)")
    if d then return d end
    d = raw:match("(%d%d%d%d%-%d%d%-%d%d)")
    if d then return d end
    return raw
end

return Dates
