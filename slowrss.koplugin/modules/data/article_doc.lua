-- SlowRSS: Article files
-- Each article is a self-contained HTML file in
--   <articles folder>/<OPML folder>/<feed name>/<title>.html
--
-- Public API:
--   ArticleDoc.feedDir(root, feed)        → directory for a feed's articles
--   ArticleDoc.locate(article, dir)       → path, exists: where the article's file is or goes
--   ArticleDoc.write(article, path, ts, progress)
--                                         → true, or nil, err; mtime set to ts when given.
--                                           Also writes the cover and metadata sidecar.
--                                           progress(line) is called after each image download
--                                           and returns false when the user aborts; err is then "aborted".

local Config      = require("modules/data/config")
local DocSettings = require("docsettings")
local Html        = require("modules/data/html")
local Images      = require("modules/data/images")
local lfs         = require("libs/libkoreader-lfs")
local util        = require("util")

local ArticleDoc = {}

local function safeName(name, dir)
    return util.getSafeFilename(name, dir, 100)
end

function ArticleDoc.feedDir(root, feed)
    local dir = root
    for segment in feed.folder:gmatch("[^/]+") do
        dir = dir .. "/" .. safeName(segment, root)
    end
    return dir .. "/" .. safeName(feed.name, root)
end

-- nil when there is no file at path, otherwise whether it holds this article
local function holds(path, article)
    local f = io.open(path, "rb")
    if not f then return nil end
    local head = f:read(4096) or ""
    f:close()
    return head:find(Html.canonical(article.link), 1, true) ~= nil
end

-- The title alone when it is free or already this article's; otherwise the
-- disambiguated name.
function ArticleDoc.locate(article, dir)
    local path = dir .. "/" .. safeName(Html.filename(article), dir)
    local found = holds(path, article)
    if found == nil or found then return path, found == true end
    path = dir .. "/" .. safeName(Html.filename(article, true), dir)
    return path, holds(path, article) ~= nil
end

-- KOReader reads only the <title> of an HTML file, so the rest of the
-- metadata and the cover go where "Book information" edits would put them:
-- the document's sidecar (.sdr) folder, which the file browser hides and
-- which is deleted along with the document.
local function writeSidecar(article, path, cover, cover_mime)
    local props = {
        authors     = article.author ~= "" and article.author or article.source,
        series      = article.source,
        keywords    = table.concat(article.categories, "\n"),
        description = article.summary,
        language    = article.language,
    }
    for key, value in pairs(props) do
        if value == "" then props[key] = nil end
    end
    local custom = DocSettings.openSettingsFile()
    custom:saveSetting("doc_props", { title = article.title })
    custom:saveSetting("custom_props", props)
    custom:flushCustomMetadata(path)
    if cover then
        local tmp = path .. ".cover." .. Images.extension(cover_mime)
        local f = io.open(tmp, "wb")
        f:write(cover)
        f:close()
        DocSettings:flushCustomCover(path, tmp)
        os.remove(tmp)
    end
end

function ArticleDoc.write(article, path, ts, progress)
    local images = Config.getSettings().article_images_enabled
    -- First pass: find the images the article will embed.  The progress
    -- message pauses this coroutine, which Lua cannot do inside the HTML
    -- builder's gsub callbacks, so downloads happen between the two passes.
    local urls, seen = {}, {}
    Html.document(article, {
        images = images,
        embed  = function(url)
            if not seen[url] then
                seen[url] = true
                table.insert(urls, url)
            end
            return "" -- stand-in so the first pass makes the same choices as the second
        end,
    })
    local downloads = {}
    for i, url in ipairs(urls) do
        local data, mime_type = Images.download(url)
        downloads[url] = { data = data, mime = mime_type }
        if not progress(string.format("Image %d of %d (%s)", i, #urls,
                data and util.getFriendlySize(#data) or "not downloaded")) then
            return nil, "aborted"
        end
    end
    local html = Html.document(article, {
        images = images,
        embed  = function(url)
            local d = downloads[url]
            return d and d.data and Images.dataUri(d.data, d.mime)
        end,
    })
    local dir = path:match("^(.*)/")
    if not util.makePath(dir) then
        return nil, "could not create " .. dir
    end
    local tmp = path .. ".tmp"
    local f, err = io.open(tmp, "wb")
    if not f then return nil, err end
    f:write(html)
    f:close()
    local ok, rename_err = os.rename(tmp, path)
    if not ok then
        os.remove(tmp)
        return nil, rename_err
    end
    if ts then lfs.touch(path, ts, ts) end
    local lead = images and article.image_url and downloads[article.image_url]
    writeSidecar(article, path, lead and lead.data, lead and lead.mime)
    return true
end


return ArticleDoc
