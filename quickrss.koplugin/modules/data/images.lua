-- QuickRSS: Image download
--
-- Public API:
--   Images.download(url)          → data, mime_type, or nil when the download failed or
--                                   the format is one the reader cannot render
--   Images.dataUri(data, mime)    → "data:<mime>;base64,<data>" for embedding in an article
--   Images.extension(mime)        → file extension for a supported mime type

local logger = require("logger")
local mime   = require("mime")

-- Formats crengine renders.  Anything else (HEIC, AVIF, HTML error pages…)
-- would show as a broken box, so it is dropped instead.
local MIME_BY_EXT = {
    jpg  = "image/jpeg",
    jpeg = "image/jpeg",
    png  = "image/png",
    gif  = "image/gif",
    webp = "image/webp",
    svg  = "image/svg+xml",
    bmp  = "image/bmp",
}
local SUPPORTED = {}
for _, m in pairs(MIME_BY_EXT) do SUPPORTED[m] = true end

local function decodeUrl(url)
    return (url:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
               :gsub("&quot;", '"'):gsub("&apos;", "'"))
end

-- Synchronous GET following up to three redirects, retrying transient
-- network errors twice.  Returns body, content_type or nil, err.
local function fetch(url)
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
            return table.concat(sink), headers and headers["content-type"] or ""
        end
        if attempt > MAX_RETRIES then return nil, tostring(code) end
        logger.dbg("QuickRSS: image retry", attempt, "for:", url, code)
    end
end

local function mimeType(url, content_type)
    local declared = (content_type or ""):match("^%s*([^;%s]+)")
    if declared and SUPPORTED[declared] then return declared end
    local ext = url:match("%.(%a%a%a?%a?)%?") or url:match("%.(%a%a%a?%a?)$")
    return ext and MIME_BY_EXT[ext:lower()]
end

local EXT_BY_MIME = {}
for ext, m in pairs(MIME_BY_EXT) do EXT_BY_MIME[m] = ext end
EXT_BY_MIME["image/jpeg"] = "jpg"

local Images = {}

function Images.download(url)
    url = decodeUrl(url)
    local data, content_type = fetch(url)
    if not data then
        logger.warn("QuickRSS: image download failed:", url, content_type)
        return nil
    end
    local mime_type = mimeType(url, content_type)
    if not mime_type then
        logger.warn("QuickRSS: unsupported image type:", url, content_type)
        return nil
    end
    return data, mime_type
end

function Images.dataUri(data, mime_type)
    return "data:" .. mime_type .. ";base64," .. mime.b64(data)
end

function Images.extension(mime_type)
    return EXT_BY_MIME[mime_type]
end

return Images
