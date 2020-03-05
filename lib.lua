--[[

	Minecart
	========

	Copyright (C) 2019-2020 Joachim Stolberg

	MIT
	See license.txt for more information
	
]]--

-- for lazy programmers
local M = minetest.get_meta
local P2S = function(pos) if pos then return minetest.pos_to_string(pos) end end
local S2P = minetest.string_to_pos
local S = minecart.S

local RegisteredInventories = {}

local param2_to_dir = {[0]=
	{x=0,  y=0,  z=1},
	{x=1,  y=0,  z=0},
	{x=0,  y=0, z=-1},
	{x=-1, y=0,  z=0},
	{x=0,  y=-1, z=0},
	{x=0,  y=1,  z=0}
}

local function is_air_like(name)
	local ndef = minetest.registered_nodes[name]
	if ndef and ndef.buildable_to then
		return true
	end
	return false
end

function minecart.get_next_node(pos, param2)
	local pos2 = vector.add(pos, param2_to_dir[param2])
	local node = minetest.get_node(pos2)
	return pos2, node
end

function minecart.check_cart(pos, param2)	
	if param2 then
		pos = minecart.get_next_node(pos, param2)
	end
	for _, object in pairs(minetest.get_objects_inside_radius(pos, 0.5)) do
		if object:get_entity_name() == "minecart:cart" then
			local vel = object:get_velocity()
			if vector.equals(vel, {x=0, y=0, z=0}) then  -- still standing?
				return true
			end
		end
	end
	return false
end

local get_next_node = minecart.get_next_node
local check_cart = minecart.check_cart

-- Take the given number of items from the inv.
-- Returns nil if ItemList is empty.
function minecart.inv_take_items(inv, listname, num)
	if inv:is_empty(listname) then
		return nil
	end
	local size = inv:get_size(listname)
	for idx = 1, size do
		local items = inv:get_stack(listname, idx)
		if items:get_count() > 0 then
			local taken = items:take_item(num)
			inv:set_stack(listname, idx, items)
			return taken
		end
	end
	return nil
end

function minecart.take_items(pos, param2, num)
	local npos, node
	if param2 then
		npos, node = get_next_node(pos, (param2 + 2) % 4)
	else
		npos, node = pos, minetest.get_node(pos)
	end
	local def = RegisteredInventories[node.name]
	local owner = M(pos):get_string("owner")
	local inv = minetest.get_inventory({type="node", pos=npos})
	
	if def and inv and (not def.allow_take or def.allow_take(npos, nil, owner)) then
		return minecart.inv_take_items(inv, def.take_listname, num)
	else
		local ndef = minetest.registered_nodes[node.name]
		if ndef and ndef.minecart_hopper_takeitem then
			return ndef.minecart_hopper_takeitem(npos, num)
		end
	end
end

function minecart.put_items(pos, param2, stack)
	local npos, node = get_next_node(pos, param2)
	local def = RegisteredInventories[node.name]
	local owner = M(pos):get_string("owner")
	local inv = minetest.get_inventory({type="node", pos=npos})
	
	if def and inv and (not def.allow_put or def.allow_put(npos, stack, owner)) then
		local leftover = inv:add_item(def.put_listname, stack)
		if leftover:get_count() > 0 then
			return leftover
		end
	elseif is_air_like(node.name) or check_cart(npos) then
		minetest.add_item(npos, stack)
	else
		local ndef = minetest.registered_nodes[node.name]
		if ndef and ndef.minecart_hopper_additem then
			local leftover = ndef.minecart_hopper_additem(npos, stack)
			if leftover:get_count() > 0 then
				return leftover
			end
		else
			return stack
		end
	end
end

function minecart.untake_items(pos, param2, stack)
	local npos, node
	if param2 then
		npos, node = get_next_node(pos, (param2 + 2) % 4)
	else
		npos, node = pos, minetest.get_node(pos)
	end
	local def = RegisteredInventories[node.name]
	local inv = minetest.get_inventory({type="node", pos=npos})
	
	if def then
		return inv and inv:add_item(def.put_listname, stack)
	else
		local ndef = minetest.registered_nodes[node.name]
		if ndef and ndef.minecart_hopper_untakeitem then
			return ndef.minecart_hopper_untakeitem(npos, stack)
		end
	end
end

function minecart.punch_cart(pos, param2)
	local pos2 = minecart.get_next_node(pos, param2)
	for _, object in pairs(minetest.get_objects_inside_radius(pos2, 0.5)) do
		if object:get_entity_name() == "minecart:cart" then
			object:punch(object, 1.0, {
				full_punch_interval = 1.0,
				damage_groups = {fleshy = 1},
			}, minetest.facedir_to_dir(0))
			break -- start only one cart
		end
	end
end	

-- Register inventory node for hopper access
-- (for examples, see below)
function minecart.register_inventory(node_names, def)
	for _, name in ipairs(node_names) do
		RegisteredInventories[name] = {
			allow_put = def.put and def.put.allow_inventory_put,
			put_listname = def.put and def.put.listname,
			allow_take = def.take and def.take.allow_inventory_take,
			take_listname = def.take and def.take.listname,
		}
	end
end

minecart.register_inventory({"default:chest", "default:chest_open"}, {
	put = {
		listname = "main",
	},
	take = {
		listname = "main",
	},
})

minecart.register_inventory({"default:chest_locked", "default:chest_locked_open"}, {
	put = {
		allow_inventory_put = function(pos, stack, player_name)
			local owner = M(pos):get_string("owner")
			return owner == player_name
		end, 
		listname = "main",
	},
	take = {
		allow_inventory_take = function(pos, stack, player_name)
			local owner = M(pos):get_string("owner")
			return owner == player_name
		end, 
		listname = "main",
	},
})

minecart.register_inventory({"minecart:hopper"}, {
	put = {
		allow_inventory_put = function(pos, stack, player_name)
			local owner = M(pos):get_string("owner")
			return owner == player_name
		end, 
		listname = "main",
	},
	take = {
		allow_inventory_take = function(pos, stack, player_name)
			local owner = M(pos):get_string("owner")
			return owner == player_name
		end, 
		listname = "main",
	},
})
