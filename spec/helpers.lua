local H = {}

function H.eq(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label or "value",
            tostring(expected), tostring(actual)), 2)
    end
end

function H.truthy(value, label)
    if not value then error((label or "value") .. " is falsy", 2) end
end

function H.contains(haystack, needle, label)
    if not haystack:find(needle, 1, true) then
        error(string.format("%s: %q not found in:\n%s", label or "text", needle, haystack), 2)
    end
end

function H.lacks(haystack, needle, label)
    if haystack:find(needle, 1, true) then
        error(string.format("%s: %q unexpectedly found in:\n%s", label or "text", needle, haystack), 2)
    end
end

function H.links(list)
    local out = {}
    for i, art in ipairs(list) do out[i] = art.link end
    return table.concat(out, ",")
end

return H
