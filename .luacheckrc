-- Same conventions as KOReader's own .luacheckrc
std = "luajit"
self = false
unused_args = false

globals = {
    "G_reader_settings",
    "G_defaults",
}

exclude_files = {
    "quickrss.koplugin/modules/lib/xml.lua",
    "quickrss.koplugin/modules/lib/handler.lua",
}

ignore = {
    "211/__*", -- Unused local variable
    "631",     -- Line is too long
}
