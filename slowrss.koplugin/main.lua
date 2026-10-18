-- SlowRSS: plugin entry point
-- Adds Tools → SlowRSS.  Fetching turns every configured feed into
-- self-contained HTML files under the articles folder, one sub-folder per
-- OPML folder and feed, which are read like any other document.

local Blitbuffer       = require("ffi/blitbuffer")
local Config           = require("modules/data/config")
local ConfirmBox       = require("ui/widget/confirmbox")
local Device           = require("device")
local InputDialog      = require("ui/widget/inputdialog")
local FileManager      = require("apps/filemanager/filemanager")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr       = require("ui/network/manager")
local PathChooser      = require("ui/widget/pathchooser")
local ProgressWidget   = require("ui/widget/progresswidget")
local Size             = require("ui/size")
local SpinWidget       = require("ui/widget/spinwidget")
local Trapper          = require("ui/trapper")
local UIManager        = require("ui/uimanager")
local WidgetContainer  = require("ui/widget/container/widgetcontainer")
local logger           = require("logger")
local util             = require("util")
local T                = require("ffi/util").template
local _                = require("gettext")

local Screen = Device.screen

local SlowRSS = WidgetContainer:extend{
    name = "slowrss",
    is_doc_only = false,
}

function SlowRSS:init()
    self.ui.menu:registerToMainMenu(self)
end

