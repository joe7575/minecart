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

local param2_to_dir = {[0]=
	{x=0,  y=0,  z=1},
	{x=1,  y=0,  z=0},
	{x=0,  y=0, z=-1},
	{x=-1, y=0,  z=0},
	{x=0,  y=-1, z=0},
	{x=0,  y=1,  z=0}
}

-- Registered carts
minecart.tEntityNames = {} -- [<cart_node_name>] =  <cart_entity_name>
minecart.lCartNodeNames = {}

function minecart.param2_to_dir(param2)
	return param2_to_dir[param2 % 6]
end

function minecart.get_node_lvm(pos)
	local node = minetest.get_node_or_nil(pos)
	if node then
		return node
	end
	local vm = minetest.get_voxel_manip()
	local MinEdge, MaxEdge = vm:read_from_map(pos, pos)
	local data = vm:get_data()
	local param2_data = vm:get_param2_data()
	local area = VoxelArea:new({MinEdge = MinEdge, MaxEdge = MaxEdge})
	local idx = area:indexp(pos)
	if data[idx] and param2_data[idx] then
		return {
			name = minetest.get_name_from_content_id(data[idx]),
			param2 = param2_data[idx]
		}
	end
	return {name="ignore", param2=0}
end

function minecart.is_air_like(name)
	local ndef = minetest.registered_nodes[name]
	if ndef and ndef.buildable_to then
		return true
	end
	return false
end

function minecart.range(val, min, max)
	val = tonumber(val)
	if val < min then return min end
	if val > max then return max end
	return val
end

function minecart.get_next_node(pos, param2)
	local pos2 = param2 and vector.add(pos, param2_to_dir[param2]) or pos
	local node = minetest.get_node(pos2)
	return pos2, node
end

function minecart.get_object_id(object)
	for id, entity in pairs(minetest.luaentities) do
		if entity.object == object then
			return id
		end
	end
end

function minecart.is_owner(player, owner)
	if not player or not player:is_player() or not owner or owner == "" then
		return true
	end
	local name = player:get_player_name()
	if minetest.check_player_privs(name, "minecart") then
		return true
	end
	return name == owner
end

function minecart.get_route_key(pos, player_name)
	local pos1 = minetest.find_node_near(pos, 1, {"minecart:buffer"})
	if pos1 then
		local meta = minetest.get_meta(pos1)
		if player_name == nil or player_name == meta:get_string("owner") then
			return P2S(pos1)
		end
	end
end

function minecart.get_station_name(pos)
	local pos1 = minetest.find_node_near(pos, 1, {"minecart:buffer"})
	if pos1 then
		local name = M(pos1):get_string("name")
		if name ~= "" then
			return name
		end
		return P2S(pos1)
	end
end

function minecart.register_cart_names(node_name, entity_name)
	minecart.tEntityNames[node_name] = entity_name
	minecart.lCartNodeNames[#minecart.lCartNodeNames+1] = node_name
end

function minecart.node_to_entity(pos, node_name, entity_name)
	-- Remove node
	local meta = M(pos)
	local ndef = minetest.registered_nodes[node_name]
	local rail = meta:get_string("removed_rail")
	if rail == "" then rail = "carts:rail" end
	local userID = meta:get_int("userID")
	local owner = meta:get_string("owner")
	local cargo = ndef.get_cargo and ndef.get_cargo(pos) or {}
	minetest.swap_node(pos, {name = rail})
	
	-- Add entity
	local obj = minetest.add_entity(pos, entity_name)
	local objID = minecart.get_object_id(obj)
	
	if objID then
		local entity = obj:get_luaentity()
		entity.owner = owner
		entity.userID = userID
		entity.objID = objID
		entity.cargo = cargo
		obj:set_nametag_attributes({color = "#ffff00", text = owner..": "..userID})
		
		minecart.update_cart_status(owner, userID, false, objID, pos, node_name, entity_name, cargo)
		return objID, obj
	else
		print("Entity has no ID")
	end
end

function minecart.entity_to_node(pos, entity, node_name, param2)
	-- Stop sound
	if entity.sound_handle then
		minetest.sound_stop(entity.sound_handle)
		entity.sound_handle = nil
	end
	
	-- Remove entity
	local owner = entity.owner or ""
	local userID = entity.userID or 0
	local cargo = entity.cargo or {}
	local entity_name = entity.name
	entity.object:remove()
	
	-- Add node
	local ndef = minetest.registered_nodes[node_name]
	local node = minetest.get_node(pos)
	local rail = node.name
	minetest.add_node(pos, {name = node_name, param2 = param2})
	local meta = M(pos)
	meta:set_string("removed_rail", rail)
	meta:set_string("owner", owner)
	meta:set_string("userID", userID)
	meta:set_string("infotext", minetest.get_color_escape_sequence("#FFFF00")..owner..": "..userID)
	if ndef.after_place_node then
		ndef.after_place_node(pos)
	end
	if cargo and ndef.set_cargo then
		ndef.set_cargo(pos, cargo)
	end

	minecart.update_cart_status(owner, userID, true, nil, pos, node_name, entity_name, cargo)
end

function minecart.add_node_to_player_inventory(pos, player, node_name)
	local inv = player:get_inventory()
	if not (creative and creative.is_enabled_for
			and creative.is_enabled_for(player:get_player_name()))
			or not inv:contains_item("main", node_name) then
		local leftover = inv:add_item("main", node_name)
		-- If no room in inventory, drop the cart
		if not leftover:is_empty() then
			minetest.add_item(pos, leftover)
		end
	end
end

-- Player removes the node
function minecart.remove_entity(self, pos, player)
	-- Stop sound
	if self.sound_handle then
		minetest.sound_stop(self.sound_handle)
		self.sound_handle = nil
	end
	minecart.add_node_to_player_inventory(pos, player, self.node_name or "minecart:cart")
	minecart.update_cart_status(self.owner, self.userID)
	self.object:remove()
end

