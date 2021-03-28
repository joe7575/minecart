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
local MP = minetest.get_modpath("minecart")
local lib = dofile(MP.."/cart_lib3.lua")

local CartsOnRail = minecart.CartsOnRail  -- from storage.lua
local get_route = minecart.get_route  -- from storage.lua

--
-- Route recording
--
function minecart.start_recording(self, pos)	
	print("start_recording")
	self.start_key = lib.get_route_key(pos, self.driver)
	if self.start_key then
		self.waypoints = {}
		self.junctions = {}
		self.recording = true
		self.num_junctions = 0
		self.next_time = minetest.get_us_time() + 1000000
		
		local player = minetest.get_player_by_name(self.driver)
		if player then
			minecart.hud_remove(self)
			self.hud_id = player:hud_add({
				name = "minecart",
				hud_elem_type = "text",
				position = {x = 0.4, y = 0.25},
				scale = {x=100, y=100},
				text = "Test",
				number = 0xFFFFFF,
				--alignment = {x = 1, y = 1},
				--offset = {x = 100, y = 100},
				size = {x = 1},
			})
		end
	end
end

function minecart.store_next_waypoint(self, pos, vel)	
	if self.start_key and self.recording and self.driver and 
			self.next_time < minetest.get_us_time() then
		self.next_time = minetest.get_us_time() + 1000000
		self.waypoints[#self.waypoints+1] = {P2S(vector.round(pos)), P2S(vector.round(vel))}
	elseif self.recording and not self.driver then
		self.recording = false
		self.waypoints = nil
		self.junctions = nil
	end
end

-- destination reached(speed == 0)
function minecart.stop_recording(self, pos, vel, puncher)	
	print("stop_recording")
	local dest_pos = lib.get_route_key(pos, self.driver)
	local player = minetest.get_player_by_name(self.driver)
	if dest_pos then
		if self.start_key and self.start_key ~= dest_pos then
			local route = {
				waypoints = self.waypoints,
				dest_pos = dest_pos,
				junctions = self.junctions,
			}
			minecart.store_route(self.start_key, route)
			minetest.chat_send_player(self.driver, S("[minecart] Route stored!"))
		end
	end
	self.recording = false
	self.waypoints = nil
	self.junctions = nil
end

function minecart.set_junction(self, pos, dir, switch_keys)
	if self.junctions then
		self.junctions[P2S(pos)] = {dir, switch_keys}
		self.num_junctions = self.num_junctions + 1
	end
end

function minecart.get_junction(self, pos, dir)
	local junctions = CartsOnRail[self.myID] and CartsOnRail[self.myID].junctions
	if junctions then
		local data = junctions[P2S(pos)]
		if data then
			return data[1], data[2]
		end
		data = junctions[P2S(vector.subtract(pos, dir))]
		if data then
			return data[1], data[2]
		end
	end
	return dir
end

function minecart.hud_dashboard(self, vel)
	if self.hud_id then
		local player = minetest.get_player_by_name(self.driver)
		if player then
			local speed = math.floor((math.sqrt((vel.x+vel.z)^2 + vel.y^2) * 10) + 0.5) / 10
			local num = self.num_junctions or 0
			local dir = (self.left_req and "left") or (self.right_req and "right") or "straight"
			local s = string.format("Recording: speed = %.1f | dir = %-8s | %u junctions", speed, dir, num)
			player:hud_change(self.hud_id, "text", s)
		end
	end
end

function minecart.hud_remove(self)
	if self.driver then
		local player = minetest.get_player_by_name(self.driver)
		if player and self.hud_id then
			player:hud_remove(self.hud_id)
			self.hud_id = nil
		end
	end
end	
