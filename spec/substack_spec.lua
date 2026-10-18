local H    = require("helpers")
local JSON = require("json")

-- Stand-in HTTP layer: canned responses by URL, and a log of requests
local Fake = { responses = {}, requests = {} }
function Fake.get(url)
    table.insert(Fake.requests, url)
    return Fake.responses[url]
end
package.loaded["modules/data/http"] = Fake
package.loaded["modules/data/substack"] = nil
local Substack = require("modules/data/substack")

local BASE = "https://pub.example"
local FEED = { name = "Pub", url = BASE .. "/feed", include = "", exclude = "" }

local function post(n, extra)
    local p = {
        title = "Post " .. n, slug = "post-" .. n, canonical_url = BASE .. "/p/post-" .. n,
        post_date = string.format("2026-01-%02dT10:00:00.000Z", n), cover_image = "https://cdn.example/" .. n .. ".jpg",
        description = "About " .. n, publishedBylines = { { name = "Ann Author" } }, postTags = { { name = "Tag" .. n } },
    }
    for k, v in pairs(extra or {}) do p[k] = v end
    return p
end

local function archive(offset, posts)
    Fake.responses[string.format("%s/api/v1/archive?sort=new&offset=%d&limit=50", BASE, offset)] = JSON.encode(posts)
end

local function reset()
    Fake.responses, Fake.requests = {}, {}
end

local always = function() return true end

return {
    pages_until_limit_skipping_feed_posts = function()
        reset()
        -- The feed already has posts 30 and 29; the archive's first page is short, as Substack's is
        local rss = { { title = "Post 30", link = BASE .. "/p/post-30", language = "en" }, { title = "Post 29", link = BASE .. "/p/post-29", language = "en" } }
        local page1 = {}
        for n = 30, 28, -1 do table.insert(page1, post(n)) end
        local page2 = {}
        for n = 27, 1, -1 do table.insert(page2, post(n)) end
        archive(0, page1); archive(3, page2)
        local older, aborted = Substack.olderArticles(FEED, rss, 5, always)
        H.eq(aborted, false)
        H.eq(#older, 3, "5 wanted, 2 from the feed")
        H.eq(H.links(older), BASE .. "/p/post-28," .. BASE .. "/p/post-27," .. BASE .. "/p/post-26")
        local a = older[1]
        H.eq(a.title, "Post 28");                       H.eq(a.date, "2026-01-28T10:00:00.000Z")
        H.eq(a.image_url, "https://cdn.example/28.jpg"); H.eq(a.author, "Ann Author")
        H.eq(a.categories[1], "Tag28");                   H.eq(a.summary, "About 28")
        H.eq(a.language, "en", "language taken from the feed")
        H.eq(a.content, "");                              H.eq(a.body_url, BASE .. "/api/v1/posts/post-28")
        H.eq(#Fake.requests, 2, "two archive pages, no bodies")
    end,
    filter_decides_what_counts = function()
        reset()
        archive(0, { post(3, { title = "Sponsored: buy" }), post(2), post(1) })
        archive(3, {})
        local older = Substack.olderArticles({ name = "Pub", url = BASE .. "/feed", include = "", exclude = "sponsored" }, {}, 2, always)
        H.eq(H.links(older), BASE .. "/p/post-2," .. BASE .. "/p/post-1")
    end,
    stops_when_the_archive_runs_out = function()
        reset()
        archive(0, { post(2), post(1) }); archive(2, {})
        local older = Substack.olderArticles(FEED, {}, 10, always)
        H.eq(#older, 2)
    end,
    not_substack = function()
        reset()
        Fake.responses[BASE .. "/api/v1/archive?sort=new&offset=0&limit=50"] = "<html>not json</html>"
        local older, aborted = Substack.olderArticles(FEED, {}, 10, always)
        H.eq(#older, 0); H.eq(aborted, false)
        reset() -- no response at all (404)
        H.eq(#Substack.olderArticles(FEED, {}, 10, always), 0)
    end,
    nothing_needed_means_no_request = function()
        reset()
        local rss = { { title = "A", link = BASE .. "/p/a" }, { title = "B", link = BASE .. "/p/b" } }
        Substack.olderArticles(FEED, rss, 2, always)
        H.eq(#Fake.requests, 0)
    end,
    abort_while_listing = function()
        reset()
        archive(0, { post(1) })
        local older, aborted = Substack.olderArticles(FEED, {}, 10, function() return false end)
        H.eq(aborted, true); H.eq(#older, 0)
    end,
    fetch_body = function()
        reset()
        local art = { body_url = BASE .. "/api/v1/posts/post-1" }
        Fake.responses[art.body_url] = JSON.encode({ body_html = "<p>Hello</p>", cover_image = JSON.util.null })
        H.eq(Substack.fetchBody(art), true); H.eq(art.content, "<p>Hello</p>")
        local bad = { body_url = BASE .. "/api/v1/posts/missing" }
        local ok, err = Substack.fetchBody(bad)
        H.eq(ok, nil); H.truthy(err)
    end,
}
