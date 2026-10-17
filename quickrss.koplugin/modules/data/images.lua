-- QuickRSS: Images
-- Images are embedded exactly as published.  Only formats the reader can
-- render are kept, recognised by their first bytes rather than by what the
-- server claims; anything else (AVIF, HEIC, an HTML error page…) is dropped.
--
-- Public API:
--   Images.download(url)       → data, mime_type, or nil
--   Images.dataUri(data, mime) → "data:<mime>;base64,…" for embedding in an article
--   Images.extension(mime)     → file extension for the cover file

local Http   = require("modules/data/http")
local logger = require("logger")
local mime   = require("mime")
local util   = require("util")

local function sniff(data)
    if data:sub(1, 3) == "\255\216\255" then return "image/jpeg" end
    if data:sub(1, 8) == "\137PNG\r\n\26\n" then return "image/png" end
    if data:sub(1, 4) == "GIF8" then return "image/gif" end
    if data:sub(1, 4) == "RIFF" and data:sub(9, 12) == "WEBP" then return "image/webp" end
    if data:sub(1, 2) == "BM" then return "image/bmp" end
    if data:sub(1, 512):find("<svg", 1, true) then return "image/svg+xml" end
end

local Images = {}

function Images.download(url)
    url = util.htmlEntitiesToUtf8(url)
    local data, err = Http.get(url)
    if not data then
        logger.warn("QuickRSS: image download failed:", url, err)
        return nil
    end
    local mime_type = sniff(data)
    if not mime_type then
        logger.warn("QuickRSS: image format not supported:", url)
        return nil
    end
    return data, mime_type
end

function Images.dataUri(data, mime_type)
    return "data:" .. mime_type .. ";base64," .. mime.b64(data)
end

function Images.extension(mime_type)
    return ({ ["image/jpeg"] = "jpg", ["image/svg+xml"] = "svg" })[mime_type] or mime_type:match("/(%w+)")
end

return Images
