-- QuickRSS: plugin entry point
-- Adds Tools → QuickRSS.  Fetching turns every configured feed into
-- self-contained HTML files under the articles folder, one sub-folder per
-- OPML folder and feed, which are read like any other document.

local Config           = require("modules/data/config")
local ConfirmBox       = require("ui/widget/confirmbox")
local FileManager      = require("apps/filemanager/filemanager")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr       = require("ui/network/manager")
local PathChooser      = require("ui/widget/pathchooser")
local SpinWidget       = require("ui/widget/spinwidget")
local Trapper          = require("ui/trapper")
local UIManager        = require("ui/uimanager")
local WidgetContainer  = require("ui/widget/container/widgetcontainer")
local logger           = require("logger")
local util             = require("util")
local T                = require("ffi/util").template
local _                = require("gettext")

local QuickRSS = WidgetContainer:extend{
    name = "quickrss",
    is_doc_only = false,
}

function QuickRSS:init()
    self.ui.menu:registerToMainMenu(self)
end

function QuickRSS:addToMainMenu(menu_items)
    menu_items.quickrss = {
        text = _("QuickRSS"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Fetch articles"),
                callback = function() self:fetch() end,
            },
            {
                text = _("Go to articles folder"),
                callback = function() self:openArticlesFolder() end,
                separator = true,
            },
            {
                text = _("Feeds"),
                sub_item_table_func = function() return self:feedItems() end,
            },
            {
                text = _("Settings"),
                sub_item_table = self:settingsItems(),
            },
        },
    }
end

-- ── Feeds ────────────────────────────────────────────────────────────────────

local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

-- " Tech / News/ " → "Tech/News"
local function normaliseFolder(s)
    local segments = {}
    for segment in s:gmatch("[^/]+") do
        segment = trim(segment)
        if segment ~= "" then table.insert(segments, segment) end
    end
    return table.concat(segments, "/")
end

function QuickRSS:feedItems()
    local items = {
        {
            text = _("Add feed"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self:editFeed(nil, touchmenu_instance)
            end,
            separator = true,
        },
    }
    for i, feed in ipairs(Config.getFeeds()) do
        table.insert(items, {
            text = feed.folder ~= "" and (feed.folder .. " › " .. feed.name) or feed.name,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self:editFeed(i, touchmenu_instance)
            end,
        })
    end
    return items
end

-- Add (index = nil) or edit the feed at index; the OPML file is rewritten on
-- save or delete.
function QuickRSS:editFeed(index, touchmenu_instance)
    local feeds = Config.getFeeds()
    local feed = feeds[index] or { name = "", url = "", folder = "", include = "", exclude = "" }
    local function done()
        Config.saveFeeds(feeds)
        touchmenu_instance.item_table = self:feedItems()
        touchmenu_instance:updateItems()
    end
    local dialog
    local buttons = {
        {
            text = _("Cancel"),
            id = "close",
            callback = function() UIManager:close(dialog) end,
        },
        {
            text = _("Save"),
            is_enter_default = true,
            callback = function()
                local f = dialog:getFields()
                local edited = {
                    name    = trim(f[1]),
                    url     = trim(f[2]),
                    folder  = normaliseFolder(f[3]),
                    include = trim(f[4]),
                    exclude = trim(f[5]),
                }
                if edited.name == "" or edited.url == "" then return end
                UIManager:close(dialog)
                feeds[index or #feeds + 1] = edited
                done()
            end,
        },
    }
    if index then
        table.insert(buttons, 1, {
            text = _("Delete"),
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = T(_("Remove feed %1?\nIts articles stay on disk."), feed.name),
                    ok_text = _("Remove"),
                    ok_callback = function()
                        UIManager:close(dialog)
                        table.remove(feeds, index)
                        done()
                    end,
                })
            end,
        })
    end
    dialog = MultiInputDialog:new{
        title = index and _("Edit feed") or _("Add feed"),
        fields = {
            { description = _("Name"), text = feed.name, hint = "Ars Technica" },
            { description = _("URL"), text = feed.url, hint = "https://feeds.example.com/rss" },
            { description = _("Folder (optional)"), text = feed.folder, hint = "Tech/News" },
            { description = _("Only titles containing (optional)"), text = feed.include, hint = "space|nasa" },
            { description = _("Skip titles containing (optional)"), text = feed.exclude, hint = "deals|sponsored" },
        },
        buttons = { buttons },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- ── Settings ─────────────────────────────────────────────────────────────────

local function updateSetting(key, value)
    local s = Config.getSettings()
    s[key] = value
    Config.saveSettings(s)
end

function QuickRSS:settingsItems()
    return {
        {
            text_func = function()
                return T(_("Articles per feed: %1"), Config.getSettings().items_per_feed)
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                UIManager:show(SpinWidget:new{
                    title_text = _("Articles per feed"),
                    info_text = _("How many articles to keep in each feed's folder. Feeds only publish their latest items, so the folder fills up to this number over successive fetches; older files are deleted beyond it."),
                    value = Config.getSettings().items_per_feed,
                    value_min = 1,
                    value_max = 500,
                    value_step = 5,
                    value_hold_step = 25,
                    default_value = 20,
                    callback = function(spin)
                        updateSetting("items_per_feed", spin.value)
                        touchmenu_instance:updateItems()
                    end,
                })
            end,
        },
        {
            text = _("Embed images"),
            checked_func = function() return Config.getSettings().article_images_enabled end,
            callback = function()
                updateSetting("article_images_enabled", not Config.getSettings().article_images_enabled)
            end,
        },
        {
            text_func = function()
                return T(_("Articles folder: %1"), Config.getSettings().articles_dir)
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                UIManager:show(PathChooser:new{
                    select_file = false,
                    show_files = false,
                    path = Config.getSettings().articles_dir,
                    onConfirm = function(path)
                        updateSetting("articles_dir", path)
                        touchmenu_instance:updateItems()
                    end,
                })
            end,
        },
    }
end

-- ── Fetch ────────────────────────────────────────────────────────────────────

function QuickRSS:fetch()
    NetworkMgr:runWhenOnline(function()
        Trapper:wrap(function() self:_runFetch() end)
    end)
end

-- Runs inside Trapper:wrap, so Trapper:info() shows progress and lets the
-- user abort by tapping the message.
function QuickRSS:_runFetch()
    local result = require("modules/data/fetcher").run(function(message)
        return Trapper:info(message)
    end)
    Trapper:reset()
    logger.info("QuickRSS: fetch finished:", result.new, "new,", result.removed, "removed,", #result.errors, "errors")
    if FileManager.instance then
        FileManager.instance:onRefresh()
    end

    local lines = {}
    if result.aborted then
        table.insert(lines, _("Fetch aborted."))
    end
    table.insert(lines, T(_("%1 new, %2 removed."), result.new, result.removed))
    if #result.errors > 0 then
        table.insert(lines, T(_("%1 problem(s):"), #result.errors) .. "\n" .. table.concat(result.errors, "\n"))
    end
    UIManager:show(ConfirmBox:new{
        text = table.concat(lines, "\n"),
        ok_text = _("Open folder"),
        ok_callback = function() self:openArticlesFolder() end,
        cancel_text = _("Close"),
    })
end

function QuickRSS:openArticlesFolder()
    local dir = Config.getSettings().articles_dir
    util.makePath(dir)
    if self.ui.document then
        self.ui:onClose()
    end
    if FileManager.instance then
        FileManager.instance:reinit(dir)
    else
        FileManager:showFiles(dir)
    end
end

return QuickRSS
