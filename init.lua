minecart = {}

local MP = minetest.get_modpath("minecart")
dofile(MP.."/storage.lua")
dofile(MP.."/routes.lua")
dofile(MP.."/cart_entity.lua")
dofile(MP.."/buffer.lua")

minetest.log("info", "[MOD] Minecart loaded")
