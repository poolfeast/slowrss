local H     = require("helpers")
local Dates = require("modules/data/dates")

return {
    parse = function()
        H.truthy(Dates.parse("Mon, 01 Mar 2026 12:00:00 +0000"))
        H.truthy(Dates.parse("2026-03-01T12:00:00Z"))
        H.truthy(Dates.parse("2026-03-01"))
        H.eq(Dates.parse("yesterday"), nil)
        H.eq(Dates.parse(""), nil)
        H.truthy(Dates.parse("2026-03-02T00:00:00Z") > Dates.parse("Sun, 01 Mar 2026 23:00:00 +0000"))
    end,
    iso = function()
        H.eq(Dates.iso("Mon, 01 Mar 2026 12:00:00 +0000"), "2026-03-01")
        H.eq(Dates.iso("Tue, 9 Sep 2025 08:00:00 GMT"), "2025-09-09")
        H.eq(Dates.iso("2026-03-01T12:00:00+02:00"), "2026-03-01")
        H.eq(Dates.iso("nope"), nil)
    end,
    display = function()
        H.eq(Dates.display("Mon, 01 Mar 2026 12:00:00 +0000"), "01 Mar 2026")
        H.eq(Dates.display("2026-03-01T12:00:00Z"), "01 Mar 2026", "same form as RSS dates")
        H.eq(Dates.display("2025-04-21T10:00:00.000Z"), "21 Apr 2025")
        H.eq(Dates.display("odd"), "odd")
        H.eq(Dates.display(""), nil)
    end,
}