function SlowRSS:addToMainMenu(menu_items)
    menu_items.slowrss = {
        text = _("SlowRSS"),
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
-- Each feed is a submenu whose entries are edited one at a time, so every
-- dialog is a single line that fits above the on-screen keyboard.

-- " Tech / News/ " → "Tech/News"
local function normaliseFolder(s)
    local segments = {}
    for segment in s:gmatch("[^/]+") do
        segment = util.trim(segment)
        if segment ~= "" then table.insert(segments, segment) end
    end
    return table.concat(segments, "/")
end

local function editText(title, value, hint, callback)
    local dialog
    dialog = InputDialog:new{
        title = title,
        input = value,
        input_hint = hint,
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function() UIManager:close(dialog) end,
            },
            {
                text = _("Save"),
                is_enter_default = true,
                callback = function()
                    local text = util.trim(dialog:getInputText())
                    UIManager:close(dialog)
                    callback(text)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

local FIELDS = {
    { key = "name",    label = _("Name"),                   required = true },
    { key = "url",     label = _("URL"),                    required = true, hint = "https://feeds.example.com/rss" },
    { key = "folder",  label = _("Folder"),                 hint = "Tech/News" },
    { key = "include", label = _("Only titles containing"), hint = "space|nasa" },
    { key = "exclude", label = _("Skip titles containing"), hint = "deals|sponsored" },
}

local function feedLabel(feed)
    return feed.folder ~= "" and (feed.folder .. " › " .. feed.name) or feed.name
end

local function updateFeed(index, key, value)
    local feeds = Config.getFeeds()
    feeds[index][key] = value
    Config.saveFeeds(feeds)
end

function SlowRSS:feedItems()
    local items = {
        {
            text = _("Add feed"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self:addFeed(touchmenu_instance)
            end,
            separator = true,
        },
    }
    for i in ipairs(Config.getFeeds()) do
        table.insert(items, {
            text_func = function() return feedLabel(Config.getFeeds()[i]) end,
            sub_item_table_func = function() return self:feedSettingsItems(i) end,
        })
    end
    return items
end

function SlowRSS:addFeed(touchmenu_instance)
    local dialog
    dialog = MultiInputDialog:new{
        title = _("Add feed"),
        fields = {
            { hint = _("Name") },
            { hint = _("URL") },
        },
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function() UIManager:close(dialog) end,
            },
            {
                text = _("Add"),
                is_enter_default = true,
                callback = function()
                    local f = dialog:getFields()
                    local name, url = util.trim(f[1]), util.trim(f[2])
                    if name == "" or url == "" then return end
                    UIManager:close(dialog)
                    local feeds = Config.getFeeds()
                    table.insert(feeds, { name = name, url = url, folder = "", include = "", exclude = "" })
                    Config.saveFeeds(feeds)
                    touchmenu_instance.item_table = self:feedItems()
                    touchmenu_instance:updateItems()
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function SlowRSS:feedSettingsItems(index)
    local function feed() return Config.getFeeds()[index] end
    local items = {}
    for __, field in ipairs(FIELDS) do
        table.insert(items, {
            text_func = function()
                local value = feed()[field.key]
                return T(_("%1: %2"), field.label, value ~= "" and value or _("none"))
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                editText(field.label, feed()[field.key], field.hint, function(value)
                    if field.key == "folder" then value = normaliseFolder(value) end
                    if field.required and value == "" then return end
                    updateFeed(index, field.key, value)
                    touchmenu_instance:updateItems()
                end)
            end,
        })
    end
    table.insert(items, {
        text_func = function()
            return T(_("Articles to fetch: %1"), feed().limit or Config.getSettings().items_per_feed)
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            UIManager:show(SpinWidget:new{
                title_text = _("Articles to fetch"),
                info_text = _("How many of this feed's newest articles each fetch downloads. Articles already downloaded stay until you delete them."),
                value = feed().limit or Config.getSettings().items_per_feed,
                value_min = 1,
                value_max = 500,
                value_step = 5,
                value_hold_step = 25,
                default_value = Config.getSettings().items_per_feed,
                callback = function(spin)
                    updateFeed(index, "limit", spin.value)
                    touchmenu_instance:updateItems()
                end,
            })
        end,
        separator = true,
    })
    table.insert(items, {
        text = _("Delete feed"),
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            UIManager:show(ConfirmBox:new{
                text = T(_("Remove feed %1?\nIts articles stay on disk."), feed().name),
                ok_text = _("Remove"),
                ok_callback = function()
                    local feeds = Config.getFeeds()
                    table.remove(feeds, index)
                    Config.saveFeeds(feeds)
                    touchmenu_instance:backToUpperMenu()
                    touchmenu_instance.item_table = self:feedItems()
                    touchmenu_instance:updateItems()
                end,
            })
        end,
    })
    return items
end

-- ── Settings ─────────────────────────────────────────────────────────────────

local function updateSetting(key, value)
    local s = Config.getSettings()
    s[key] = value
    Config.saveSettings(s)
end

function SlowRSS:settingsItems()
    return {
        {
            text_func = function()
                return T(_("Default articles to fetch: %1"), Config.getSettings().items_per_feed)
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                UIManager:show(SpinWidget:new{
                    title_text = _("Default articles to fetch"),
                    info_text = _("How many of a feed's newest articles each fetch downloads, for feeds without their own number. Articles already downloaded stay until you delete them."),
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

function SlowRSS:fetch()
    NetworkMgr:runWhenOnline(function()
        Trapper:wrap(function() self:_runFetch() end)
    end)
end

-- Runs inside Trapper:wrap, so Trapper:info() shows progress and lets the
-- user abort by tapping the message.  Overall progress is the same thin bar
-- the reader shows while a document loads, painted straight to the screen
-- because UIManager does not get to run during the fetch.
function SlowRSS:_runFetch()
    local bar = ProgressWidget:new{
        width = math.floor(Screen:getWidth() / 3),
        height = Size.line.progress,
        fillcolor = Blitbuffer.COLOR_BLACK,
        percentage = 0,
        margin_h = 0,
        margin_v = 0,
        radius = 0,
    }
    local result = require("modules/data/fetcher").run(function(message, fraction)
        local go_on = Trapper:info(message)
        if fraction then
            bar:setPercentage(fraction)
            bar:paintTo(Screen.bb, 0, Size.margin.small)
            Screen:refreshFast(0, Size.margin.small, bar.width, bar.height)
        end
        return go_on
    end)
    Trapper:reset()
    logger.info("SlowRSS: fetch finished:", result.new, "new,", #result.errors, "errors")
    if FileManager.instance then
        FileManager.instance:onRefresh()
    end

    local lines = {}
    if result.aborted then
        table.insert(lines, _("Fetch aborted."))
    end
    table.insert(lines, T(_("%1 new articles."), result.new))
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

function SlowRSS:openArticlesFolder()
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

return SlowRSS
