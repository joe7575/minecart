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

local function dashboard_destroy(self)
	if self.driver and self.hud_id then
		local player = minetest.get_player_by_name(self.driver)
		if player then
			player:hud_remove(self.hud_id)
			self.hud_id = nil
		end
	end
end

local function dashboard_create(self)
	if self.driver then	
		local player = minetest.get_player_by_name(self.driver)
		if player then
			dashboard_destroy(self)
			self.hud_id = player:hud_add({
				name = "minecart",
				hud_elem_type = "text",
				position = {x = 0.4, y = 0.25},
				scale = {x=100, y=100},
				text = "Recording:",
				number = 0xFFFFFF,
				size = {x = 1},
			})
		end
	end
end

local function dashboard_update(self)
	if self.driver and self.hud_id then
		local player = minetest.get_player_by_name(self.driver)
		if player then
			local num = self.num_sections or 0
			local dir = (self.ctrl and self.ctrl.left and "left") or 
					(self.ctrl and self.ctrl.right and "right") or "straight"
			local speed = math.floor((self.speed or 0) + 0.5)
			local s = string.format("Recording: speed = %.1f | dir = %-8s | %u sections", 
					speed, dir, num)
			player:hud_change(self.hud_id, "text", s)
		end
	end
end

--
-- Route recording
--
function minecart.start_recording(self, pos)	
	print("start_recording")
	if self.driver then
		self.start_pos = minecart.get_buffer_pos(pos, self.driver)
		if self.start_pos then
			self.checkpoints = {}
			self.junctions = {}
			self.is_recording = true
			self.rec_time = self.timebase
			self.hud_time = self.timebase
			self.num_sections = 0
			self.ctrl = {}
			dashboard_create(self)
			dashboard_update(self, 0)
		end
	end
end

function minecart.stop_recording(self, pos)	
	print("stop_recording")
	if self.driver and self.is_recording then
		local dest_pos = minecart.get_buffer_pos(pos, self.driver)
		local player = minetest.get_player_by_name(self.driver)
		if dest_pos and player then
			if self.start_pos then
				local route = {
					dest_pos = dest_pos,
					checkpoints = self.checkpoints,
					junctions = self.junctions,
				}
				minecart.store_route(self.start_pos, route)
				minetest.chat_send_player(self.driver, S("[minecart] Route stored!"))
			end
		end
		dashboard_destroy(self)
	end
	self.is_recording = false
	self.waypoints = nil
	self.junctions = nil
end

function minecart.recording_waypoints(self)	
	local pos = self.object:get_pos()
	pos = vector.round(pos)
	self.checkpoints[#self.checkpoints+1] = {
		-- cart_pos, new_pos, speed, dot
		P2H(pos), 
		P2H(self.waypoint.pos), 
		math.floor(self.speed + 0.5),
		self.waypoint.dot
	}
end

function minecart.recording_junctions(self, speed)
	local player = minetest.get_player_by_name(self.driver)
	if player then
		local ctrl = player:get_player_control()
		if ctrl.left then
			self.ctrl = {left = true}
			self.junctions[P2H(self.waypoint.pos)] = self.ctrl
		elseif ctrl.right then
			self.ctrl = {right = true}
			self.junctions[P2H(self.waypoint.pos)] = self.ctrl
		end
	end
	if self.hud_time <= self.timebase then
		dashboard_update(self)
		self.hud_time = self.timebase + 0.5
	end
end

function minecart.player_ctrl(self)
	local player = minetest.get_player_by_name(self.driver)
	if player then
		local ctrl = player:get_player_control()
		if ctrl.left then
			self.ctrl = {left = true}
		elseif ctrl.right then
			self.ctrl = {right = true}
		end
	end
end
