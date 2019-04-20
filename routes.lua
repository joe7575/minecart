local S = function(pos) if pos then return minetest.pos_to_string(pos) end end

local CartsOnRail = minecart.CartsOnRail

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

local function get_route_key(pos)
	local pos1 = minetest.find_node_near(pos, 1, {"minecart:buffer"})
	if pos1 then
		return S(pos1)
	end
end

--
-- Teach-in
--
function minecart.start_teach_in(self, pos, vel, puncher)	
	-- Player punches cart to start the trip
	if puncher:get_player_name() == self.driver and vector.equals(vel, {x=0, y=0, z=0}) then
		self.start_key = get_route_key(pos)
		if self.start_key then
			CartsOnRail[self.myID] = {start_key = self.start_key, teach_in = true}
			minecart.new_route(self.start_key)
			self.next_time = minetest.get_us_time() + 1000000
		end
	end
end

function minecart.store_next_waypoint(self, pos, vel)	
	if self.start_key and self.teach_in and self.driver and 
			self.next_time < minetest.get_us_time() then
		self.next_time = minetest.get_us_time() + 1000000
		local route = minecart.get_route(self.start_key)
		route[#route+1] = {S(vector.round(pos)), S(vector.round(vel))}
		
		if vector.equals(vel, {x=0, y=0, z=0}) then
			minecart.store_route(self.start_key)
			CartsOnRail[self.myID] = nil
		end
	elseif self.teach_in and not self.driver then
		self.teach_in = false
	end
end

--
-- Run
--
function minecart.on_activate(self, dtime_s)
	self.myID = get_object_id(self.object)
	local pos = self.object:get_pos()
	CartsOnRail[self.myID] = {
		start_key = get_route_key(pos),
		start_pos = pos,
	}
	print("CartsOnRail", dump(CartsOnRail))
end

function minecart.start_run(self, pos, vel)
	if vector.equals(vel, {x=0, y=0, z=0}) then
		CartsOnRail[self.myID] = {
			start_time = minetest.get_gametime(), 
			start_key = get_route_key(pos),
			start_pos = pos,
		}
		minetest.log("info", "[minecart] Cart "..self.myID.." started.")
		print("CartsOnRail", dump(CartsOnRail))
	end
end

function minecart.store_loaded_items(self, pos)
	local data = CartsOnRail[self.myID]
	if data then
		data.attached_items = {}
		for _, obj_ in pairs(minetest.get_objects_inside_radius(pos, 1)) do
			local entity = obj_:get_luaentity()
			if not obj_:is_player() and entity and 
					not entity.physical_state and entity.name == "__builtin:item" then
				obj_:remove()
				data.attached_items[#data.attached_items + 1] = entity.itemstring
			end
		end
	end
end

function minecart.stopped(self, pos)
	local data = CartsOnRail[self.myID]
	if data then
		-- Spawn loaded items again
		if data.attached_items then
			for _,item in ipairs(data.attached_items) do
				minetest.add_item(pos, ItemStack(item))
			end
		end
		-- Remove data
		CartsOnRail[self.myID] = nil
		minetest.log("info", "[minecart] Cart "..self.myID.." stopped.")
	end
end

function minecart.on_dig(self)
	CartsOnRail[self.myID] = nil
end

--
-- Monitoring
--
local function spawn_cart(pos, vel)
	local object = minetest.add_entity(pos, "minecart:cart", nil)
	object:set_velocity(vel)
	local id = get_object_id(object)
	minetest.log("info", "[minecart] Cart "..id.." spawned again.")
	return id
end

local function current_pos_and_vel(item)
	local data
	if item.start_time then
		local run_time = minetest.get_gametime() - item.start_time
		local route = minecart.get_route(item.start_key)
		data = route[run_time]
	else
		data = item.start_pos, {x=0, y=0, z=0}
	end
	if data then
		return minetest.string_to_pos(data[1]), minetest.string_to_pos(data[2])
	end
end

local function monitoring()
	local to_be_added = {}
	for key,item in pairs(CartsOnRail) do
		if not item.teach_in and item.start_key then
			local entity = minetest.luaentities[key]
			local pos, vel = current_pos_and_vel(item)
			if pos and vel then
				if entity then  -- cart running
					if not minetest.get_node_or_nil(pos) then  -- in unloaded area
						minetest.log("info", "[minecart] Cart "..key.." virtualized.")
						entity.object:remove()
					end
				else  -- cart unloaded
					if minetest.get_node_or_nil(pos) then  -- in loaded area
						local id = spawn_cart(pos, vel)
						to_be_added[id] = table.copy(CartsOnRail[key])
						CartsOnRail[key] = nil
					end
				end
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
