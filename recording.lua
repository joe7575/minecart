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

local function dashboard_create(self)
	if self.driver then	
		local player = minetest.get_player_by_name(self.driver)
		if player then
			minecart.dashboard_destroy(self)
			self.hud_id = player:hud_add({
				name = "minecart",
				hud_elem_type = "text",
				position = {x = 0.4, y = 0.25},
				scale = {x=100, y=100},
				text = "Test",
				number = 0xFFFFFF,
				size = {x = 1},
			})
		end
	end
end

function minecart.dashboard_update(self, vel)
	if self.driver and self.hud_id then
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

function minecart.dashboard_destroy(self)
	if self.driver and self.hud_id then
		local player = minetest.get_player_by_name(self.driver)
		if player then
			player:hud_remove(self.hud_id)
			self.hud_id = nil
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
			self.rec_time = self.rec_time + 2.0
			
			dashboard_create(self)
		end
	end
end

function minecart.stop_recording(self, pos)	
	print("stop_recording")
	if self.driver then
		local dest_pos = minecart.get_buffer_pos(pos, self.driver)
		local player = minetest.get_player_by_name(self.driver)
		if dest_pos and player then
			if self.start_pos then
				local route = {
					dest_pos = dest_pos,
					waypoints = self.waypoints,
					junctions = self.junctions,
				}
				minecart.store_route(self.start_pos, route)
				minetest.chat_send_player(self.driver, S("[minecart] Route stored!"))
			end
		end
		minecart.dashboard_destroy(self)
	end
	self.is_recording = false
	self.waypoints = nil
	self.junctions = nil
end

function minecart.recording_waypoints(self)	
	self.waypoints[#self.waypoints+1] = {
		-- cart_pos, new_pos, speed, dot
		P2H(self.object:get_pos()), 
		P2H(self.section.pos), 
		math.floor(self.speed + 0.5),
		self.dot
	}
end

function minecart.recording_junctions(self)
	if self.driver then
		local player = minetest.get_player_by_name(self.driver)
		if player then
			local ctrl = player:get_player_control()
			if ctrl.left then
				self.junctions[P2H(self.waypoint.pos)] = {left = true}
			elseif ctrl.right then
				self.junctions[P2H(self.waypoint.pos)] = {right = true}
			end
		end
	end
end
