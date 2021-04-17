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

local MAX_SPEED = 8
local SLOWDOWN = 0.3
local MAX_NODES = 100

--waypoint = {
--	dot = travel direction, 
--	pos = destination pos, 
--	speed = 10 times the section speed (as int), 
--	limit = 10 times the speed limit (as int),
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
-- Rails plus node carts. Used to find waypoints. Added via add_raillike_nodes
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

-- facedir = math.floor(dot / 4)
-- y       = (dot % 4) - 1

-- Create helper tables
for facedir = 0,3 do
	for y = -1,1 do
		local dot = 1 + facedir * 4 + y
		local dir = vector.new(Facedir2Dir[facedir])
		dir.y = y
		Dot2Dir[dot] = dir
		Dir2Dot[P2H(dir)] = dot
	end
end

local function dot2dir(dot)    return vector.new(Dot2Dir[dot]) end
local function facedir2dir(fd) return vector.new(Facedir2Dir[fd]) end

-------------------------------------------------------------------------------
-- waypoint metadata
-------------------------------------------------------------------------------
local function get_metadata(pos)
    local s = M(pos):get_string("waypoints")
    if s ~= "" then
        return minetest.deserialize(s)
    end
end

local function set_metadata(pos, t)
	local s = minetest.serialize(t)
	M(pos):set_string("waypoints", s)
	minecart.set_marker(pos, "_______set", 0.3, 10)
end

local function del_metadata(pos)
	local meta = M(pos)
    if meta:contains("waypoints") then
        meta:set_string("waypoints", "")
        minecart.set_marker(pos, "del_______", 0.3, 10)
    end
end

-------------------------------------------------------------------------------
-- find_next_waypoint
-------------------------------------------------------------------------------
local function check_right(pos, facedir)
    local fdr = (facedir + 1) % 4  -- right
	local new_pos = vector.add(pos, facedir2dir(fdr)) 
	
	local name = get_node_lvm(new_pos).name
    if tRailsExt[name] or tSigns[name] then
		return true
    end
    new_pos.y = new_pos.y - 1
    if tRailsExt[get_node_lvm(new_pos).name] then
        return true
    end
end

local function check_left(pos, facedir)
    local fdl = (facedir + 3) % 4  -- left
	local new_pos = vector.add(pos, facedir2dir(fdl)) 
	
	local name = get_node_lvm(new_pos).name
    if tRailsExt[name] or tSigns[name] then
		return true
    end
    new_pos.y = new_pos.y - 1
    if tRailsExt[get_node_lvm(new_pos).name] then
        return true
    end
end

local function get_next_pos(pos, facedir, y)
	local new_pos = vector.add(pos, facedir2dir(facedir)) 
    new_pos.y = new_pos.y + y
	local name = get_node_lvm(new_pos).name
    return tRailsExt[name] ~= nil, new_pos, tRailsPower[name] or 0
end

local function is_ramp(pos)
    return tRailsExt[get_node_lvm({x = pos.x, y = pos.y + 1, z = pos.z}).name]  ~= nil
end

-- Check also the next position to detect a ramp
local function slope_detection(pos, facedir)
	local is_rail, new_pos = get_next_pos(pos, facedir, 0)
	if not is_rail then
		return is_ramp(new_pos)
	end
end

local function find_next_waypoint(pos, facedir, y)
	local cnt = 0
	local name = get_node_lvm(pos).name
	local speed = tRailsPower[name] or 0
	local is_rail, new_pos, _speed
	
	while cnt < MAX_NODES do
		is_rail, new_pos, _speed = get_next_pos(pos, facedir, y)
		speed = speed + _speed
		if not is_rail then
			return pos, y == 0 and is_ramp(new_pos), speed
		end
		if y == 0 then  -- no slope
			if check_right(new_pos, facedir) then
				return new_pos, slope_detection(new_pos, facedir), speed
			elseif check_left(new_pos, facedir) then
				return new_pos, slope_detection(new_pos, facedir), speed
			end
		end
		pos = new_pos
		cnt = cnt + 1
	end
	return new_pos, false, speed
end

-------------------------------------------------------------------------------
-- find_all_next_waypoints
-------------------------------------------------------------------------------
local function check_front_up_down(pos, facedir)
	local new_pos = vector.add(pos, facedir2dir(facedir)) 
	
    if tRailsExt[get_node_lvm(new_pos).name] then
		return 0
    end
    new_pos.y = new_pos.y - 1
    if tRailsExt[get_node_lvm(new_pos).name] then
        return -1
    end
    new_pos.y = new_pos.y + 2
    if tRailsExt[get_node_lvm(new_pos).name] then
        return 1
    end
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
local function recalc_speed(num_pow_rails, pos1, pos2, y)
	local num_norm_rails = vector.distance(pos1, pos2) - num_pow_rails
	local ratio, speed
	
	if y ~= 0 then
		num_norm_rails = math.floor(num_norm_rails / 1.41 + 0.5)
	end
	
	if y ~= -1 then
		if num_pow_rails == 0 then
			return num_norm_rails * -SLOWDOWN
		else
			ratio = math.floor(num_norm_rails / num_pow_rails)
			ratio = minecart.range(ratio, 0, 11)
		end
	else
		ratio = 3 + num_norm_rails * SLOWDOWN + num_pow_rails
	end
	
	if y == 1 then
		speed = 7 - ratio
	elseif y == -1 then
		speed = 15 - ratio
	else
		speed = 11 - ratio
	end
	
	return minecart.range(speed, 0, 8)
end	

local function find_all_next_waypoints(pos)
    local wp = {}
	local dots = {}
	local cnt = 0
	
	for facedir = 0,3 do
		local y = check_front_up_down(pos, facedir)
		if y then
			local new_pos, is_ramp, speed = find_next_waypoint(pos, facedir, y)
			local dot = 1 + facedir * 4 + y
			speed = recalc_speed(speed, pos, new_pos, y) * 10
			wp[facedir] = {dot = dot, pos = new_pos, speed = speed, is_ramp = is_ramp}
			cnt = cnt + 1
		end
	end
	
	return wp, cnt
end

-------------------------------------------------------------------------------
-- get_waypoint
-------------------------------------------------------------------------------
-- If ramp, stop 0.5 nodes earlier or later
local function ramp_correction(pos, wp, facedir)
	if wp.is_ramp or pos.y < wp.pos.y then  -- ramp detection
		local dir = facedir2dir(facedir)
		local pos = wp.pos
		
		wp.cart_pos = {
			x = pos.x - dir.x / 2,
			y = pos.y,
			z = pos.z - dir.z / 2}
	elseif pos.y > wp.pos.y then
		local dir = facedir2dir(facedir)
		local pos = wp.pos
		
		wp.cart_pos = {
			x = pos.x + dir.x / 2,
			y = pos.y,
			z = pos.z + dir.z / 2}
	end
	return wp
end



-- Returns waypoint and is_junction
local function get_waypoint(pos, facedir, ctrl, uturn)
	local t = get_metadata(pos) 
	if not t then
		t = find_all_next_waypoints(pos)
		set_metadata(pos, t)
	end
	
	local left  = (facedir + 3) % 4
	local right = (facedir + 1) % 4
	local back  = (facedir + 2) % 4
	
	if ctrl.right and t[right] then return t[right], t[facedir] ~= nil or t[left] ~= nil end
	if ctrl.left  and t[left]  then return t[left] , t[facedir] ~= nil or t[right] ~= nil end
	
	if t[facedir] then return ramp_correction(pos, t[facedir], facedir), false end
	if t[right]   then return ramp_correction(pos, t[right], right),     false end
	if t[left]    then return ramp_correction(pos, t[left], left),       false end
	
	if uturn and t[back] then return t[back], false end
end

-------------------------------------------------------------------------------
-- cart helper function
-------------------------------------------------------------------------------
-- Return new cart pos and if an extra move cycle is needed
function minecart.get_current_cart_pos_correction(curr_pos, curr_fd, curr_y, new_dot)
	local new_y = (new_dot % 4) - 1
	local new_fd = math.floor(new_dot / 4)
	
	if curr_y == -1 or new_y == -1 then
		local new_fd = math.floor(new_dot / 4)
		local dir = facedir2dir(new_fd)
		return {
			x = curr_pos.x + dir.x / 2,
			y = curr_pos.y,
			z = curr_pos.z + dir.z / 2}, new_y == -1
	elseif curr_y == 1 and curr_fd ~= new_fd then
		local dir = facedir2dir(new_fd)
		return {
			x = curr_pos.x + dir.x / 2,
			y = curr_pos.y,
			z = curr_pos.z + dir.z / 2}, true
	elseif curr_y == 1 or new_y == 1 then
		local dir = facedir2dir(curr_fd)
		return {
			x = curr_pos.x - dir.x / 2,
			y = curr_pos.y,
			z = curr_pos.z - dir.z / 2}, false
	end
	return curr_pos, false
end
	
function minecart.get_speedlimit(pos, facedir)
    local fd = (facedir + 1) % 4  -- right
	local new_pos = vector.add(pos, facedir2dir(fd)) 
	local node = get_node_lvm(new_pos)
	if tSigns[node.name] and node.param2 == facedir then
		return tSigns[node.name]
    end
	
    fd = (facedir + 3) % 4  -- left
	new_pos = vector.add(pos, facedir2dir(fd)) 
	node = get_node_lvm(new_pos)
	if tSigns[node.name] and node.param2 == facedir then
		return tSigns[node.name]
    end
end

-- Search for rails in 3 directions (based on given facedir)
--local function find_rails_nearby(pos, facedir, test_for_slope)
--	-- Do not check the direction we are coming from
--	facedir = flip[facedir]
    
--    local tbl = {}
--    for fd = 0, 3 do
--        if fd ~= facedir then 
--            tbl[#tbl + 1] = check_front_up_down(pos, fd, test_for_slope)
--        end
--    end
--	return tbl
--end

local function delete_rail_metadata(pos, nearby)
--	local delete = function(pos)
--		local meta = M(pos)
--		if meta:contains("waypoints") then
--			local hash = P2H(pos)
--			tWaypoints[hash] = nil
--			meta:set_string("waypoints", "")
--			--minecart.set_marker(pos, "delete")
--		end
--	end
	
--	if nearby then
--		local pos1 = {x = pos.x - 1, y = pos.y, z = pos.z - 1}
--		local pos2 = {x = pos.x + 1, y = pos.y, z = pos.z + 1}
--		for _, npos in ipairs(minetest.find_nodes_in_area(pos1, pos2, lRailsExt)) do
--			delete(npos)
--		end
--	else
--		delete(pos)
--	end
end
		
--local function get_rail_power(pos, dot)
--	local node = get_node_lvm(pos)
--	return tRailsPower[node.name] or 0
--end

--local function check_speed_limit(dot, pos)
--	local facedir = math.floor((dot - 1) / 3)
--	local facedir2 = (facedir + 1) % 4 -- turn right
--	local npos = vector.add(pos, facedir2dir(facedir2))
--	local node = get_node_lvm(npos)
--	if tSigns[node.name] then
--		return node.param2 == facedir and tSigns[node.name]
--	end
--	facedir2 = (facedir2 + 2) % 4 -- turn left
--	npos = vector.add(pos, facedir2dir(facedir2))
--	node = get_node_lvm(npos)
--	if tSigns[node.name] then
--		return node.param2 == facedir and tSigns[node.name]
--	end
--end

--local function slope_detection(dot1, dot2)
--	local y1 = ((dot1 - 1) % 3) - 1
--	local y2 = ((dot2 - 1) % 3) - 1
--	local fd1 = math.floor((dot1 - 1) / 3)
--	local fd2 = math.floor((dot2 - 1) / 3)
--	--           ________
--	--          /        \
--	--   ______/          \______
--	--      (1) (2)    (3) (4)
	
--	if y2 == 1 then        -- (1)
--		return fd2 * 2 + 0
--	elseif y1 == 1 then    -- (2)
--		return fd1 * 2 + 0
--	elseif y1 == -1 then   -- (3)
--		return fd2 * 2 + 1
--	elseif y2 == -1 then   -- (4)
--		return fd1 * 2 + 1
--	end
--end	

--local function find_next_waypoint(pos, dot)
--	--print("find_next_waypoint", P2S(pos), dot)
--	local npos = vector.new(pos)
--	local facedir = math.floor((dot - 1) / 3)
--	local power = 0
--	local cnt = 0
	
--	while cnt < MAX_NODES do
--		power = power + get_rail_power(npos, dot)
--		npos = vector.add(npos, dot2dir(dot))
--		local dots = find_rails_nearby(npos, facedir, true)
--		-- check for speed sign as end of the section
--		local speed = check_speed_limit(dot, npos)
		
--		if #dots == 0 then -- end of rail
--			return npos, power
--		elseif #dots > 1 then -- junction
--			return npos, power
--		elseif dots[1] ~= dot then -- curve or slope
--			return npos, power, slope_detection(dot, dots[1])
--		elseif speed then -- sign detected
--			--print("check_speed_limit", speed)
--			return npos, power, slope_detection(dot, dots[1])
--		end
--		cnt = cnt + 1
--	end
--	return npos, power
--end

--local function find_next_meta(pos, dot)
--	--print("find_next_meta", P2S(pos), dot)
--	local npos = vector.new(pos)
--	local facedir = math.floor((dot - 1) / 3)
--	local old_dot = dot
--	local cnt = 0

--	while cnt <= MAX_NODES do
--		npos = vector.add(npos, Dot2Dir[dot])
--		local dot = check_front_up_down(npos, facedir)
--		if M(npos):contains("waypoints") then
--			return npos
--		end
--		if dot ~= old_dot then
--			return
--		end
--		cnt = cnt + 1
--	end
--	return npos
--end	

-- Search for rails in all 4 directions
--local function find_all_rails_nearby(pos)
--	--print("find_all_rails_nearby")
--    local tbl = {}
--    for fd = 0, 3 do
--		tbl[#tbl + 1] = check_front_up_down(pos, fd, true)
--    end
--	return tbl
--end


--local function determine_waypoints(pos)
--	--print("determine_waypoints")
--    local waypoints = {}
--	local dots = {}
--	local limit
--	local has_waypoint = false
	
--	for _,dot in ipairs(find_all_rails_nearby(pos, 0)) do
--		local npos, power, slope = find_next_waypoint(pos, dot)
--		power = math.floor(recalc_power(dot, power, pos, npos) * 100)
--		-- check for speed limit
--		local speed = check_speed_limit(dot, pos)
--		if speed then
--			limit = speed * 100
--		end
--		local facedir = math.floor((dot - 1) / 3)
--		waypoints[facedir] = {dot = dot, pos = npos, power = power, limit = limit, slope = slope}
--		dots[#dots + 1] = dot
--		has_waypoint = true
--	end
--	if has_waypoint then
--		M(pos):set_string("waypoints", minetest.serialize(waypoints))
--		minecart.set_marker(pos, "_________add")
--		return waypoints
--	end
--end

--local function delete_waypoints(pos)
--	-- Use invalid facedir to be able to test all 4 directions
--	for _, dot in ipairs(find_rails_nearby(pos, 4)) do
--		local npos = find_next_meta(pos, dot)
--		if npos then
--			delete_rail_metadata(npos, true)
--		end		
--	end
--	delete_rail_metadata(pos, true)
--end	

--local function get_metadata(pos)
--    local s = M(pos):get_string("waypoints")
--    if s ~= "" then
--        return minetest.deserialize(s)
--    end
--end

-- Cart position correction, if it is a change in y direction (slope kink)
--local function slope_handling(wp)
--	if wp.slope then  -- slope kink
--		local facedir = math.floor(wp.slope / 2)
--		local kink_type = wp.slope % 2
--		local dir = facedir2dir(facedir)
--		local pos = wp.pos
		
--		if kink_type == 0 then	-- up
--			wp.cart_pos = {
--				x = pos.x - dir.x / 2,
--				y = pos.y,
--				z = pos.z - dir.z / 2}
--		else  -- down
--			wp.cart_pos = {
--				x = pos.x + dir.x / 2,
--				y = pos.y,
--				z = pos.z + dir.z / 2}
--		end
--	end
--	return wp
--end
				
-- Return the new waypoint and a bool "was junction"
--local function get_waypoint(pos, facedir, ctrl, uturn)
--    local hash = P2H(pos)
--	tWaypoints[hash] = tWaypoints[hash] or get_metadata(pos) or determine_waypoints(pos) or {}
--	local t = tWaypoints[hash] 
	
--	local left  = (facedir + 3) % 4
--	local right = (facedir + 1) % 4
--	local back  = (facedir + 2) % 4
	
--	if ctrl.right and t[right] then return t[right], t[facedir] ~= nil or t[left] ~= nil end
--	if ctrl.left  and t[left]  then return t[left] , t[facedir] ~= nil or t[right] ~= nil end
	
--	if t[facedir] then return slope_handling(t[facedir]), false end
--	if t[right]   then return slope_handling(t[right]),   false end
--	if t[left]    then return slope_handling(t[left]),    false end
	
--	if uturn and t[back] then return t[back], false end
--end

--local function after_dig_node(pos, oldnode, oldmetadata, digger)
--	delete_waypoints(pos)
--end

--local function after_place_node(pos, oldnode, oldmetadata, digger)
--	delete_waypoints(pos)
--end

--for name,_ in pairs(tRails) do
--	minetest.override_item(name, {
--			after_destruct = after_dig_node, 
--			after_place_node = after_place_node
--	})
--end	

minecart.MAX_SPEED = MAX_SPEED
minecart.dot2dir = dot2dir
--minecart.dir2dot = dir2dot 
minecart.facedir2dir = facedir2dir

minecart.get_waypoint = get_waypoint
minecart.delete_waypoint = delete_rail_metadata -- used by carts
minecart.lRails = lRails
minecart.tRails = tRails
minecart.tRailsExt = tRailsExt
minecart.lRailsExt = lRailsExt
minecart.tWaypoints = tWaypoints
minecart.check_front_up_down = check_front_up_down

---- used by speed limit signs
--function minecart.delete_waypoints(pos)
--	local pos1 = {x = pos.x - 1, y = pos.y, z = pos.z - 1}
--	local pos2 = {x = pos.x + 1, y = pos.y, z = pos.z + 1}
--	local posses = minetest.find_nodes_in_area(pos1, pos2, lRailsExt)
--	for _, pos in ipairs(posses) do
--		delete_waypoints(pos)
--	end
--end

function minecart.is_rail(pos)
	return tRails[get_node_lvm(pos).name] ~= nil
end

function minecart.add_raillike_nodes(name)
	tRailsExt[name] = true
	lRailsExt[#lRailsExt + 1] = name
end

-- For debugging purposes
function minecart.get_waypoints(pos)
    local hash = P2H(pos)
	tWaypoints[hash] = tWaypoints[hash] or get_metadata(pos) or determine_waypoints(pos)
	return tWaypoints[hash]
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

