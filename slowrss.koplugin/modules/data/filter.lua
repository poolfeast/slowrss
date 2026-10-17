-- SlowRSS: Title filter
--
-- Public API:
--   Filter.matches(title, include, exclude) → whether a title passes a feed's filter
--     include / exclude are "|"-separated keywords matched case-insensitively
--     anywhere in the title.  An empty include list lets everything through.

local Filter = {}

local function hasKeyword(title, list)
    for keyword in list:gmatch("[^|]+") do
        keyword = keyword:match("^%s*(.-)%s*$"):lower()
        if keyword ~= "" and title:find(keyword, 1, true) then return true end
    end
    return false
end

function Filter.matches(title, include, exclude)
    title = (title or ""):lower()
    if include ~= "" and not hasKeyword(title, include) then return false end
    return not hasKeyword(title, exclude)
end

return Filter
