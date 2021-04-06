--[[

	Minecart
	========

	Copyright (C) 2019-2021 Joachim Stolberg

	MIT
	See license.txt for more information
	
]]--

-- for lazy programmers
local M = minetest.get_meta
local S = minecart.S
local P2S = function(pos) if pos then return minetest.pos_to_string(pos) end end
local S2P = minetest.string_to_pos
local P2H = minetest.hash_node_position

local function DOTS(dots) 
	if dots then
		return table.concat(dots, ", ")
	else
		return ""
	end
end

local function test_get_route(pos, node, player, ctrl)
	local yaw = player:get_look_horizontal()
	local dir = minetest.yaw_to_dir(yaw)
	local facedir = minetest.dir_to_facedir(dir)
	local route = minecart.get_waypoint(pos, facedir, ctrl)
	if route then
--		print(dump(route))
		print("test_get_route", string.format("dist = %u, dot = %u, power = %d", 
				vector.distance(pos, route.pos), route.dot, route.power))
		minecart.set_marker(route.pos, "pos")
	end
end

local function click_left(itemstack, placer, pointed_thing)
	if pointed_thing.type == "node" then
		local pos = pointed_thing.under
		local node = minetest.get_node(pos)
		if node.name == "carts:rail" or node.name == "carts:powerrail" then
			test_get_route(pos, node, placer, {left = false})
		end
	end
end

local function click_right(itemstack, placer, pointed_thing)
	if pointed_thing.type == "node" then
		local pos = pointed_thing.under
		local node = minetest.get_node(pos)
		if node.name == "carts:rail" or node.name == "carts:powerrail" then
			test_get_route(pos, node, placer, {right = false})
		elseif node.name == "minecart:buffer" then
			local route = minecart.get_route(P2S(pos))
			print(dump(route))
		end
	end
end

minetest.register_node("minecart:tool", {
	description = "Tool",
	inventory_image = "minecart_tool.png",
	wield_image = "minecart_tool.png",
	liquids_pointable = true,
	use_texture_alpha = true,
	groups = {cracky=1, book=1},
	on_use = click_left,
	on_place = click_right,
	node_placement_prediction = "",
	stack_max = 1,
})
