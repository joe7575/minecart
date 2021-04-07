--[[

	Minecart
	========

	Copyright (C) 2019-2021 Joachim Stolberg

	MIT
	See license.txt for more information
	
]]--

local P2S = function(pos) if pos then return minetest.pos_to_string(pos) end end
local P2H = minetest.hash_node_position
local H2P = minetest.get_position_from_hash
local MAX_SPEED = minecart.MAX_SPEED
local Dot2Dir = minecart.Dot2Dir
local Dir2Dot = minecart.Dir2Dot
local get_waypoint = minecart.get_waypoint
local recording_waypoints = minecart.recording_waypoints
local recording_junctions = minecart.recording_junctions
local tEntityNames = minecart.tEntityNames

local function stop_cart(self)
	self.is_running = false
	self.arrival_time = 0
	local pos = self.object:get_pos()
	
	if self.driver then
		local player = minetest.get_player_by_name(self.driver)
		if player then
			minecart.manage_attachment(player, self, false)
		end
	end
	minecart.entity_to_node(pos, self)
end

local function running(self)
	local rot = self.object:get_rotation()
	local dir = minetest.yaw_to_dir(rot.y)
	dir.y = math.floor((rot.x / (math.pi/4)) + 0.5)
	local facedir = minetest.dir_to_facedir(dir)
	local cart_pos, cart_speed, new_speed
	
	if self.reenter then -- through monitoring
		cart_pos = H2P(self.reenter[1])
		cart_speed = self.reenter[3]
		self.waypoint = {pos = H2P(self.reenter[2]), power = 0, limit = MAX_SPEED, dot = self.reenter[4]}
		self.reenter = nil
	elseif not self.waypoint then
		-- get waypoint
		cart_pos = self.object:get_pos()
		cart_speed = 2
		self.waypoint = get_waypoint(cart_pos, facedir, {}, true)
	else
		-- next waypoint
		cart_pos = vector.new(self.waypoint.pos)
		local vel = self.object:get_velocity()
		cart_speed = math.sqrt((vel.x+vel.z)^2 + vel.y^2)
		local ctrl = self.junctions and self.junctions[P2H(self.waypoint.pos)] or {}
		self.waypoint = get_waypoint(self.waypoint.pos, facedir, ctrl, cart_speed < 0.1)
	end

	if not self.waypoint then
		stop_cart(self)
		return
	end
	
	-- Calc speed
	local rail_power = self.waypoint.power / 100
	local speed_limit = self.waypoint.limit / 100
	--print("speed", rail_power, speed_limit)
	if rail_power <= 0 then
		new_speed = math.max(cart_speed + rail_power, 0)
		new_speed = math.min(new_speed, speed_limit)
	elseif rail_power < cart_speed then
		new_speed = math.min((cart_speed + rail_power) / 2, speed_limit)
	else
		new_speed = math.min(rail_power, speed_limit)
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
	
	-- Slope corrections
	if new_dir.y ~= 0 then
		cart_pos = vector.add(cart_pos, {x = new_dir.x / 2, y = 0.2, z = new_dir.z / 2})
	elseif dir.y == 1 then
		cart_pos = vector.subtract(cart_pos, {x = dir.x / 2, y = 0, z = dir.z / 2})
	elseif dir.y == -1 then
		cart_pos = vector.add(cart_pos, {x = dir.x / 2, y = 0, z = dir.z / 2})
	end	
	
	-- Calc velocity, rotation and arrival_time
	local yaw = minetest.dir_to_yaw(new_dir)
	local pitch = new_dir.y * math.pi/4
	local dist = vector.distance(cart_pos, self.waypoint.pos)
	local vel = vector.multiply(new_dir, new_speed / (new_dir.y ~= 0 and 1.41 or 1))
	self.arrival_time = self.timebase + (dist / new_speed)
	self.speed = new_speed  -- needed for recording
	self.dot = Dir2Dot[new_dir]  -- needed for recording
	
	if new_speed < 0.1 or dist < 0.5 then
		stop_cart(self)
		return
	end
		
	self.object:set_pos(cart_pos)
	self.object:set_rotation({x = pitch, y = yaw, z = 0})
	self.object:set_velocity(vel)
	return
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
		gain = self.speed / MAX_SPEED,
	})
