--[[

	Minecart
	========

	Copyright (C) 2019-2020 Joachim Stolberg

	MIT
	See license.txt for more information
	
	Cart library base functions (level 3)
	
]]--

-- for lazy programmers
local M = minetest.get_meta
local S = minecart.S
local P2S = function(pos) if pos then return minetest.pos_to_string(pos) end end
local S2P = minetest.string_to_pos

local api = {}

local tRails = {
	["carts:rail"] = true,
	["carts:powerrail"] = true,
	["carts:brakerail"] = true,
}

local lRails = {"carts:rail", "carts:powerrail", "carts:brakerail"}

local function get_rail_node(pos)
	local node = minecart.get_node_lvm(pos)
	if tRails[node.name] then
		return node
	end
end

function api.find_rail_node(rail_pos)
	if not rail_pos then
		return
	end
	local node = get_rail_node(rail_pos)
	if node then
		return rail_pos, node
	end
	local pos1 = {x=rail_pos.x-1, y=rail_pos.y-1, z=rail_pos.z-1}
	local pos2 = {x=rail_pos.x+1, y=rail_pos.y+1, z=rail_pos.z+1}
	for _,pos3 in ipairs(minetest.find_nodes_in_area(pos1, pos2, lRails)) do
		return pos3, minecart.get_node_lvm(pos3)
	end
	pos1 = {x=rail_pos.x-3, y=rail_pos.y-3, z=rail_pos.z-3}
	pos2 = {x=rail_pos.x+3, y=rail_pos.y+3, z=rail_pos.z+3}
	for _,pos3 in ipairs(minetest.find_nodes_in_area(pos1, pos2, lRails)) do
		return pos3, minecart.get_node_lvm(pos3)
	end
end

function api.get_object_id(object)
	for id, entity in pairs(minetest.luaentities) do
		if entity.object == object then
			return id
		end
	end
end

function api.get_route_key(pos, player_name)
	local pos1 = minetest.find_node_near(pos, 1, {"minecart:buffer"})
	if pos1 then
		local meta = minetest.get_meta(pos1)
		if player_name == nil or player_name == meta:get_string("owner") then
			return P2S(pos1)
		end
	end
end

function api.get_station_name(pos)
	local pos1 = minetest.find_node_near(pos, 1, {"minecart:buffer"})
	if pos1 then
		local name = M(pos1):get_string("name")
		if name ~= "" then
			return name
		end
		return P2S(pos1)
	end
end

return api
