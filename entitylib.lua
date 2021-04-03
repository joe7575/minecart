--[[

	Minecart
	========

	Copyright (C) 2019-2021 Joachim Stolberg

	MIT
	See license.txt for more information
	
]]--

local P2S = function(pos) if pos then return minetest.pos_to_string(pos) end end
local MAX_SPEED = minecart.MAX_SPEED
local Dot2Dir = minecart.Dot2Dir
local Dir2Dot = minecart.Dir2Dot 
local get_waypoint = minecart.get_waypoint
local recording = minecart.recording
local monitoring = minecart.monitoring

local function running(self)
	local rot = self.object:get_rotation()
	local dir = minetest.yaw_to_dir(rot.y)
	local facedir = minetest.dir_to_facedir(dir)
	local new_speed
	local cart_pos
	
	if not self.waypoint then
		-- get waypoint
		local pos = self.object:get_pos()
		self.waypoint = minecart.get_waypoint(pos, facedir, {})
		if not self.waypoint then return end
		new_speed = math.max((self.waypoint.power / 100), 0)
		cart_pos = pos
	else
		-- position correction
		--self.object:set_pos(self.waypoint.cart_pos)
		cart_pos = vector.new(self.waypoint.cart_pos)
		
		-- next waypoint
		self.waypoint = minecart.get_waypoint(self.waypoint.pos, facedir, self.ctrl or {})
		if not self.waypoint then return end
		self.ctrl = nil -- has to be determined for the next waypoint
		local vel = self.object:get_velocity()
		local speed = math.sqrt((vel.x+vel.z)^2 + vel.y^2)
		if self.waypoint.power <= 0 then
			new_speed = math.max(speed + (self.waypoint.power / 100), 0)
		else
			new_speed = math.min((self.waypoint.power / 100), MAX_SPEED)
		end
	end

	-- Speed corrections
	local new_dir = Dot2Dir[self.waypoint.dot]
	if new_dir.y == 1 then
		if new_speed < 1 then new_speed = 0 end
	elseif new_dir.y == -1 then
		if new_speed < 3 then new_speed = 3 end
	else
		if new_speed < 0.4 then new_speed = 0 end
	end
	
	-- Calc velocity, rotation, pos and arrival_time
	local yaw = minetest.dir_to_yaw(new_dir)
	local pitch = new_dir.y * math.pi/4
	local dist = math.max(vector.distance(cart_pos, self.waypoint.cart_pos), 1)
	self.arrival_time = self.timebase + (dist / new_speed)
	
	-- Slope corrections
	if new_dir.y ~= 0 then
		cart_pos.y = cart_pos.y + 0.2
		new_speed = new_speed / 1.41
	end
	
	local vel = vector.multiply(new_dir, new_speed)
	
	self.object:set_pos(cart_pos)
	self.object:set_rotation({x = pitch, y = yaw, z = 0})
	self.object:set_velocity(vel)
	--local s = string.format("power = %.1f, dist = %.1f, pos = %s, cart_pos = %s", self.waypoint.power, dist, P2S(self.waypoint.pos), P2S(self.waypoint.cart_pos))
	--print("running", s)
end

local function play_sound(self)
	if self.sound_handle then
		local handle = self.sound_handle
		self.sound_handle = nil
		minetest.after(0.2, minetest.sound_stop, handle)
	end
	self.sound_handle = minetest.sound_play(
		"carts_cart_moving", {
		object = self.object,
		loop = true,
	})
end

local function on_step(self, dtime)
--	if self.is_recording then
--		recording(self)
--	elseif self.is_monitoring then
--		monitoring(self)
--	end
	
	if self.is_running then
		self.timebase = (self.timebase or 0) + dtime
		print("on_step", self.timebase)
		if self.timebase >= (self.arrival_time or 0) then
			running(self)
		end
		
		self.sound_ttl = (self.sound_ttl or 0) + dtime
		if self.sound_ttl >= 1 then
			play_sound(self)
			self.sound_ttl = 0
		end
	else
		if self.sound_handle then
			minetest.sound_stop(self.sound_handle)
			self.sound_handle = nil
		end		
	end
end

local function on_activate(self, staticdata, dtime_s)
	self.object:set_armor_groups({immortal=1})
end

-- Entity callback: Node is already converted to an entity.
local function on_punch(self, puncher, time_from_last_punch, tool_capabilities, dir)
--	local puncher_name = puncher and puncher:is_player() and puncher:get_player_name()
--	local puncher_is_owner = minecart.is_owner(puncher, self.owner)
--	local puncher_is_driver = self.driver and self.driver == puncher_name
--	local sneak_punch = puncher_name and puncher:get_player_control().sneak
--	local no_cargo = next(self.cargo or {}) == nil
--	local pos = self.object:get_pos()
	
--	-- driver wants to leave/remove the empty cart by sneak-punch
--	if sneak_punch and puncher_is_driver and no_cargo then
--		if puncher_is_owner then
--			minecart.hud_remove(self)
--			local pos = self.object:get_pos()
--			minecart.remove_entity(self, pos, puncher)
--		end
--		carts:manage_attachment(puncher, nil)
--		return
--	end
	
--	-- Punched by non-authorized player
--	if puncher_name and not puncher_is_owner then
--		minetest.chat_send_player(puncher_name, S("[minecart] Cart is protected by ")..(self.owner or ""))
--		return
--	end
	
--	-- Sneak-punched by owner
--	if sneak_punch then
--		-- Unload the cargo
--		if minetest.add_cargo_to_player_inv(self, pos, puncher) then
--			return
--		end
--		-- detach driver
--		if self.driver then
--			carts:manage_attachment(puncher, nil)
--		end
--		-- Pick up cart
--		minetest.remove_entity(self, pos, puncher)
--		return
--	end
	
--	minetest.load_cargo(self, pos)
	
--	-- Cart with driver punched to start recording
--	if puncher_is_driver then
--		minecart.start_recording(self, pos, puncher)
--		self.is_recording = true
--	else
--		self.is_recording = false
--	end

--	minetest.push_cart_entity(self, pos, nil, puncher)

	local pos = self.object:get_pos()
	minecart.remove_entity(self, pos, puncher)
end
	
-- Player get on / off
local function on_rightclick(self, clicker)
	if not clicker or not clicker:is_player() then
		return
	end
	local player_name = clicker:get_player_name()
	if self.driver and player_name == self.driver then
		minecart.hud_remove(self)
		self.driver = nil
		self.recording = false
		carts:manage_attachment(clicker, nil)
	elseif not self.driver then
		self.driver = player_name
		carts:manage_attachment(clicker, self.object)

		-- player_api does not update the animation
		-- when the player is attached, reset to default animation
		player_api.set_animation(clicker, "stand")
	end
end

local function on_detach_child(self, child)
	if child and child:get_player_name() == self.driver then
		self.driver = nil
	end
end


function minecart.register_cart_entity(entity_name, node_name, entity_def)
	entity_def.entity_name = entity_name
	entity_def.node_name = node_name
	entity_def.on_activate = on_activate
	entity_def.on_punch = on_punch
	entity_def.on_step = on_step
	entity_def.on_rightclick = on_rightclick
	entity_def.on_detach_child = on_detach_child
	
	entity_def.owner = nil
	entity_def.driver = nil
	entity_def.cargo = {}
	
	minetest.register_entity(entity_name, entity_def)
	-- register node for punching
	minecart.register_cart_names(node_name, entity_name)
end

