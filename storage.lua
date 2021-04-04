--[[

	Minecart
	========

	Copyright (C) 2019-2021 Joachim Stolberg

	MIT
	See license.txt for more information
	
]]--

-- for lazy programmers
local M = minetest.get_meta
local P2S = function(pos) if pos then return minetest.pos_to_string(pos) end end
local S2P = minetest.string_to_pos
local P2H = minetest.hash_node_position
local S = minecart.S

local storage = minetest.get_mod_storage()

-------------------------------------------------------------------------------
-- Store data of running carts
-------------------------------------------------------------------------------
minecart.CartsOnRail = {}

--minetest.register_on_mods_loaded(function()
--	local version = storage:get_int("version")
--	if version < 2 then
--		minecart.CartsOnRail = convert_to_v2()
--		storage:set_int("version", 2)
--	else
--		minecart.CartsOnRail = minetest.deserialize(storage:get_string("CartsOnRail")) or {}
--	end
--end)

--minetest.register_on_shutdown(function()
--	storage:set_string("CartsOnRail", minetest.serialize(minecart.CartsOnRail))
--end)

--function minecart.store_carts()
--	storage:set_string("CartsOnRail", minetest.serialize(minecart.CartsOnRail))
--end

-------------------------------------------------------------------------------
-- Store routes (in buffers)
-------------------------------------------------------------------------------
function minecart.store_route(pos, route)
	if pos and route then
		M(pos):set_string("route", minetest.serialize(route))
		return true
	end
	return false
end

function minecart.get_route(pos)
	if pos then
		local s = M(pos):get_string("route")
		if s ~= "" then
			local route = minetest.deserialize(s)
			if route.waypoints then
				M(pos):set_string("route", "")
				return
			end
			return minetest.deserialize(s)
		end
	end
end

function minecart.del_route(pos)
	M(pos):set_string("route", "")
end
