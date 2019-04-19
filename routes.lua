local S = function(pos) if pos then return minetest.pos_to_string(pos) end end

local CartsOnRail = {}

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
			print("Start teaching "..self.start_key)
			CartsOnRail[self.myID] = {start_key = self.start_key}
			self.teach_in = true
			minecart.new_route(self.start_key)
			self.next_time = minetest.get_us_time() + 1000000
		end
	end
end


function minecart.store_next_waypoint(self, pos, vel)	
--	if self.myID and not vector.equals(vel, {x=0, y=0, z=0}) then
--		print("Cart "..self.myID.." running at "..S(vector.round(pos)))
--	end
	if self.teach_in and self.driver and self.next_time < minetest.get_us_time() then
		self.next_time = minetest.get_us_time() + 1000000
		local route = minecart.get_route(self.start_key)
		route[#route+1] = {S(vector.round(pos)), S(vector.round(vel))}
		print("Waypoint "..S(vector.round(pos)).." added")
		
		if vector.equals(vel, {x=0, y=0, z=0}) then
			self.teach_in = false
			minecart.store_route(self.start_key)
			print("stored")
			CartsOnRail[self.myID] = nil
		end
	elseif self.teach_in and not self.driver then
		print("lost driver")
		self.teach_in = false
	end
end

--
-- Run
--
local function remove_cart(self, pos)
	if not get_route_key(pos) then
		CartsOnRail[self.myID] = nil
		print("cart "..self.myID.." removed")
		self.object:remove()
	end
end

function minecart.on_activate(self, dtime_s)
	self.myID = get_object_id(self.object)
	local pos = self.object:get_pos()
	print("Cart "..self.myID.." activated at "..S(vector.round(pos)))

	if not self.driver and dtime_s > 2 then -- cart was unloaded?
		-- wait a second until the world is loaded
		minetest.after(1, remove_cart, self, pos)
	end
end

function minecart.start_run(self, pos, vel)
	if vector.equals(vel, {x=0, y=0, z=0}) then
		CartsOnRail[self.myID] = {
			start_time = minetest.get_gametime(), 
			start_key = get_route_key(pos),
			start_pos = pos,
		}
		print("Cart "..self.myID.." started")
	end
end

function minecart.stopped(self, pos)
	if CartsOnRail[self.myID] then
		print("Cart "..self.myID.." stopped")
		CartsOnRail[self.myID] = nil
	end
	if self.attached_items then
		for _,item in ipairs(self.attached_items) do
			minetest.add_item(pos, item)
			print(item:get_name())
		end
		self.attached_items = {}
	end
end

function minecart.on_dig(self)
	print("Cart "..self.myID.." dug")
	CartsOnRail[self.myID] = nil
end

minetest.register_node("minecart:buffer", {
	description = "buffer",
	tiles = {
		'default_junglewood.png',
		'default_junglewood.png',
		'default_junglewood.png',
		'default_junglewood.png',
		'default_junglewood.png',
		'default_junglewood.png^minecart_buffer.png',
		},
	after_place_node = function(pos)
		minecart.del_route(S(pos))
	end,
	after_dig_node = function(pos)
		minecart.del_route(S(pos))
	end,
	sunlight_propagates = true,
	paramtype2 = "facedir",
	groups = {cracky=2, crumbly=2, choppy=2},
	is_ground_content = false,
	sounds = default.node_sound_wood_defaults(),
})


local function monitoring()
	local tbl = {}
	for key,item in pairs(CartsOnRail) do
		if item.start_time then
			local t = minetest.get_gametime() - item.start_time
			local entity = minetest.luaentities[key]
			if entity then
				-- Cart in loaded area
				local spos = S(vector.round(entity.old_pos))
				print("cart "..key.." running since "..t.." at "..spos)
				if not item.attached_items then
					item.attached_items = table.copy(entity.attached_items)
				end
				local route = minecart.get_route(item.start_key)
				local data = route[t+1]
				if data then
					local pos = minetest.string_to_pos(data[1])
					if not minetest.get_node_or_nil(pos) then
						-- Cart will reach an unloaded area
						print("cart "..key.." removed")
						entity.object:remove()
						item.cart_removed = true
					end
				end
			else
				-- Cart in unloaded area
				if item.start_key then
					local route = minecart.get_route(item.start_key)
					local data = route[t]
					if data then
						if not item.cart_removed then
							-- load area so that the cart will be removed
							local pos = minetest.string_to_pos(data[1])
							if pos then
								minetest.load_area(pos)
								print("area loaded")
							end
						end
						print("cart "..key.." should be at "..data[1])
						local pos = minetest.string_to_pos(data[1])
						local vel = minetest.string_to_pos(data[2])
						if minetest.get_node_or_nil(pos) then
							local object = minetest.add_entity(pos, "minecart:cart", nil)
							object:set_velocity(vel)
							local id = get_object_id(object)
							local entity = object:get_luaentity()
							if item.attached_items then
								entity.attached_items = table.copy(item.attached_items)
							end
							print("New cart "..id.." spawned")
							tbl[id] = table.copy(CartsOnRail[key])
							--print("cart "..key.." removed from CartsOnRail")
							CartsOnRail[key] = nil
						end
					else
						print("cart "..key.." has reached the dest")
						CartsOnRail[key] = nil
					end
				end
			end
		end
	end
	for key,val in pairs(tbl) do
		--print("cart "..key.." in CartsOnRail added")
		CartsOnRail[key] = val
	end
	minetest.after(1, monitoring)
end
minetest.after(1, monitoring)


minetest.register_on_shutdown(function()
	for key,item in pairs(CartsOnRail) do
		local entity = minetest.luaentities[key]
		if entity and item.start_pos then
			entity.object:set_pos(item.start_pos)
			entity.object:set_velocity({x=0, y=0, z=0})
		else
			print("pos is nil", item.start_pos)
		end
	end
end)