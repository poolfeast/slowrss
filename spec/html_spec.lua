local H    = require("helpers")
local Html = require("modules/data/html")

local function embed(url)
    if url:find("missing") then return nil end
    return "data:image/png;base64,AAAA(" .. url .. ")"
end

local ARTICLE = {
    title     = "Tom & Jerry <3",
    link      = "https://blog.example/posts/2026/hello",
    source    = "Blog",
    author    = "Jane Doe",
    date      = "Mon, 02 Mar 2026 10:00:00 +0000",
    image_url = "https://cdn.example/lead-640x427.jpg",
    content   = table.concat({
        "<h2>Tom &amp; Jerry &lt;3</h2>",
        '<img src="https://cdn.example/lead-1152x648.jpg" width="1152">',
        '<p>See <a href="/about">about</a>, <a href="other">other</a>, <a href="#fn1">fn</a>, <a href="https://x.example/">x</a>.</p>',
        '<img src="//cdn.example/pic.png" style="width:900px">',
        '<img src="https://cdn.example/missing.jpg">',
        "<script>alert(1)</script>",
        '<p id="fn1">Note</p>',
    }, "\n"),
}

return {
    filename = function()
        local hash = require("modules/data/text").hash("l")
        H.eq(Html.filename(ARTICLE), "Tom & Jerry <3.html")
        H.eq(Html.filename(ARTICLE, true), "Tom & Jerry <3 (2026-03-02).html")
        H.eq(Html.filename({ title = " Spaced   title ", link = "l", date = "" }), "Spaced title.html")
        H.eq(Html.filename({ title = "Undated", link = "l", date = "" }, true), "Undated (" .. hash .. ").html")
        H.eq(Html.filename({ title = "", link = "l", date = "" }), hash .. ".html")
    end,
    absolutize_url = function()
        local base = "https://blog.example/posts/2026/hello"
        H.eq(Html.absolutizeUrl("/about", base), "https://blog.example/about")
        H.eq(Html.absolutizeUrl("other", base), "https://blog.example/posts/2026/other")
        H.eq(Html.absolutizeUrl("//cdn.example/p.png", base), "https://cdn.example/p.png")
        H.eq(Html.absolutizeUrl("?p=1", base), "https://blog.example/posts/2026/hello?p=1")
        H.eq(Html.absolutizeUrl("#fn1", base), "#fn1")
        H.eq(Html.absolutizeUrl("mailto:a@b.c", base), "mailto:a@b.c")
        H.eq(Html.absolutizeUrl("https://x.example/", base), "https://x.example/")
        H.eq(Html.absolutizeUrl("/x", "not a url"), "/x")
    end,
    document_with_images = function()
        local html = Html.document(ARTICLE, { images = true, embed = embed })
        H.contains(html, "<head>\n" .. Html.canonical(ARTICLE.link), "canonical link first in head")
        H.contains(html, '<link rel="canonical" href="https://blog.example/posts/2026/hello"/>')
        H.contains(html, "<title>Tom &amp; Jerry &lt;3</title>")
        H.contains(html, "<h1>Tom &amp; Jerry &lt;3</h1>")
        H.lacks(html, "<h2>", "duplicate heading removed")
        H.contains(html, 'class="meta">Blog &#183; Jane Doe &#183; 02 Mar 2026<')
        H.contains(html, '<div class="banner"><img src="data:image/png;base64,AAAA(https://cdn.example/lead-640x427.jpg)"/></div>')
        H.lacks(html, "lead-1152x648", "lead image variant removed from body")
        H.contains(html, '<img src="data:image/png;base64,AAAA(https://cdn.example/pic.png)" style="width:900px">', "attributes kept")
        H.lacks(html, "missing.jpg", "unavailable image dropped")
        H.lacks(html, "<script")
        H.contains(html, 'href="https://blog.example/about"')
        H.contains(html, 'href="https://blog.example/posts/2026/other"')
        H.contains(html, 'href="#fn1"')
        H.contains(html, 'href="https://x.example/"')
    end,
    document_without_images = function()
        local html = Html.document(ARTICLE, { images = false, embed = function() error("must not fetch") end })
        H.lacks(html, "<img")
        H.lacks(html, '<div class="banner"')
        H.contains(html, "<h1>")
    end,
}
