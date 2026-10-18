local H    = require("helpers")
local OPML = require("modules/data/opml")

local NESTED = [[<?xml version="1.0"?>
<opml version="2.0"><head><title>x</title></head><body>
  <outline text="Top" type="rss" xmlUrl="https://top.example/feed"/>
  <outline text="Tech" title="Tech">
    <outline title="Ars &amp; Co" type="rss" xmlUrl="https://ars.example/rss?a=1&amp;b=2" htmlUrl="https://ars.example" slowrssInclude="space|nasa" slowrssExclude="deals" slowrssLimit="40"/>
    <outline text="Deep">
      <outline text="Nested" type="rss" xmlUrl="https://deep.example/feed" />
    </outline>
  </outline>
  <outline text="Empty folder"></outline>
</body></opml>]]

return {
    parse_nested_folders = function()
        local feeds = OPML.parse(NESTED)
        H.eq(#feeds, 3)
        H.eq(feeds[1].name, "Top");        H.eq(feeds[1].folder, "")
        H.eq(feeds[2].name, "Ars & Co");   H.eq(feeds[2].folder, "Tech")
        H.eq(feeds[2].url, "https://ars.example/rss?a=1&b=2")
        H.eq(feeds[2].include, "space|nasa");  H.eq(feeds[2].exclude, "deals")
        H.eq(feeds[1].include, "");            H.eq(feeds[1].exclude, "")
        H.eq(feeds[2].limit, 40);              H.eq(feeds[1].limit, nil)
        H.eq(feeds[3].name, "Nested");     H.eq(feeds[3].folder, "Tech/Deep")
    end,
    round_trip = function()
        local feeds = OPML.parse(NESTED)
        table.insert(feeds, { name = 'Quote "d"', url = "https://q.example/", folder = "Tech" })
        local again = OPML.parse(OPML.serialize(feeds))
        H.eq(#again, 4)
        -- Serialising groups feeds by folder, so compare by URL rather than position
        local by_url = {}
        for _, feed in ipairs(again) do by_url[feed.url] = feed end
        for _, feed in ipairs(feeds) do
            H.truthy(by_url[feed.url], "feed kept: " .. feed.url)
            H.eq(by_url[feed.url].name, feed.name, "name of " .. feed.url)
            H.eq(by_url[feed.url].folder, feed.folder, "folder of " .. feed.url)
        end
    end,
    serialize_structure = function()
        local xml = OPML.serialize({
            { name = "A", url = "https://a/", folder = "", include = "x", exclude = "" },
            { name = "B", url = "https://b/", folder = "F/G", include = "", exclude = "" },
        })
        H.contains(xml, '    <outline text="A" title="A" type="rss" xmlUrl="https://a/" slowrssInclude="x"/>')
        H.contains(xml, '    <outline text="F" title="F">\n      <outline text="G" title="G">\n        <outline text="B" title="B" type="rss" xmlUrl="https://b/"/>\n      </outline>\n    </outline>')
    end,
}
