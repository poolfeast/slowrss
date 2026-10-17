local H    = require("helpers")
local Text = require("modules/data/text")

return {
    hash_is_stable_hex = function()
        H.eq(Text.hash("https://example.com/a"), Text.hash("https://example.com/a"))
        H.truthy(Text.hash("x"):match("^%x%x%x%x%x%x%x%x$"))
        H.truthy(Text.hash("a") ~= Text.hash("b"))
    end,
    title_filter = function()
        H.eq(Text.titleMatches("NASA launches rocket", "", ""), true, "no filter")
        H.eq(Text.titleMatches("NASA launches rocket", "space | nasa", ""), true, "include, case-insensitive")
        H.eq(Text.titleMatches("Weekly deals", "space|nasa", ""), false, "include miss")
        H.eq(Text.titleMatches("Sponsored: NASA merch", "nasa", "sponsored|deals"), false, "exclude wins")
        H.eq(Text.titleMatches("C++ (and Lua%)", "c++|lua%", ""), true, "keywords are plain text")
        H.eq(Text.titleMatches(nil, "", "x"), true, "missing title")
    end,
    escape_html = function()
        H.eq(Text.escapeHtml([[<a href="x">'&']]), "&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;")
    end,
    sanitize = function()
        local html = Text.sanitizeHtml([[<p onclick="x()">Hi</p><script>evil()</script><a href="javascript:bad()">l</a><style>p{}</style>]])
        H.lacks(html, "<script")
        H.lacks(html, "onclick")
        H.lacks(html, "javascript:")
        H.lacks(html, "<style")
        H.contains(html, "<p>Hi</p>")
    end,
}