end

local function on_step(self, dtime)
	self.timebase = (self.timebase or 0) + dtime
	
	if self.is_running then
		if self.arrival_time <= self.timebase then
			running(self)
		end
		
		if (self.sound_ttl or 0) <= self.timebase then
			play_sound(self)
			self.sound_ttl = self.timebase + 1.0
		end
	else
		if self.sound_handle then
			minetest.sound_stop(self.sound_handle)
			self.sound_handle = nil
		end		
	end

	if self.is_recording then
		if self.rec_time <= self.timebase then
			recording_waypoints(self)
			self.rec_time = self.rec_time + 2.0
		end
		recording_junctions(self)
	end
end

local function on_entitycard_activate(self, staticdata, dtime_s)
	self.object:set_armor_groups({immortal=1})
end

-- Start the entity cart (or dig by shift+leftclick)
local function on_entitycard_punch(self, puncher, time_from_last_punch, tool_capabilities, dir)
	if minecart.is_owner(puncher, self.owner) then
		if puncher:get_player_control().sneak then
			-- Dig cart
			if self.driver then
				-- remove cart as driver
				local pos = self.object:get_pos()
				minecart.remove_entity(self, pos, puncher)
				minecart.manage_attachment(puncher, self, false)
			else
				-- remove cart from outside
				local pos = self.object:get_pos()
				minecart.remove_entity(self, pos, puncher)
			end
		end
	end
end
	
-- Player get on / off
local function on_entitycard_rightclick(self, clicker)
	if clicker and clicker:is_player() then
		-- Get on / off
		if self.driver then
			-- get off
			local pos = self.object:get_pos()
			minecart.entity_to_node(pos, self)
			minecart.manage_attachment(clicker, self, false)
		else
			-- get on
			minecart.manage_attachment(clicker, self, true)
		end
	end
end

local function on_entitycard_detach_child(self, child)
	if child and child:get_player_name() == self.driver then
		self.driver = nil
	end
end

function minecart.get_entitycart_nearby(pos, param2, radius)
	local pos2 = param2 and vector.add(pos, minecart.param2_to_dir(param2)) or pos
	for _, object in pairs(minetest.get_objects_inside_radius(pos2, radius or 0.5)) do
		local entity = object:get_luaentity()
		if entity and entity.name and tEntityNames[entity.name] then
			local vel = object:get_velocity()
			if vector.equals(vel, {x=0, y=0, z=0}) then  -- still standing?
				return entity
			end
		end
	end	
end

function minecart.push_entitycart(self, punch_dir)
	print("push_entitycart")
	local pos = self.object:get_pos()
	local vel = self.object:get_velocity()
	punch_dir.y = 0
	local yaw = minetest.dir_to_yaw(punch_dir)
	self.object:set_rotation({x = 0, y = yaw, z = 0})
	self.is_running = true
	self.arrival_time = 0
end

function minecart.register_cart_entity(entity_name, node_name, entity_def)
	entity_def.entity_name = entity_name
	entity_def.node_name = node_name
	entity_def.on_activate = on_entitycard_activate
	entity_def.on_punch = on_entitycard_punch
	entity_def.on_step = on_step
	entity_def.on_rightclick = on_entitycard_rightclick
	entity_def.on_detach_child = on_entitycard_detach_child
	
	entity_def.owner = nil
	entity_def.driver = nil
	entity_def.cargo = {}
	
	minetest.register_entity(entity_name, entity_def)
	-- register node for punching
	minecart.register_cart_names(node_name, entity_name)
end

