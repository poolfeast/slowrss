local H      = require("helpers")
local Filter = require("modules/data/filter")

return {
    title_filter = function()
        H.eq(Filter.matches("NASA launches rocket", "", ""), true, "no filter")
        H.eq(Filter.matches("NASA launches rocket", "space | nasa", ""), true, "include, case-insensitive")
        H.eq(Filter.matches("Weekly deals", "space|nasa", ""), false, "include miss")
        H.eq(Filter.matches("Sponsored: NASA merch", "nasa", "sponsored|deals"), false, "exclude wins")
        H.eq(Filter.matches("C++ (and Lua%)", "c++|lua%", ""), true, "keywords are plain text")
        H.eq(Filter.matches(nil, "", "x"), true, "missing title")
    end,
}
