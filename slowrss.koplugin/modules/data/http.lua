-- SlowRSS: HTTP
--
-- Public API:
--   Http.get(url) → body, or nil, err

local logger = require("logger")

local Http = {}

-- Synchronous GET following up to three redirects, retrying transient
-- network errors twice.  Returns body, or nil, err.
function Http.get(url)
    local https      = require("ssl.https")
    local ltn12      = require("ltn12")
    local socketutil = require("socketutil")

    local MAX_RETRIES = 2
    for attempt = 1, MAX_RETRIES + 1 do
        local current_url = url
        local sink, ok, code, headers
        for _ = 1, 3 do
            sink = {}
            socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
            ok, code, headers = https.request{ url = current_url, sink = ltn12.sink.table(sink) }
            socketutil:reset_timeout()
            if not ok then break end
            if code == 301 or code == 302 or code == 303 or code == 307 or code == 308 then
                local location = headers and headers["location"]
                if not location or location == "" then
                    return nil, "redirect without Location"
                end
                current_url = location
            else
                break
            end
        end
        if ok then
            if code ~= 200 then return nil, "HTTP " .. tostring(code) end
            return table.concat(sink)
        end
        if attempt > MAX_RETRIES then return nil, tostring(code) end
        logger.dbg("SlowRSS: image retry", attempt, "for:", url, code)
    end
end

return Http
