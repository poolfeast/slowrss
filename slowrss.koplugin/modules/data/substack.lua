-- SlowRSS: Substack back-catalogue
-- A Substack RSS feed stops at the latest 20 posts.  Substack's JSON API
-- pages back through every post, and the bodies it returns are the same HTML
-- the feed carries, so older posts go through the same pipeline as feed
-- items and come out identical.  Works for custom domains too: any host that
-- answers the archive API is treated as Substack.
--
-- Public API:
--   Substack.olderArticles(feed, articles, limit, progress) → older, aborted
--     Lists posts not already in `articles` (newest first) until `limit`
--     posts in total pass the feed's title filter.  Bodies are not fetched
--     here: each article has body_url and content "" until fetchBody().
--     Returns {} for feeds that are not on Substack.
--   Substack.fetchBody(article) → true, or nil, err; fills article.content

local Filter = require("modules/data/filter")
local Http   = require("modules/data/http")
local JSON   = require("json")

local PAGE = 50

local Substack = {}

local function getJson(url)
    local body = Http.get(url)
    if not body then return nil end
    local ok, data = pcall(JSON.decode, body, JSON.decode.simple)
    if ok and type(data) == "table" then return data end
end

local function toArticle(post, base, language)
    local tags = {}
    for _, tag in ipairs(post.postTags or {}) do
        if tag.name then table.insert(tags, tag.name) end
    end
    local byline = post.publishedBylines and post.publishedBylines[1]
    return {
        title      = post.title or "",
        link       = post.canonical_url,
        date       = post.post_date or "",
        content    = "",
        body_url   = base .. "/api/v1/posts/" .. post.slug,
        image_url  = post.cover_image,
        author     = byline and byline.name or "",
        categories = tags,
        summary    = post.description or "",
        language   = language,
    }
end

function Substack.olderArticles(feed, articles, limit, progress)
    local url  = feed.url:match("^https?://") and feed.url or ("https://" .. feed.url)
    local base = url:match("^(https?://[^/]+)")
    local have, count = {}, 0
    for _, art in ipairs(articles) do
        have[art.link] = true
        if Filter.matches(art.title, feed.include, feed.exclude) then count = count + 1 end
    end
    local language = articles[1] and articles[1].language or ""
    local older  = {}
    local offset = 0
    while count < limit do
        if not progress(string.format("Listing older posts… (%d found)", #older)) then
            return older, true
        end
        local posts = getJson(string.format("%s/api/v1/archive?sort=new&offset=%d&limit=%d", base, offset, PAGE))
        if not posts or #posts == 0 then break end -- not Substack, or no more posts
        for _, post in ipairs(posts) do
            if count >= limit then break end
            if post.slug and post.canonical_url and not have[post.canonical_url] then
                have[post.canonical_url] = true
                if Filter.matches(post.title, feed.include, feed.exclude) then
                    count = count + 1
                    table.insert(older, toArticle(post, base, language))
                end
            end
        end
        offset = offset + #posts
    end
    return older, false
end

function Substack.fetchBody(article)
    local post = getJson(article.body_url)
    if not post or type(post.body_html) ~= "string" then
        return nil, "could not fetch the post body"
    end
    article.content = post.body_html
    return true
end

return Substack
