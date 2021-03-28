--[[

	Minecart
	========

	Copyright (C) 2019-2020 Joachim Stolberg

	MIT
	See license.txt for more information
	
	Cart library functions (level 1)
	
]]--

-- Notes:
-- 1) Only the owner can punch der cart
-- 2) Only the owner can start the recording
-- 3) But any player can act as cargo, cart punched by owner or buffer

local SLOPE_ACCELERATION = 3
local MAX_SPEED = 7
local PUNCH_SPEED = 3
local SLOWDOWN = 0.4
local CYCLE_TIME = 0.15
local RAILTYPE = minetest.get_item_group("carts:rail", "connect_to_raillike")
local Y_OFFS_ON_SLOPES = 0.7
local TTL_STOP = 5 -- ticks until the stopping entity mutates into a node


-- for lazy programmers
local M = minetest.get_meta
local S = minecart.S
local P2S = function(pos) if pos then return minetest.pos_to_string(pos) end end
local S2P = minetest.string_to_pos
local MP = minetest.get_modpath("minecart")
local D = function(pos) return minetest.pos_to_string(vector.round(pos)) end 


local function get_pitch(dir)
	local pitch = 0
	if dir.y == -1 then
		pitch = math.pi/4
	elseif dir.y == 1 then
		pitch = -math.pi/4
	end
	return pitch * (dir.z == 0 and -1 or 1)
end

local function get_yaw(dir)
	local yaw = 0
	if dir.x < 0 then
		yaw = math.pi/2
	elseif dir.x > 0 then
		yaw = math.pi/2*3
	elseif dir.z < 0 then
		yaw = math.pi
	end
	return yaw
end

local function push_cart(self, pos, punch_dir, puncher)
	local vel = self.object:get_velocity()
	punch_dir = punch_dir or carts:velocity_to_dir(puncher:get_look_dir())
	punch_dir.y = 0
	local cart_dir = carts:get_rail_direction(pos, punch_dir, nil, nil, RAILTYPE)
	
	-- Always start in horizontal direction
	cart_dir.y = 0
	
	if vector.equals(cart_dir, {x=0, y=0, z=0}) then return end
	
	local speed = vector.multiply(cart_dir, PUNCH_SPEED)
	local new_vel = vector.add(vel, speed)
	local yaw = get_yaw(cart_dir)
	local pitch = get_pitch(cart_dir)

	self.object:set_rotation({x = pitch, y = yaw, z = 0})
	self.object:set_velocity(new_vel)

	self.old_pos = vector.round(pos)
	self.stopped = false
	self.left_req = false
	self.right_req = false
end

local api = {}

function api:init(is_node_cart)
	local lib
	
	if is_node_cart then
		lib = dofile(MP.."/cart_lib2n.lua")
	else
		lib = dofile(MP.."/cart_lib2e.lua")
	end
		
	-- add lib to local api
	for k,v in pairs(lib) do
		api[k] = v
	end
end

-- Player get on / off
function api:on_rightclick(clicker)
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

function api:on_activate(staticdata, dtime_s)
	self.object:set_armor_groups({immortal=1})
end

function api:on_detach_child(child)
	if child and child:get_player_name() == self.driver then
		self.driver = nil
	end
end

