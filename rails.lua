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

--waypoint = {
--	dot = travel direction, 
--	pos = destination pos, 
--	power = 10 times the waypoint speed (as int), 
--	cart_pos = destination cart pos
--}
--
-- waypoints = {facedir = waypoint,...}

local tWaypoints = {} -- {pos_hash = waypoints, ...}
local tRails = {
	["carts:rail"] = true,
	["carts:powerrail"] = true,
	["carts:brakerail"] = true,
}

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
	[3] = 1
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


local function check_front_up_down(pos, facedir)
	local npos
	
    npos = vector.add(pos, Facedir2Dir[facedir]) 
    if tRails[get_node_lvm(npos).name] then
		-- We also have to check the next node to find the next upgoing rail.
		npos = vector.add(npos, Facedir2Dir[facedir])
		npos.y = npos.y + 1
		if tRails[get_node_lvm(npos).name] then
			--print("check_front_up_down: 2up")
			return facedir * 3 + 3 -- up
		end
  
		--print("check_front_up_down: front")
		return facedir * 3 + 2 -- front
    end

    npos.y = npos.y - 1
    if tRails[get_node_lvm(npos).name] then
		--print("check_front_up_down: down")
        return facedir * 3 + 1 -- down
    end
	
    npos.y = npos.y + 2
    if tRails[get_node_lvm(npos).name] then
		--print("check_front_up_down: up")
        return facedir * 3 + 3 -- up
    end
end

-- Search for rails in 3 directions (based on given facedir)
local function find_rails_nearby(pos, facedir)
	-- Do not check the direction we are coming from
	facedir = flip[facedir]
    
    local tbl = {}
    for fd = 0, 3 do
        if fd ~= facedir then 
            tbl[#tbl + 1] = check_front_up_down(pos, fd)
        end
    end
	return tbl
end

local function get_rail_power(pos, dot)
	local y = ((dot - 1) % 3) - 1
	local node
	if y == 1 then
		node = get_node_lvm({x = pos.x, y = pos.y - 1, z = pos.z})
	else
		node = get_node_lvm(pos)
	end
	return (carts.railparams[node.name] or {}).acceleration or 0
end

local function find_next_waypoint(pos, dot)
	--print("find_next_waypoint", P2S(pos), dot)
	local npos = vector.new(pos)
	local facedir = math.floor((dot - 1) / 3)
	local y = ((dot - 1) % 3) - 1
	local power = 0
	local cnt = 0
	while cnt < 1000 do
		npos = vector.add(npos, Dot2Dir[dot])
		power = power + get_rail_power(npos, dot)
		local dots = find_rails_nearby(npos, facedir)
		
		if #dots == 0 then -- end of rail
			return npos, power, npos
		elseif #dots > 1 then -- junction
			return npos, power, npos
		elseif dots[1] ~= dot then -- curve
			-- If the direction changes to upwards ,
			-- the cart position must be half a block further and
			-- the destination pos must be one block further to hit the next rail.
			if y == 1 then
				local dir = Dot2Dir[dot]
				local cart_pos = vector.add(npos, {x = dir.x / 2, y = 0, z = dir.z / 2})
				npos = vector.add(npos, Facedir2Dir[facedir])
				return npos, power, cart_pos
			end
			-- If the direction changes between straight, up and down,
			-- the cart position must be half a block further.
			local chng = dot - dots[1]
			if chng >= -2 and chng <= 1 then
				local dir = Dot2Dir[dot]
				local cart_pos = vector.add(npos, {x = dir.x / 2, y = 0, z = dir.z / 2})
				return npos, power, cart_pos
			end
			
			return npos, power, npos
		end
		cnt = cnt + 1
	end
	return pos, 0, pos
end

-- Search for rails in all 4 directions
local function find_all_rails_nearby(pos)
	--print("find_all_rails_nearby")
    local tbl = {}
    for fd = 0, 3 do
		tbl[#tbl + 1] = check_front_up_down(pos, fd)
    end
	return tbl
end

-- Recalc the value based on waypoint length and slope
local function recalc_power(dot, power, pos1, pos2)
	local y = ((dot - 1) % 3) - 1
	local dist = vector.distance(pos1, pos2)
	local offs
	
	if y == 1 then
		--print("recalc_power", power, dist * -SLOPE_ACCELERATION)
		offs = dist * -SLOPE_ACCELERATION
	elseif y == -1 then
		--print("recalc_power", power, dist * SLOPE_ACCELERATION)
		offs = dist * SLOPE_ACCELERATION
	else
		offs = dist * -SLOWDOWN
	end
	
	power = power + offs
	
	if power > MAX_SPEED then
		return MAX_SPEED
	elseif power < -MAX_SPEED then
		return -MAX_SPEED
	else
		return power
	end
end	

local function is_waypoint(dots)
	if #dots ~= 2 then return true end
	
	local facedir1 = math.floor((dots[1] - 1) / 3)
	local facedir2 = math.floor((dots[2] - 1) / 3)
	local y1 = ((dots[1] - 1) % 3) - 1
	local y2 = ((dots[2] - 1) % 3) - 1
	
	if facedir1 ~= flip[facedir2] then return true end
	if y1 ~= y2 * -1 then return true end
	
	return false
end	

local function determine_waypoints(pos)
	--print("determine_waypoints")
	local t = minetest.get_us_time()
    local waypoints = {}
	local dots = {}
	for _,dot in ipairs(find_all_rails_nearby(pos, 0)) do
		local npos, power, cart_pos = find_next_waypoint(pos, dot)
		local facedir = math.floor((dot - 1) / 3)
		power = math.floor(recalc_power(dot, power, pos, npos) * 100)
		waypoints[facedir] = {dot = dot, pos = npos, power = power, cart_pos = cart_pos}
		dots[#dots + 1] = dot
	end
	if is_waypoint(dots) then
		M(pos):set_string("waypoints", minetest.serialize(waypoints))
	end
	t = minetest.get_us_time() - t
	print("time = ", t)
    return waypoints
end

local function get_metadata(pos)
    local s = M(pos):get_string("waypoints")
    if s ~= "" then
        return minetest.deserialize(s)
    end
end

local function get_waypoint(pos, facedir, ctrl)
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
	if t[back]    then return t[back]    end
end

local function after_dig_node(pos, oldnode, oldmetadata, digger)
	print("after_dig_node")
	for _, waypoint in pairs(determine_waypoints(pos)) do
		if waypoint.pos then
			print("after_dig_node", P2S(waypoint.pos))
			local hash = P2H(waypoint.pos)
			tWaypoints[hash] = nil
			M(waypoint.pos):set_string("waypoints", "")
		end
	end
end

for name,_ in pairs(tRails) do
	minetest.override_item(name, {after_dig_node = after_dig_node})
end	

minecart.MAX_SPEED = MAX_SPEED
minecart.Dot2Dir = Dot2Dir
minecart.Dir2Dot = Dir2Dot 
minecart.find_next_waypoint = find_next_waypoint
minecart.get_waypoint = get_waypoint

function minecart.is_rail(pos)
	return tRails[get_node_lvm(pos).name] ~= nil
end

minetest.register_lbm({
	label = "Delete waypoints",
	name = "minecart:rails",
	nodenames = {"carts:rail", "carts:powerrail", "carts:brakerail"},
	run_at_every_load = true,
	action = function(pos, node)
		M(pos):set_string("waypoints", "")
	end,
})