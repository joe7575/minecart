local S = minecart.S
local RANGE = 8

local Rails = {
	"carts:rail",
	"carts:powerrail",
	"carts:brakerail",
}

local function landmark_found(pos, name, range)
	local pos1 = {x=pos.x-range, y=pos.y-range, z=pos.z-range}
	local pos2 = {x=pos.x+range, y=pos.y+range, z=pos.z+range}
	for _,npos in ipairs(minetest.find_nodes_in_area(pos1, pos2, {"minecart:landmark"})) do
		if minetest.get_meta(npos):get_string("owner") ~= name then
			return true
		end
	end
	return false
end

local function is_protected(pos, name, range)
	if not minetest.is_protected(pos, name)
			and (minetest.check_player_privs(name, "minecart")
			or not landmark_found(pos, name, range)) then
		return false
	end
	return true
end

local function can_dig(pos, player)
	return not is_protected(pos, player:get_player_name(), RANGE)
end

local function after_place_node(pos, placer, itemstack, pointed_thing)
	if is_protected(pos, placer:get_player_name(), RANGE) then
		minetest.remove_node(pos)
		return true
	end
end	

for _,name in ipairs(Rails) do
	minetest.override_item(name, {can_dig = can_dig, after_place_node = after_place_node})
end

minetest.register_node("minecart:landmark", {
	description = S("Minecart Landmark"),
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {
			{-3/16, -8/16, -3/16,  3/16, 4/16, 3/16},
			{-2/16,  4/16, -3/16,  2/16, 5/16, 3/16},
		},
	},
	tiles = {
		'default_mossycobble.png',
		'default_mossycobble.png',
		'default_mossycobble.png',
		'default_mossycobble.png',
		'default_mossycobble.png^minecart_protect.png',
		'default_mossycobble.png^minecart_protect.png',
	},
	after_place_node = function(pos, placer, itemstack, pointed_thing)
		local meta = minetest.get_meta(pos)
		meta:set_string("owner", placer:get_player_name())
		if is_protected(pos, placer:get_player_name(), RANGE+3) then
			minetest.remove_node(pos)
			return true
		end
	end,
	
	can_dig = function(pos, digger)
		local meta = minetest.get_meta(pos)
		if meta:get_string("owner") == digger:get_player_name() then
			return true
		end
		if minetest.check_player_privs(digger:get_player_name(), "minecart") then
			return true
		end
		return false
	end,
	
	paramtype2 = "facedir",
	sunlight_propagates = true,
	groups = {cracky = 3, stone = 1},
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),
})

minetest.register_craft({
	output = "minecart:landmark 6",
	recipe = {
		{"", "default:mossycobble", ""},
		{"", "default:mossycobble", ""},
		{"", "default:mossycobble", ""},
	},
})

minetest.register_privilege("minecart", {
	description = S("Allow to dig/place rails in Minecart Landmark areas"),
	give_to_singleplayer = false,
	give_to_admin = true,
})