function api:on_punch(puncher, time_from_last_punch, tool_capabilities, direction)
	local pos = self.object:get_pos()
	local vel = self.object:get_velocity()
	local stopped = vector.equals(vel, {x=0, y=0, z=0})
	local is_minecart = self.node_name == nil
	local node_name = self.node_name or "minecart:cart"
	local puncher_name = puncher and puncher:is_player() and puncher:get_player_name()
	local puncher_is_owner = puncher_name and (not self.owner or self.owner == "" or
			puncher_name == self.owner or
			minetest.check_player_privs(puncher_name, "minecart"))
	local puncher_is_driver = self.driver and self.driver == puncher_name
	local sneak_punch = puncher_name and puncher:get_player_control().sneak
	local no_cargo = next(self.cargo or {}) == nil
	
	-- driver wants to leave/remove the empty Minecart by sneak-punch
	if is_minecart and sneak_punch and puncher_is_driver and no_cargo then
		if puncher_is_owner then
			minecart.hud_remove(self)
			api.remove_cart(self, pos, puncher)
		end
		carts:manage_attachment(puncher, nil)
		return
	end
	
	-- Punched by non-authorized player
	if puncher_name and not puncher_is_owner then
		minetest.chat_send_player(puncher_name, S("[minecart] Cart is protected by ")..(self.owner or ""))
		return
	end
	
	-- Punched by non-player
	if not puncher_name then
		local cart_dir = carts:get_rail_direction(pos, direction, nil, nil, RAILTYPE)
		if vector.equals(cart_dir, {x=0, y=0, z=0}) then
			return
		end
		api.load_cargo(self, pos)
		push_cart(self, pos, cart_dir)
		self.has_no_route = not minecart.monitoring_start_cart(pos, self.myID)
		minecart.hud_remove(self)
		return
	end
	
	-- Sneak-punched by owner
	if sneak_punch then
		-- Unload the cargo
		if api.add_cargo_to_player_inv(self, pos, puncher) then
			return
		end
		-- detach driver
		if self.driver then
			carts:manage_attachment(puncher, nil)
		end
		-- Pick up cart
		api.remove_cart(self, pos, puncher)
		return
	end
	
	-- Cart with driver punched to start recording
	if puncher_is_driver then
		minecart.start_recording(self, pos, vel, puncher)
		self.recording = true
	else
		self.has_no_route = not minecart.monitoring_start_cart(pos, self.myID)
		self.recording = false
	end

	api.load_cargo(self, pos)
	
	push_cart(self, pos, nil, puncher)
end

-- sound refresh interval = 1.0sec
local function rail_sound(self, dtime)
	if not self.sound_ttl then
		self.sound_ttl = 1.0
		return
	elseif self.sound_ttl > 0 then
		self.sound_ttl = self.sound_ttl - dtime
		return
	end
	self.sound_ttl = 1.0
	if self.sound_handle then
		local handle = self.sound_handle
		self.sound_handle = nil
		minetest.after(0.2, minetest.sound_stop, handle)
	end
	if not self.stopped then
		local vel = self.object:get_velocity() or {x=0, y=0, z=0}
		local speed = vector.length(vel)
		self.sound_handle = minetest.sound_play(
			"carts_cart_moving", {
			object = self.object,
			gain = (speed / carts.speed_max) / 2,
			loop = true,
		})
	end
end

local function stop_cart(self, pos)
	if self.ttl then
		self.ttl = self.ttl - 1
		if self.ttl > 0 then
			return
		end
		self.ttl = nil
	end
	if not self.stopped then
		local param2 = minetest.dir_to_facedir(self.old_dir)
		api.stop_cart(pos, self, self.node_name or "minecart:cart", param2)
		if self.recording then
			minecart.stop_recording(self, pos, {x=0, y=0, z=0}, self.driver)
			self.recording = false
		end
		api.unload_cargo(self, pos) 
		self.stopped = true
	end
	self.old_pos = pos
end

