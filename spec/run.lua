-- Unit tests for the plugin's data modules.  They use KOReader's own
-- libraries, so run from KOReader's install directory:
--   cd <koreader>/lib/koreader && ./luajit <repo>/spec/run.lua
-- (nix flake check does this.)
local root = arg[0]:match("^(.*)/spec/run%.lua$")
require("setupkoenv")
package.path = root .. "/slowrss.koplugin/?.lua;" .. root .. "/spec/?.lua;" .. package.path
require("logger"):setLevel(require("logger").levels.err)

local specs = { "filter_spec", "dates_spec", "html_spec", "opml_spec", "parser_spec", "substack_spec" }

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
