--[[

	Minecart
	========

	Copyright (C) 2019-2020 Joachim Stolberg

	MIT
	See license.txt for more information
	
]]--

-- Some notes:
-- 1) Entity IDs are volatile. For each server restart all carts get new IDs.
-- 2) Monitoring is performed for entities only. Stopped carts in form of
--    real nodes need no monitoring.
-- 3) But nodes at stations have to call 'node_at_station' to be "visible"
--    for the chat commands


-- for lazy programmers
local M = minetest.get_meta
local P2S = function(pos) if pos then return minetest.pos_to_string(pos) end end
local S2P = minetest.string_to_pos
local S = minecart.S
local MP = minetest.get_modpath("minecart")
local lib = dofile(MP.."/cart_lib3.lua")

local CartsOnRail = minecart.CartsOnRail  -- from storage.lua
local get_route = minecart.get_route  -- from storage.lua
local NodesAtStation = {}

--
-- Helper functions
--
local function get_pos_vel(item)
	if item.start_time and item.start_key then  -- cart on recorded route
		local run_time = minetest.get_gametime() - item.start_time
		local waypoints = get_route(item.start_key).waypoints
		if run_time >= #waypoints then
			local waypoint = waypoints[#waypoints]
			return S2P(waypoint[1]), S2P(waypoint[2]), true -- time to appear
		else
			local waypoint = waypoints[run_time]
			return S2P(waypoint[1]), S2P(waypoint[2]), false
		end
	end
end

local function is_player_nearby(pos)
	for _, object in pairs(minetest.get_objects_inside_radius(pos, 30)) do
		if object:is_player() then
			return true
		end
	end
end

--
-- Monitoring API functions
--
function minecart.add_to_monitoring(myID, pos, entity_name, owner, userID)
	print("add_to_monitoring")
	if myID and pos and entity_name and owner and userID then
		local start_key = lib.get_route_key(pos)
		if start_key then
			local route = get_route(start_key)
			if route then
				CartsOnRail[myID] = {
					start_key = start_key,
					last_pos = pos,
					entity_name = entity_name,
					owner = owner,  -- needed for query API
					userID = userID,  -- needed for query API
					junctions = route.junctions,
					dest_pos = S2P(route.dest_pos),
					stopped = true,
				}
				minecart.store_carts()
				return true
			end
		end
	end
end

function minecart.monitoring_start_cart(myID)
	print("monitoring_start_cart")
	if myID then
		local item = CartsOnRail[myID]
		if item and item.stopped then
			item.stopped = false
			item.start_time = minetest.get_gametime()
			minecart.store_carts()
			return true
		end
	end
	return false
end

function minecart.monitoring_stop_cart(myID)
	print("monitoring_stop_cart")
	if myID then
		local item = CartsOnRail[myID]
		if item and not item.stopped then
			item.start_time = nil
			item.stopped = true
			item.time_to_appear = nil
			minecart.store_carts()
			return true
		end
	end
	return false
end

-- When cart entity is removed
function minecart.remove_from_monitoring(myID)
	print("remove_from_monitoring")
	if myID then
		CartsOnRail[myID] = nil
		minecart.store_carts()
	end
end	

--
-- Additional API functions
--
-- For the emergency "back to start"
function minecart.get_start_pos_vel(myID)
	local item = CartsOnRail[myID]
	if item then
		local waypoints = get_route(item.start_key).waypoints
		local waypoint = waypoints[1]
		if waypoint then
			local pos = S2P(waypoint[1])
			local vel = S2P(waypoint[2])
			vel = vector.multiply(vel, -1)
			return pos, vel
		end
	end
end

-- Called after cart number formspec is closed
function minecart.update_userID(myID, userID)
	if CartsOnRail[myID] then
		CartsOnRail[myID].userID = userID
	end
end


-- For node carts at stations
function minecart.node_at_station(owner, userID, pos)
	print("node_at_station", owner, userID, P2S(pos))
	NodesAtStation[owner] = NodesAtStation[owner] or {}
	NodesAtStation[owner][userID] = pos
end
		
--
-- Monitoring
--
-- Copy item data to entity cart
local function item_to_entity(pos, vel, item)
	pos = lib.find_rail_node(pos)
	if pos then
		-- Add cart to map
		local obj = minetest.add_entity(pos, item.entity_name or "minecart:cart", nil)
		-- Determine ID
		local myID = lib.get_object_id(obj)
		if myID then
			-- Copy item data to cart entity
			local entity = obj:get_luaentity()
			entity.owner = item.owner or "unknown"
			entity.userID = item.userID or 0
			entity.cargo = item.cargo or {}
			entity.myID = myID
			obj:set_nametag_attributes({color = "#FFFF00", text = entity.owner..": "..entity.userID})
			-- Update item data
			item.cargo = nil
			-- Start cart
			obj:set_velocity(vel)
			obj:set_rotation({x = 0, y = 0, z = 0})
			return myID
		else
			-- should never happen
			minetest.log("error", "[minecart] Entity has no ID")
		end
	end
end

local function entity_to_item(entity, item)
	item.cargo = entity.cargo
	-- Remove entity from map
	entity.object:remove()
	-- Stop sound
	if entity.sound_handle then
		minetest.sound_stop(entity.sound_handle)
		entity.sound_handle = nil
	end
end

local function debug(item, pos, entity)
	if item.owner == "wuffi" or item.owner == "singleplayer" then
		print("Cart:", 
			item.userID, 
			P2S(vector.round(pos)), 
			item.stopped and "stopped" or "running", 
			entity and "entity" or "virtualized", 
			item.entity_name)
	end
end

local function monitoring()
	local to_be_added = {}
	local to_be_removed = {}
	
	for key, item in pairs(CartsOnRail) do
		local entity = minetest.luaentities[key]
		if entity then  -- cart entity running
			local pos = entity.object:get_pos()
			local vel = entity.object:get_velocity()
			if pos and vel then
				--debug(item, pos, entity)
				item.last_pos = pos
				item.stopped = minecart.stopped(vel)
				if not is_player_nearby(pos) and not item.time_to_appear then
					entity_to_item(entity, item)
				end
			else
				minetest.log("error", "[minecart] Entity issues")
			end
			--entity.stopped = false -- force to stop monitoring
		else  -- no cart running
			local pos, vel, time_to_appear = get_pos_vel(item)
			if pos and vel then
				--debug(item, pos, entity)
				item.last_pos = pos
				item.stopped = minecart.stopped(vel)
				if time_to_appear or is_player_nearby(pos) then
					local myID = item_to_entity(pos, vel, item)
					if myID then
						item.time_to_appear = time_to_appear
						to_be_added[myID] = table.copy(item)
						to_be_removed[#to_be_removed + 1] = key
					end
				end
			else
				minetest.log("error", "[minecart] Cart got lost")
				to_be_removed[#to_be_removed + 1] = key
			end
		end
	end
	
	-- table maintenance
	local is_changed = false
	for key,val in pairs(to_be_added) do
		CartsOnRail[key] = val
		is_changed = true
	end
	for _,key in ipairs(to_be_removed) do
		CartsOnRail[key] = nil
		is_changed = true
	end
	if is_changed then
		minecart.store_carts()
	end
	minetest.after(1, monitoring)
end
-- delay the start to prevent cart disappear into nirvana
minetest.register_on_mods_loaded(function()
	minetest.after(10, monitoring)
end)


--
-- API functions
--

-- Return a list of carts with current position and speed.
function minecart.get_cart_list()
	local tbl = {}
	for id, item in pairs(CartsOnRail) do
		local pos, speed = get_pos_vel(item)
		tbl[#tbl+1] = {pos = pos, speed = speed, id = id}
	end
	return tbl
end

-- Function returns the cart state ("running" / "stopped") and
-- the station name or position string, or if cart is running, 
-- the distance to the query_pos.
function minecart.get_cart_state_and_loc(name, userID, query_pos)
	-- First check if node cart is at any station
	local cart_pos = NodesAtStation[name] and NodesAtStation[name][userID]
	if cart_pos then
		return "stopped", lib.get_station_name(cart_pos)
	end
	-- Then check all running carts
	for id, item in pairs(CartsOnRail) do
		if item.owner == name and item.userID == userID then
			local loc = lib.get_station_name(item.last_pos) or
					math.floor(vector.distance(item.last_pos, query_pos))
			return (item.stopped and "stopped") or "running", loc
		end
	end
	return "unknown", 0
end	

minetest.register_chatcommand("mycart", {
	params = "<cart-num>",
	description = "Output cart state and position, or a list of carts, if no cart number is given.",
    func = function(name, param)
		local userID = tonumber(param)
		local query_pos = minetest.get_player_by_name(name):get_pos()
		
		if userID then
			local state, loc = minecart.get_cart_state_and_loc(name, userID, query_pos)
			if type(loc) == "number" then
				return true, "Cart #" .. userID .. " " .. state .. " " .. loc .. " m away  "
			else
				return true, "Cart #" .. userID .. " " .. state .. " at ".. loc .. "  "
			end
			return false, "Cart #" .. userID .. " is unknown  "
		else
			-- Output a list with all numbers
			local tbl = {}
			for userID, pos in pairs(NodesAtStation[name] or {}) do
				tbl[#tbl + 1] = userID
			end
			for id, item in pairs(CartsOnRail) do
				if item.owner == name then
					tbl[#tbl + 1] = item.userID
				end
			end
			return true, "List of carts: "..table.concat(tbl, ", ").."  "
		end
    end
})

function minecart.cmnd_cart_state(name, userID)
	local state, loc = minecart.get_cart_state_and_loc(name, userID, {x=0, y=0, z=0})
	return state
end

function minecart.cmnd_cart_location(name, userID, query_pos)
	local state, loc = minecart.get_cart_state_and_loc(name, userID, query_pos)
	return loc
end

minetest.register_on_mods_loaded(function()
	if minetest.global_exists("techage") then
		techage.icta_register_condition("cart_state", {
			title = "read cart state",
			formspec = {
				{
					type = "digits",
					name = "number",
					label = "cart number",
					default = "",
				},
				{
					type = "label", 
					name = "lbl", 
					label = "Read state from one of your carts", 
				},
			},
			button = function(data, environ)  -- default button label
				local number = tonumber(data.number) or 0
				return 'cart_state('..number..')'
			end,
			code = function(data, environ)
				local condition = function(env, idx)
					local number = tonumber(data.number) or 0
					return minecart.cmnd_cart_state(environ.owner, number)
				end
				local result = function(val)
					return val ~= 0
				end
				return condition, result
			end,
		})
		techage.icta_register_condition("cart_location", {
			title = "read cart location",
			formspec = {
				{
					type = "digits",
					name = "number",
					label = "cart number",
					default = "",
				},
				{
					type = "label", 
					name = "lbl", 
					label = "Read location from one of your carts", 
				},
			},
			button = function(data, environ)  -- default button label
				local number = tonumber(data.number) or 0
				return 'cart_loc('..number..')'
			end,
			code = function(data, environ)
				local condition = function(env, idx)
					local number = tonumber(data.number) or 0
					return minecart.cmnd_cart_location(environ.owner, number, env.pos)
				end
				local result = function(val)
					return val ~= 0
				end
				return condition, result
			end,
		})
		techage.lua_ctlr.register_function("cart_state", {
			cmnd = function(self, num) 
				num = tonumber(num) or 0
				return minecart.cmnd_cart_state(self.meta.owner, num)
			end,
			help = " $cart_state(num)\n"..
				" Read state from one of your carts.\n"..
				' "num" is the cart number\n'..
				' example: sts = $cart_state(2)'
		})
		techage.lua_ctlr.register_function("cart_location", {
			cmnd = function(self, num) 
				num = tonumber(num) or 0
				return minecart.cmnd_cart_location(self.meta.owner, num, self.meta.pos)
			end,
			help = " $cart_location(num)\n"..
				" Read location from one of your carts.\n"..
				' "num" is the cart number\n'..
				' example: sts = $cart_location(2)'
		})
	end
end)