local function rail_on_step(self)
	local pos = self.object:get_pos()
	local rot = self.object:get_rotation()
	local vel = self.object:get_velocity()
	
	-- cart position correction on slopes
	local on_slope = rot.x ~= 0
	if on_slope then
		pos.y = pos.y - Y_OFFS_ON_SLOPES
	end
	local pos_rounded = vector.round(pos)
	
	-- Determine correct rail position
	local rail_pos, node = api.find_rail_node(pos_rounded)
	if not rail_pos then
		rail_pos, node = api.find_rail_node(self.old_pos)
		if not rail_pos then
			-- should never happen
			print("stop_cart 2")
			stop_cart(self, pos, false)
			-- TODO: back to start
			minetest.log("error", "[minecart] No valid rail position")
			return
		end
	end
	
	-- Check if stopped
	if self.stopped then
		return
	elseif not on_slope and minecart.stopped(vel) then
		print("stop_cart 1")
		stop_cart(self, rail_pos)
		return -- nothing todo
	end
	
	-- Same pos as before
	if vector.equals(pos_rounded, self.old_pos or {x=0, y=0, z=0}) then
		return -- nothing todo
	end

	-- Used as fallback position
	self.old_pos = rail_pos

	if self.recording then
		minecart.hud_dashboard(self, vel)
	end
	
	if pos_rounded ~= rail_pos then
		pos_rounded = rail_pos
		self.on_wrong_pos = nil
		if on_slope then
			self.object:set_pos({x=rail_pos.x, y=rail_pos.y + Y_OFFS_ON_SLOPES, z=rail_pos.z})
		else
			self.object:set_pos(rail_pos)
		end
	end	
	
	-- Calc new speed
	local speed = math.sqrt((vel.x+vel.z)^2 + vel.y^2)
	local dest_pos = minecart.get_dest_pos(self.myID) or {x=0, y=0, z=0}
	-- Check if slope position
	if pos_rounded.y > self.old_pos.y then
		speed = speed - SLOPE_ACCELERATION
	elseif pos_rounded.y < self.old_pos.y then
		speed = speed + SLOPE_ACCELERATION
	else
		speed = speed - SLOWDOWN
	end
	if self.has_no_route then
		-- Cart without a route is not allowed
		speed = speed - 0.2
	elseif vector.distance(dest_pos, pos_rounded) < 4 then
		speed = 2  -- slow down
	else
		-- Power/brake rail acceleration
		speed = speed + ((carts.railparams[node.name] or {}).acceleration or 0)
	end
	
	-- Determine new direction
	local dir = carts:velocity_to_dir(vel)
	if speed < 0 then
		if on_slope then
			dir = vector.multiply(dir, -1)
			-- start with a value > 0
			speed = 0.5 
		else
			speed = 0
		end
	end
	
	-- Get player controls
	local ctrl, player
	if self.recording then
		player = minetest.get_player_by_name(self.driver)
		if player then
			ctrl = player:get_player_control()
			if ctrl.left then
				self.left_req = true
				self.right_req = false
			elseif ctrl.right then
				self.right_req = true
				self.left_req = false
			end
			ctrl = {left = self.left_req, right = self.right_req}
		end
	end	

	-- new_dir: New moving direction of the cart
	-- keys: Currently pressed L/R key
	local new_dir, keys = carts:get_rail_direction(rail_pos, dir, ctrl, 0, RAILTYPE)

	-- handle junctions
	if not self.recording then -- normal run
		new_dir, keys = minecart.get_junction(self, rail_pos, new_dir)
	end
	
	-- Detect stop
	if new_dir.x == 0 and new_dir.z == 0 then
		-- Stop the cart
		print("Stop the cart")
		self.object:set_velocity({x=0, y=0, z=0})
		self.object:move_to(pos_rounded)
		self.ttl = TTL_STOP
		-- TODO
		return
	-- New direction
	elseif not vector.equals(dir, new_dir) then
		if self.recording and self.left_req or self.right_req then
			minecart.set_junction(self, rail_pos, new_dir, keys)
		end
		self.left_req = false
		self.right_req = false

		if new_dir.y ~= 0 then
			self.object:set_pos({x=pos_rounded.x, y=pos_rounded.y + Y_OFFS_ON_SLOPES, z=pos_rounded.z})
		else
			self.object:set_pos(pos_rounded)
		end
	end
	self.old_dir = dir
	
	-- Set velocity and rotation
	local new_vel = vector.multiply(new_dir, math.min(speed, MAX_SPEED))
	local yaw = get_yaw(new_dir)
	local pitch = get_pitch(new_dir)

	self.object:set_rotation({x = pitch, y = yaw, z = 0})
	self.object:set_velocity(new_vel)
	

	if self.recording then
		minecart.store_next_waypoint(self, rail_pos, new_vel)
	end
end

function api:on_step(dtime)
	self.delay = (self.delay or 0) + dtime
	if self.delay > CYCLE_TIME then
		rail_on_step(self)
		rail_sound(self, self.delay)
		self.delay = 0
	end
end

return api
