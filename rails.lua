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
local P2H = minetest.hash_node_position

local get_node_lvm = minecart.get_node_lvm

local SLOPE_ACCELERATION = 1
local MAX_SPEED = 8
local SLOWDOWN = 0.4
local MAX_NODES = 100

--waypoint = {
--	dot = travel direction, 
--	pos = destination pos, 
--	power = 100 times the waypoint speed (as int), 
--	limit = 100 times the speed limit (as int),
--}
--
-- waypoints = {facedir = waypoint,...}

local tWaypoints = {} -- {pos_hash = waypoints, ...}

local tRailsPower = {
	["carts:rail"] = 0,
	["carts:powerrail"] = 1,
	["carts:brakerail"] = 0,
}
-- Real rails from the mod carts
local tRails = {
	["carts:rail"] = true,
	["carts:powerrail"] = true,
	["carts:brakerail"] = true,
}
-- Rails plus node carts used to find waypoints, added via add_raillike_nodes
local tRailsExt = {
	["carts:rail"] = true,
	["carts:powerrail"] = true,
	["carts:brakerail"] = true,
}

local tSigns = {
	["minecart:speed1"] = 1, 
	["minecart:speed2"] = 2, 
	["minecart:speed4"] = 4,
	["minecart:speed8"] = 8,
}

-- Real rails from the mod carts
local lRails = {"carts:rail", "carts:powerrail", "carts:brakerail"}
-- Rails plus node carts used to find waypoints, , added via add_raillike_nodes
local lRailsExt = {"carts:rail", "carts:powerrail", "carts:brakerail"}

local Dot2Dir = {}
local Dir2Dot = {}
local Facedir2Dir = {[0] =
	{x= 0, y=0,  z= 1},
	{x= 1, y=0,  z= 0},
	{x= 0, y=0,  z=-1},
	{x=-1, y=0,  z= 0},
	{x= 0, y=-1, z= 0},
	{x= 0, y=1,  z= 0},
}

local flip = {
	[0] = 2,
	[1] = 3,
	[2] = 0,
	[3] = 1,
	[4] = 5,
	[5] = 4,
}

-- Create helper tables
for dot = 1,12 do
    local facedir = math.floor((dot - 1) / 3)
    local dir = minetest.facedir_to_dir(facedir)
	dir.y = ((dot - 1) % 3) - 1
    Dot2Dir[dot] = vector.new(dir)
    Dir2Dot[P2H(dir)] = dot
	-- dot = facedir * 3 + dir.y + 2
end


local function check_front_up_down(pos, facedir, test_for_slope)
	local npos
	
    npos = vector.add(pos, Facedir2Dir[facedir]) 
    if tRailsExt[get_node_lvm(npos).name] then
		-- We also have to check the next node to find the next upgoing rail.
		if test_for_slope then
			npos = vector.add(npos, Facedir2Dir[facedir])
			npos.y = npos.y + 1
			if tRailsExt[get_node_lvm(npos).name] then
				--print("check_front_up_down: 2up")
				return facedir * 3 + 3 -- up
			end
		end
		--print("check_front_up_down: front")
		return facedir * 3 + 2 -- front
    end

    npos.y = npos.y - 1
    if tRailsExt[get_node_lvm(npos).name] then
		--print("check_front_up_down: down")
        return facedir * 3 + 1 -- down
    end
	
    npos.y = npos.y + 2
    if tRailsExt[get_node_lvm(npos).name] then
		--print("check_front_up_down: up")
        return facedir * 3 + 3 -- up
    end
end

