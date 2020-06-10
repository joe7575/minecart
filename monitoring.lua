--[[

	Minecart
	========

	Copyright (C) 2019-2020 Joachim Stolberg

	MIT
	See license.txt for more information
	
]]--

-- Some notes:
-- 1) Entity IDs are volatile. For each server restart all carts get new IDs.
-- 2) Monitoring is performed for entities only. Stopped carts in from of
--    real nodes need no monitoring.


-- for lazy programmers
local M = minetest.get_meta
local P2S = function(pos) if pos then return minetest.pos_to_string(pos) end end
local S2P = minetest.string_to_pos
local S = minecart.S
local MP = minetest.get_modpath("minecart")
local lib = dofile(MP.."/cart_lib3.lua")

local CartsOnRail = minecart.CartsOnRail  -- from storage.lua
local get_route = minecart.get_route  -- from storage.lua


--
-- Helper functions
--
local function get_object_id(object)
	for id, entity in pairs(minetest.luaentities) do
		if entity.object == object then
			return id
		end
	end
end

local function calc_pos_and_vel(item)
	if item.start_time and item.start_key then
		local run_time = minetest.get_gametime() - item.start_time
		local waypoints = get_route(item.start_key).waypoints
		local waypoint = waypoints[run_time]
		if waypoint then
			return S2P(waypoint[1]), S2P(waypoint[2])
		end
	end
	if item.last_pos then
		if carts:is_rail(item.last_pos, minetest.raillike_group("rail")) then
			return item.last_pos, item.last_vel
		end
	end
	return item.start_pos, {x=0, y=0, z=0}
end

--
-- Monitoring of cart entities
--
function minecart.add_to_monitoring(obj, myID, owner, userID)
	print("add_to_monitoring", myID, userID)
	local pos = vector.round(obj:get_pos())
	CartsOnRail[myID] = {
		start_key = lib.get_route_key(pos),
		start_pos = pos,
		owner = owner,  -- needed for query API
		userID = userID,  -- needed for query API
		stopped = true,
	}
end

function minecart.update_userID(myID, userID)
	if CartsOnRail[myID] then
		CartsOnRail[myID].userID = userID
	end
end

function minecart.remove_from_monitoring(myID)
	print("remove_from_monitoring", myID)
	if myID then
		CartsOnRail[myID] = nil
	end
end	

function minecart.start_cart(pos, myID)
	local item = CartsOnRail[myID]
	if item and item.stopped then
		item.stopped = false
		-- cart started from a buffer?
		local start_key = lib.get_route_key(pos)
		if start_key then
			item.start_time = minetest.get_gametime()
			item.start_key = start_key
			item.start_pos = pos
			item.junctions = minecart.get_route(start_key).junctions
			return true
		end
	end
	return false
end

function minecart.stop_cart(pos, myID)
	local item = CartsOnRail[myID]
	if item and not item.stopped then
		item.start_time = nil
		item.start_key = nil
		item.start_pos = nil
		item.junctions = nil
		item.stopped = true
		return true
	end
	return false
end

local function monitoring()
	local to_be_added = {}
	for key, item in pairs(CartsOnRail) do
		local entity = minetest.luaentities[key]
		print("Cart:", key, P2S(item.last_pos), item.owner)
		if entity then  -- cart entity running
			local pos = entity.object:get_pos()
			local vel = entity.object:get_velocity()
			if not minetest.get_node_or_nil(pos) then  -- unloaded area
				lib.unload_cart(pos, vel, entity, item)
				item.stopped = vector.equals(vel, {x=0, y=0, z=0})
			end
			-- store last pos from cart without route
			item.last_pos, item.last_vel = pos, vel
		else  -- no cart running
			local pos, vel = calc_pos_and_vel(item)
			if pos and vel then
				if minetest.get_node_or_nil(pos) then  -- loaded area
					local myID = lib.load_cart(pos, vel, item)
					if myID then
						item.stopped = vector.equals(vel, {x=0, y=0, z=0})
						to_be_added[myID] = table.copy(item)
						CartsOnRail[key] = nil  -- invalid old ID 
					end
				end
				item.last_pos, item.last_vel = pos, vel
			else
				CartsOnRail[key] = nil
			end
		end
	end
	-- table maintenance
	for key,val in pairs(to_be_added) do
		CartsOnRail[key] = val
	end
	minetest.after(1, monitoring)
end
minetest.after(1, monitoring)


--
-- API functions
--

-- Return a list of carts with current position and speed.
function minecart.get_cart_list()
	local tbl = {}
	for id, item in pairs(CartsOnRail) do
		local pos, speed = calc_pos_and_vel(item)
		tbl[#tbl+1] = {pos = pos, speed = speed, id = id}
	end
	return tbl
end

-- hier umbauen nach userID und nicht Name
minetest.register_chatcommand("mycart", {
	params = "<cart-num>",
	description = "Output cart state and position",
    func = function(name, param)
		local userID = tonumber(param) or 0
		for id, item in pairs(CartsOnRail) do
			if item.owner == name and item.userID == userID then
				local pos = P2S(vector.round(item.last_pos))
				print(dump(item)) 
				local state = item.stopped and "blocked" or "running"
				local station = lib.get_station_name(item.last_pos)
				if station then  -- stopped at buffer?
					state = "stopped"
					pos = station
				end
				return true, "Cart #"..userID.." "..state.." at "..pos.."  "
			end
		end
		return false, "Cart is unknown"
    end
})

