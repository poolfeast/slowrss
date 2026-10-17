local H      = require("helpers")
-- RSS with HTML-escaped content and a comment, as many generators emit
local ESCAPED = [==[<?xml version="1.0"?>
<!-- generator comment -->
<rss version="2.0"><channel><title>T</title>
<item><title>It&amp;#8217;s here</title><link>https://e.example/1</link>
<description>&lt;p&gt;Body &amp;amp; more&lt;/p&gt;&lt;img src="https://e.example/a.jpg"&gt;</description>
<enclosure url="https://e.example/cover.jpg" type="image/jpeg" length="1"/></item>
</channel></rss>]==]
local Parser = require("modules/data/parser")

local RSS = [==[<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:dc="http://purl.org/dc/elements/1.1/">
<channel>
  <title>Example Blog</title>
  <language>en-gb</language>
  <item>
    <title>Bridges &amp; Tunnels</title>
    <link>https://blog.example/bridges</link>
    <pubDate>Mon, 02 Mar 2026 10:00:00 +0000</pubDate>
    <dc:creator><![CDATA[Jane Doe]]></dc:creator>
    <category>Infrastructure</category>
    <category><![CDATA[Civil engineering]]></category>
    <description><![CDATA[<p>A short <b>summary</b> &amp; more.</p>]]></description>
    <content:encoded><![CDATA[<p>Full body</p><img src="https://img.example/a.jpg"/>]]></content:encoded>
  </item>
  <item>
    <title>Summary only</title>
    <link>https://blog.example/short</link>
    <author>jane@blog.example (Jane D.)</author>
    <category>One</category>
    <description>Just this</description>
  </item>
</channel>
</rss>]==]

local ATOM = [==[<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xml:lang="de">
  <title>Atom Example</title>
  <entry>
    <title>Hallo</title>
    <link rel="alternate" href="https://atom.example/hallo"/>
    <published>2026-03-01T12:00:00Z</published>
    <author><name>Max Muster</name></author>
    <category term="Technik"/>
    <category term="Politik"/>
    <summary>Kurz</summary>
    <content type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml"><p>Lang &amp; breit</p><img src="https://img.example/x.png"/></div></content>
  </entry>
</feed>]==]

return {
    rss_metadata = function()
        local articles = assert(Parser.parse(RSS))
        local a, b = articles[1], articles[2]
        H.eq(a.title, "Bridges & Tunnels")
        H.eq(a.link, "https://blog.example/bridges")
        H.eq(a.date, "Mon, 02 Mar 2026 10:00:00 +0000")
        H.eq(a.author, "Jane Doe")
        H.eq(table.concat(a.categories, ","), "Infrastructure,Civil engineering")
        H.eq(a.summary, "A short summary & more.")
        H.eq(a.language, "en-gb")
        H.eq(a.image_url, "https://img.example/a.jpg")
        H.contains(a.content, "Full body")
        H.eq(b.author, "Jane D.", "RSS author email form")
        H.eq(table.concat(b.categories, ","), "One", "single category")
        H.eq(b.summary, "", "description is the content when there is no content:encoded")
        H.eq(b.content, "Just this")
    end,
    escaped_rss = function()
        local a = assert(Parser.parse(ESCAPED))[1]
        H.eq(a.title, "It\u{2019}s here", "double-escaped entity in title")
        H.eq(a.content, '<p>Body &amp; more</p><img src="https://e.example/a.jpg">')
        H.eq(a.image_url, "https://e.example/cover.jpg", "enclosure preferred")
    end,
    not_a_feed = function()
        H.eq(Parser.parse("<html><body>nope</body></html>"), nil)
    end,
    atom_metadata = function()
        local a = assert(Parser.parse(ATOM))[1]
        H.eq(a.link, "https://atom.example/hallo")
        H.eq(a.author, "Max Muster")
        H.eq(table.concat(a.categories, ","), "Technik,Politik")
        H.eq(a.summary, "Kurz")
        H.eq(a.language, "de")
        H.contains(a.content, "<p>Lang &amp; breit</p>", "inline XHTML kept as markup")
        H.eq(a.image_url, "https://img.example/x.png")
    end,
}