-- Search for rails in 3 directions (based on given facedir)
local function find_rails_nearby(pos, facedir, test_for_slope)
	-- Do not check the direction we are coming from
	facedir = flip[facedir]
    
    local tbl = {}
    for fd = 0, 3 do
        if fd ~= facedir then 
            tbl[#tbl + 1] = check_front_up_down(pos, fd, test_for_slope)
        end
    end
	return tbl
end

local function delete_rail_metadata(pos, nearby)
	local delete = function(pos)
		local meta = M(pos)
		if meta:contains("waypoints") then
			local hash = P2H(pos)
			tWaypoints[hash] = nil
			meta:set_string("waypoints", "")
			--minecart.set_marker(pos, "delete")
		end
	end
	
	if nearby then
		local pos1 = {x = pos.x - 1, y = pos.y, z = pos.z - 1}
		local pos2 = {x = pos.x + 1, y = pos.y, z = pos.z + 1}
		for _, npos in ipairs(minetest.find_nodes_in_area_under_air(pos1, pos2, lRailsExt)) do
			delete(npos)
		end
	else
		delete(pos)
	end
end
		
local function get_rail_power(pos, dot)
	local y = ((dot - 1) % 3) - 1
	local node
	if y == 1 then
		node = get_node_lvm({x = pos.x, y = pos.y - 1, z = pos.z})
	else
		node = get_node_lvm(pos)
	end
	return tRailsPower[node.name] or 0
end

local function check_speed_limit(dot, pos)
	local facedir = math.floor((dot - 1) / 3)
	local facedir2 = (facedir + 1) % 4 -- turn right
	local npos = vector.add(pos, Facedir2Dir[facedir2])
	local node = get_node_lvm(npos)
	if tSigns[node.name] then
		return node.param2 == facedir and tSigns[node.name]
	end
	facedir2 = (facedir2 + 2) % 4 -- turn left
	npos = vector.add(pos, Facedir2Dir[facedir2])
	node = get_node_lvm(npos)
	if tSigns[node.name] then
		return node.param2 == facedir and tSigns[node.name]
	end
end

local function find_next_waypoint(pos, dot)
	--print("find_next_waypoint", P2S(pos), dot)
	local npos = vector.new(pos)
	local facedir = math.floor((dot - 1) / 3)
	local y = ((dot - 1) % 3) - 1
	local power = 0
	local cnt = 0
	
	while cnt < MAX_NODES do
		npos = vector.add(npos, Dot2Dir[dot])
		power = power + get_rail_power(npos, dot)
		local dots = find_rails_nearby(npos, facedir, true)
		-- check for speed sign as end of the section
		local speed = check_speed_limit(dot, npos)
		
		if #dots == 0 then -- end of rail
			return npos, power
		elseif #dots > 1 then -- junction
			return npos, power
		elseif dots[1] ~= dot then -- curve
			-- If the direction changes to upwards,
			-- the destination pos must be one block further to hit the next rail.
			if y == 1 then
				local dir = Dot2Dir[dot]
				npos = vector.add(npos, Facedir2Dir[facedir])
				return npos, power
			end
			return npos, power
		elseif speed then -- sign detected
			--print("check_speed_limit", speed)
			return npos, power
		end
		cnt = cnt + 1
	end
	return npos, power
end

local function find_next_meta(pos, dot)
	--print("find_next_meta", P2S(pos), dot)
	local npos = vector.new(pos)
	local facedir = math.floor((dot - 1) / 3)
	local old_dot = dot
	local cnt = 0

	while cnt <= MAX_NODES do
		npos = vector.add(npos, Dot2Dir[dot])
		local dot = check_front_up_down(npos, facedir)
		if M(npos):contains("waypoints") then
			return npos
		end
		if dot ~= old_dot then
			return
		end
		cnt = cnt + 1
	end
	return npos
end	

-- Search for rails in all 4 directions
local function find_all_rails_nearby(pos)
	--print("find_all_rails_nearby")
    local tbl = {}
    for fd = 0, 3 do
		tbl[#tbl + 1] = check_front_up_down(pos, fd, true)
    end
	return tbl
end

-- Recalc the value based on waypoint length and slope
local function recalc_power(dot, num_pow_rails, pos1, pos2)
	local ratio, power
	
	if num_pow_rails == 0 then
		ratio = 11
	else
		local num_norm_rails = vector.distance(pos1, pos2) - num_pow_rails
		ratio = math.floor(num_norm_rails / num_pow_rails)
		ratio = minecart.range(ratio, 0, 11)
	end
	
	local y = ((dot - 1) % 3) - 1
	if y == 1 then
		power = 7 - ratio
	elseif y == -1 then
		power = 15 - ratio
	else
		power = 11 - ratio
	end
	
	return minecart.range(power, 0, 8)
end	

local function determine_waypoints(pos)
	--print("determine_waypoints")
    local waypoints = {}
	local dots = {}
	for _,dot in ipairs(find_all_rails_nearby(pos, 0)) do
		local npos, power = find_next_waypoint(pos, dot)
		power = math.floor(recalc_power(dot, power, pos, npos) * 100)
		-- check for speed limit
		local limit = (check_speed_limit(dot, pos) or MAX_SPEED) * 100
		local facedir = math.floor((dot - 1) / 3)
		waypoints[facedir] = {dot = dot, pos = npos, power = power, limit = limit}
		dots[#dots + 1] = dot
	end
	M(pos):set_string("waypoints", minetest.serialize(waypoints))
	--minecart.set_marker(pos, "add")
    return waypoints
end

local function delete_waypoints(pos)
	-- Use invalid facedir to be able to test all 4 directions
	for _, dot in ipairs(find_rails_nearby(pos, 4)) do
		local npos = find_next_meta(pos, dot)
		if npos then
			delete_rail_metadata(npos, true)
		end		
	end
	delete_rail_metadata(pos, true)
end	

local function get_metadata(pos)
    local s = M(pos):get_string("waypoints")
    if s ~= "" then
        return minetest.deserialize(s)
    end
end

local function get_waypoint(pos, facedir, ctrl, uturn)
    local hash = P2H(pos)
	tWaypoints[hash] = tWaypoints[hash] or get_metadata(pos) or determine_waypoints(pos)
	local t = tWaypoints[hash]
	
	local left  = (facedir + 3) % 4
	local right = (facedir + 1) % 4
	local back  = (facedir + 2) % 4
	
	if ctrl.right and t[right] then return t[right] end
	if ctrl.left  and t[left]  then return t[left]  end
	
	if t[facedir] then return t[facedir] end
	if t[right]   then return t[right]   end
	if t[left]    then return t[left]    end
	
	if uturn and t[back] then return t[back] end
end

local function after_dig_node(pos, oldnode, oldmetadata, digger)
	delete_waypoints(pos)
end

local function after_place_node(pos, oldnode, oldmetadata, digger)
	delete_waypoints(pos)
end

for name,_ in pairs(tRails) do
	minetest.override_item(name, {
			after_destruct = after_dig_node, 
			after_place_node = after_place_node
	})
end	

minecart.MAX_SPEED = MAX_SPEED
minecart.Dot2Dir = Dot2Dir
minecart.Dir2Dot = Dir2Dot 
minecart.get_waypoint = get_waypoint
minecart.delete_waypoint = delete_rail_metadata
minecart.lRails = lRails

-- used by speed limit signs
function minecart.delete_waypoints(pos)
	local pos1 = {x = pos.x - 1, y = pos.y, z = pos.z - 1}
	local pos2 = {x = pos.x + 1, y = pos.y, z = pos.z + 1}
	local posses = minetest.find_nodes_in_area(pos1, pos2, lRailsExt)
	for _, pos in ipairs(posses) do
		delete_waypoints(pos)
	end
end

function minecart.is_rail(pos)
	return tRails[get_node_lvm(pos).name] ~= nil
end

function minecart.add_raillike_nodes(name)
	tRailsExt[name] = true
	lRailsExt[#lRailsExt + 1] = name
end

minetest.register_lbm({
	label = "Delete waypoints",
	name = "minecart:rails",
	nodenames = lRailsExt,
	run_at_every_load = true,
	action = function(pos, node)
		M(pos):set_string("waypoints", "")
	end,
})
