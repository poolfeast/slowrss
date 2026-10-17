-- QuickRSS: Fetch orchestration
-- Keeps no index: the article files are the state.
--
--   * A file is named after the article's title and records the article's
--     link, so an article whose file exists is not fetched again.
--   * Only articles newer than the newest one already on disk are written, so
--     an older article you deleted does not come back.
--   * A file's modification time is the article's publish time, which orders
--     the folder by date and decides what the limit trims.
--   * After writing, each feed folder is trimmed to the newest
--     `items_per_feed` files.  Folders fill up to that limit over successive
--     fetches, because feeds only ever publish their latest items.
--
-- Public API:
--   Fetcher.run(progress) → stats { new, removed, errors, aborted }
--     progress(message) → false when the user aborted

local ArticleDoc = require("modules/data/article_doc")
local Config     = require("modules/data/config")
local Dates      = require("modules/data/dates")
local Parser     = require("modules/data/parser")
local Text       = require("modules/data/text")
local lfs        = require("libs/libkoreader-lfs")

local Fetcher = {}

-- Article files in a folder, newest first.
local function listArticles(dir)
    local files = {}
    if lfs.attributes(dir, "mode") ~= "directory" then return files end
    for name in lfs.dir(dir) do
        if name:match("%.html$") then
            local path = dir .. "/" .. name
            table.insert(files, { path = path, name = name, mtime = lfs.attributes(path, "modification") })
        end
    end
    table.sort(files, function(a, b) return a.mtime > b.mtime end)
    return files
end

-- Which of the feed's articles to write: matching the title filter, within
-- the limit, not on disk yet, and newer than the newest one that is.
local function selectNew(articles, feed, dir, limit)
    local candidates = {}
    local newest
    for _, art in ipairs(articles) do
        if #candidates >= limit then break end
        if Text.titleMatches(art.title, feed.include, feed.exclude) then
            local path, exists = ArticleDoc.locate(art, dir)
            local ts = Dates.parse(art.date)
            if exists then
                if ts and (not newest or ts > newest) then newest = ts end
            else
                art.source = feed.name
                table.insert(candidates, { article = art, path = path, ts = ts })
            end
        end
    end
    local todo = {}
    for _, c in ipairs(candidates) do
        if not (c.ts and newest and c.ts < newest) then table.insert(todo, c) end
    end
    return todo
end

function Fetcher.run(progress)
    local settings = Config.getSettings()
    local feeds    = Config.getFeeds()
    local stats    = { new = 0, removed = 0, errors = {}, aborted = false }

    for i, feed in ipairs(feeds) do
        if not progress(string.format("Fetching %s…\n(%d of %d)", feed.name, i, #feeds)) then
            stats.aborted = true
            return stats
        end
        local articles, err = Parser.fetchFeed(feed.url)
        if not articles then
            table.insert(stats.errors, feed.name .. ": " .. err)
        else
            local dir = ArticleDoc.feedDir(settings.articles_dir, feed)
            for _, item in ipairs(selectNew(articles, feed, dir, settings.items_per_feed)) do
                if not progress(string.format("Writing %s\n(%s)", item.article.title, feed.name)) then
                    stats.aborted = true
                    return stats
                end
                local ok, write_err = ArticleDoc.write(item.article, item.path, item.ts)
                if ok then
                    stats.new = stats.new + 1
                else
                    table.insert(stats.errors, item.article.title .. ": " .. tostring(write_err))
                end
            end
            local files = listArticles(dir)
            for k = settings.items_per_feed + 1, #files do
                ArticleDoc.remove(files[k].path)
                stats.removed = stats.removed + 1
            end
        end
    end
    return stats
end

return Fetcher
