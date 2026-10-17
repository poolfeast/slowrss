-- QuickRSS: Article files
-- Each article is a self-contained HTML file in
--   <articles folder>/<OPML folder>/<feed name>/<title>.html
--
-- Public API:
--   ArticleDoc.feedDir(root, feed)        → directory for a feed's articles
--   ArticleDoc.locate(article, dir)       → path, exists: where the article's file is or goes
--   ArticleDoc.write(article, path, ts)   → true, or nil, err; mtime set to ts when given.
--                                           Also writes the cover and metadata sidecar.
--   ArticleDoc.remove(path)               deletes the file with its sidecar and history entry

local Config      = require("modules/data/config")
local DocSettings = require("docsettings")
local Html        = require("modules/data/html")
local Images      = require("modules/data/images")
local lfs         = require("libs/libkoreader-lfs")
local logger      = require("logger")
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

function ArticleDoc.write(article, path, ts)
    local images = Config.getSettings().article_images_enabled
    -- The lead image is both embedded and used as the cover; download it once.
    local downloads = {}
    local function download(url)
        if not downloads[url] then downloads[url] = { Images.download(url) } end
        return downloads[url][1], downloads[url][2]
    end
    local html = Html.document(article, {
        images = images,
        embed  = function(url)
            local data, mime_type = download(url)
            return data and Images.dataUri(data, mime_type)
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
    local cover, cover_mime
    if images and article.image_url then
        cover, cover_mime = download(article.image_url)
    end
    writeSidecar(article, path, cover, cover_mime)
    return true
end

-- Deleting through FileManager also removes the document's .sdr folder
-- (reading position, highlights, status) and its history entry, exactly as
-- deleting it in the file browser does.
function ArticleDoc.remove(path)
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI.instance and ReaderUI.instance.document.file == path then
        logger.info("QuickRSS: not removing the article currently open:", path)
        return
    end
    require("apps/filemanager/filemanager"):deleteFile(path, true)
end

return ArticleDoc
