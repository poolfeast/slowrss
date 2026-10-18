-- SlowRSS: Fetch orchestration
-- Keeps no index: the article files are the state.  Nothing here ever
-- deletes an article; that is left to the user.
--
--   * Each fetch looks at the feed's newest `limit` articles that pass the
--     title filter (the feed's own limit, else the default setting).
--   * A file is named after the article's title and records the article's
--     link, so an article whose file exists is not fetched again.
--   * A folder only grows at its ends: articles newer than the newest on
--     disk, or older than the oldest (Substack's archive reaches further back
--     than its feed).  An article deleted from the middle does not come back.
--   * A file's modification time is the article's publish time, so sorting
--     by date orders a folder by publication.
--
-- Public API:
--   Fetcher.run(progress) → stats { new, errors, aborted }
--     progress(message) → false when the user aborted

local ArticleDoc = require("modules/data/article_doc")
local Config     = require("modules/data/config")
local Dates      = require("modules/data/dates")
local Filter     = require("modules/data/filter")
local Parser     = require("modules/data/parser")
local Substack   = require("modules/data/substack")

local Fetcher = {}

-- Which of the feed's articles to write: the newest `limit` that match the
-- title filter, minus those on disk and those that would fill a gap between
-- articles already on disk.
local function selectNew(articles, feed, dir, limit)
    local candidates = {}
    local newest, oldest
    local considered = 0
    for _, art in ipairs(articles) do
        if considered >= limit then break end
        if Filter.matches(art.title, feed.include, feed.exclude) then
            considered = considered + 1
            local path, exists = ArticleDoc.locate(art, dir)
            local ts = Dates.parse(art.date)
            if exists then
                if ts then
                    if not newest or ts > newest then newest = ts end
                    if not oldest or ts < oldest then oldest = ts end
                end
            else
                art.source = feed.name
                table.insert(candidates, { article = art, path = path, ts = ts })
            end
        end
    end
    local todo = {}
    for _, c in ipairs(candidates) do
        local fills_gap = c.ts and newest and c.ts < newest and c.ts > oldest
        if not fills_gap then table.insert(todo, c) end
    end
    return todo
end

function Fetcher.run(progress)
    local settings = Config.getSettings()
    local feeds    = Config.getFeeds()
    local stats    = { new = 0, errors = {}, aborted = false }

    for i, feed in ipairs(feeds) do
        local heading = string.format("Fetching %s…\n(%d of %d)", feed.name, i, #feeds)
        if not progress(heading) then
            stats.aborted = true
            return stats
        end
        local articles, err = Parser.fetchFeed(feed.url)
        if not articles then
            table.insert(stats.errors, feed.name .. ": " .. err)
        else
            local dir = ArticleDoc.feedDir(settings.articles_dir, feed)
            local limit = feed.limit or settings.items_per_feed
            local older, aborted = Substack.olderArticles(feed, articles, limit, function(line)
                return progress(heading .. "\n\n" .. line)
            end)
            if aborted then
                stats.aborted = true
                return stats
            end
            for _, art in ipairs(older) do table.insert(articles, art) end
            for _, item in ipairs(selectNew(articles, feed, dir, limit)) do
                heading = string.format("%s\n(%s)", item.article.title, feed.name)
                if not progress(heading) then
                    stats.aborted = true
                    return stats
                end
                local ok, write_err = true, nil
                if item.article.body_url then
                    ok, write_err = Substack.fetchBody(item.article)
                end
                if ok then
                    ok, write_err = ArticleDoc.write(item.article, item.path, item.ts, function(line)
                        return progress(heading .. "\n\n" .. line)
                    end)
                end
                if write_err == "aborted" then
                    stats.aborted = true
                    return stats
                end
                if ok then
                    stats.new = stats.new + 1
                else
                    table.insert(stats.errors, item.article.title .. ": " .. tostring(write_err))
                end
            end
        end
    end
    return stats
end

return Fetcher
