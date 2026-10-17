-- Minimal test runner for the pure modules: luajit spec/run.lua
-- Each spec file returns a table of { name = function } tests.
local root = arg[0]:match("^(.*)/spec/run%.lua$") or "."
package.path = root .. "/quickrss.koplugin/?.lua;" .. root .. "/spec/?.lua;" .. package.path

-- The parser logs through KOReader's logger; silence it.
package.preload["logger"] = function()
    local noop = function() end
    return { info = noop, warn = noop, dbg = noop, err = noop }
end

local specs = { "text_spec", "dates_spec", "html_spec", "opml_spec", "parser_spec" }

local failures, total = 0, 0
for _, spec in ipairs(specs) do
    for name, test in pairs(require(spec)) do
        total = total + 1
        local ok, err = xpcall(test, debug.traceback)
        if not ok then
            failures = failures + 1
            io.stderr:write(string.format("FAIL %s: %s\n%s\n", spec, name, err))
        end
    end
end
print(string.format("%d tests, %d failures", total, failures))
os.exit(failures == 0 and 0 or 1)
