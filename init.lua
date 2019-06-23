minecart = {}


minecart.S = minetest.get_translator("minecart")
local MP = minetest.get_modpath("minecart")
dofile(MP.."/storage.lua")
dofile(MP.."/routes.lua")
dofile(MP.."/cart_entity.lua")
dofile(MP.."/buffer.lua")
dofile(MP.."/protection.lua")
dofile(MP.."/doc.lua")
minetest.log("info", "[MOD] Minecart loaded")
