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
local H2P = minetest.get_position_from_hash
local S = minecart.S

local tCartsOnRail = {}
local Queue = {}
local first = 0
local last = -1

local function push(cycle, item)
	last = last + 1
	item.cycle = cycle
	Queue[last] = item
end

local function pop(cycle)
	if first > last then return end
	local item = Queue[first]
	if item.cycle < cycle then
		Queue[first] = nil -- to allow garbage collection
		first = first + 1
		return item
	end
end

local function back_to_start(cart)
	--minecart.add_nodecart(cart.start_pos, cart.node_name, 0, cart.cargo, cart.owner, cart.userID)
	--minecart.stop_monitoring(cart.owner, cart.userID, )
end

local function is_player_nearby(pos)
	for _, object in pairs(minetest.get_objects_inside_radius(pos, 30)) do
		if object:is_player() then
			return true
		end
	end
end

local function zombie_to_entity(pos, cart, checkpoint)
	local vel = {x = 0, y = 0, z = 0}
	local obj = minecart.add_entitycart(pos, cart.node_name, cart.entity_name, 
				vel, cart.cargo, cart.owner, cart.userID)
	local entity = obj:get_luaentity()
	entity.reenter = checkpoint
	entity.is_running = true
	entity.arrival_time = 0
	cart.objID = entity.objID
end


local function monitoring(cycle)
    local cart = pop(cycle)
	
    while cart and cart.objID and cart.objID > 0 do
		cart.idx = cart.idx + 1
		local entity = minetest.luaentities[cart.objID]
		if entity then  -- cart entity running
			cart.last_pos = vector.round(entity.object:get_pos())
			print("monitoring", cycle, cart.userID, P2S(cart.last_pos), cart.checkpoints ~= nil)
			push(cycle, cart)
		elseif cart.checkpoints then
			local cp = cart.checkpoints[cart.idx]
			if cp then
				local pos = H2P(cp[1])
				print("zombie at", P2S(pos))
				if is_player_nearby(pos) then
					zombie_to_entity(pos, cart, cp)
				end
				push(cycle, cart)
			else
				print("zombie got lost")
			end
		else
			local pos = cart.last_pos or cart.pos
			minecart.add_nodecart(pos, cart.node_name, 0, cart.cargo, cart.owner, cart.userID)
			print("cart to node", cycle, cart.userID, P2S(pos))
		end
        cart = pop(cycle)
	end
	if cart and not cart.objID and tCartsOnRail[cart.owner] then
		tCartsOnRail[cart.owner][cart.userID] = nil
	end
	minetest.after(2, monitoring, cycle + 1)
end

minetest.after(2, monitoring, 1)


function minecart.monitoring_add_cart(owner, userID, pos, node_name, entity_name, cargo)
	print("monitoring_add_cart", owner, userID)
	tCartsOnRail[owner] = tCartsOnRail[owner] or {}
	tCartsOnRail[owner][userID] = {
		owner = owner,
		userID = userID,
		objID = 0,
		pos = pos,
		idx = 0,
		node_name = node_name,
		entity_name = entity_name,
		cargo = cargo,
	}
end
	
function minecart.start_monitoring(owner, userID, pos, objID, checkpoints)
	print("start_monitoring", owner, userID)
	if tCartsOnRail[owner] and tCartsOnRail[owner][userID] then
		tCartsOnRail[owner][userID].pos = pos
		tCartsOnRail[owner][userID].objID = objID
		tCartsOnRail[owner][userID].checkpoints = checkpoints
		tCartsOnRail[owner][userID].idx = 0
		push(0, tCartsOnRail[owner][userID])
	end
end

function minecart.stop_monitoring(owner, userID, pos)
	print("stop_monitoring", owner, userID)
	if tCartsOnRail[owner] and tCartsOnRail[owner][userID] then
		tCartsOnRail[owner][userID].pos = pos
		tCartsOnRail[owner][userID].objID = 0
	end
end

function minecart.monitoring_remove_cart(owner, userID)
	print("monitoring_remove_cart", owner, userID)
	if tCartsOnRail[owner] and tCartsOnRail[owner][userID] then
		tCartsOnRail[owner][userID].objID = nil
		tCartsOnRail[owner][userID] = nil
	end
end

function minecart.userID_available(owner, userID)
	return not tCartsOnRail[owner] or tCartsOnRail[owner][userID] == nil
end

function minecart.get_cart_monitoring_data(owner, userID)
	if tCartsOnRail[owner] then
		return tCartsOnRail[owner][userID]
	end
end

