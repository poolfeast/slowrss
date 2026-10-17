-- QuickRSS: Config Module
-- Persists the feed list and settings under <koreader data dir>/quickrss/.
--
-- The feed list is a standard OPML file (feeds.opml) so it can be edited on a
-- computer or imported from another RSS reader.  Everything else lives in
-- settings.lua.
--
-- Public API:
--   Config.getFeeds()            → { { name, url, folder, include, exclude }, … }
--   Config.saveFeeds(feeds)
--   Config.getSettings()         → { items_per_feed, article_images_enabled, articles_dir }
--   Config.saveSettings(s)

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local OPML        = require("modules/data/opml")
local util        = require("util")

local BASE_DIR = DataStorage:getFullDataDir() .. "/quickrss"
util.makePath(BASE_DIR)
local OPML_FILE = BASE_DIR .. "/feeds.opml"

local DEFAULTS = {
    items_per_feed         = 20,   -- articles kept in each feed's folder
    article_images_enabled = true, -- embed images in articles
    articles_dir           = BASE_DIR .. "/articles",
}

local settings = LuaSettings:open(BASE_DIR .. "/settings.lua")

local Config = {}

function Config.getFeeds()
    return OPML.read(OPML_FILE) or {}
end

function Config.saveFeeds(feeds)
    OPML.write(OPML_FILE, feeds)
end

-- Merged with defaults so new keys always have a value after an upgrade.
-- Explicit nil-check because `false or default` would discard a saved false.
function Config.getSettings()
    local saved = settings:readSetting("article_settings") or {}
    local s = {}
    for key, default in pairs(DEFAULTS) do
        if saved[key] ~= nil then s[key] = saved[key] else s[key] = default end
    end
    return s
end

function Config.saveSettings(s)
    settings:saveSetting("article_settings", s):flush()
end

return Config
