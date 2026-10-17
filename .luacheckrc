-- Same conventions as KOReader's own .luacheckrc
std = "luajit"
self = false
unused_args = false

globals = {
    "G_reader_settings",
    "G_defaults",
}


ignore = {
    "211/__*", -- Unused local variable
    "631",     -- Line is too long
}
