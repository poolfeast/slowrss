-- Runs inside a live KOReader through the HTTP inspector:
--   GET /koreader/globals/dofile/"<repo>/spec/menu_check.lua"
-- Builds every SlowRSS menu and evaluates each label and checkbox function,
-- which is where a menu error would otherwise surface only on the device.
local FileManager = require("apps/filemanager/filemanager")
local plugin = FileManager.instance.slowrss
local labels = {}
local function visit(items, depth)
    for _, item in ipairs(items) do
        if item.text_func then table.insert(labels, item.text_func()) end
        if item.checked_func then item.checked_func() end
        if item.sub_item_table_func and depth < 3 then visit(item.sub_item_table_func(), depth + 1) end
        if item.sub_item_table then visit(item.sub_item_table, depth + 1) end
    end
end
local menu_items = {}
plugin:addToMainMenu(menu_items)
visit(menu_items.slowrss.sub_item_table, 0)
return table.concat(labels, " | ")
