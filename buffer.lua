local P2S = function(pos) if pos then return minetest.pos_to_string(pos) end end
local S = minecart.S

local function on_punch(pos, node, puncher)	
	local start_key = P2S(pos)
	local route = minecart.get_route(start_key)
	if next(route.waypoints) then
		minetest.chat_send_player(puncher:get_player_name(), 
				S("[minecart] Route available"))
		local no_cart = true
		for key,item in pairs(minecart.CartsOnRail) do
			if item.start_key == start_key or item.start_key == route.dest_pos then
				local pos, vel = minecart.calc_pos_and_vel(item)
				minetest.chat_send_player(puncher:get_player_name(), S("[minecart] One cart at").." "..
						P2S(pos)..", "..S("velocity").." "..vector.length(vel))
				no_cart = false
			end
		end
		if no_cart then
			minetest.chat_send_player(puncher:get_player_name(), S("[minecart] No cart available"))
		end
	else
		minetest.chat_send_player(puncher:get_player_name(), S("[minecart] No route stored!"))
	end
end

minetest.register_node("minecart:buffer", {
	description = S("Minecart Railway Buffer"),
	tiles = {
		'default_junglewood.png',
		'default_junglewood.png',
		'default_junglewood.png',
		'default_junglewood.png',
		'default_junglewood.png',
		'default_junglewood.png^minecart_buffer.png',
		},
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {
			{-8/16, -8/16, -8/16,  8/16,  -4/16,  8/16},
			{-8/16, -4/16, -8/16,  8/16,   0/16,  4/16},
			{-8/16,  0/16, -8/16,  8/16,   4/16,  0/16},
			{-8/16,  4/16, -8/16,  8/16,   8/16, -4/16},
		},
	},
	selection_box = {
		type = "fixed",
		fixed = {-8/16, -8/16, -8/16,  8/16, 8/16, 8/16},
	},
	after_place_node = function(pos, placer)
		local meta = minetest.get_meta(pos)
		meta:set_string("owner", placer:get_player_name())
		minecart.del_route(minetest.pos_to_string(pos))
	end,
	after_dig_node = function(pos)
		minecart.del_route(minetest.pos_to_string(pos))
	end,
	on_punch = on_punch,
	sunlight_propagates = true,
	on_rotate = screwdriver.disallow,
	paramtype2 = "facedir",
	groups = {cracky=2, crumbly=2, choppy=2},
	is_ground_content = false,
	sounds = default.node_sound_wood_defaults(),
})

minetest.register_craft({
	output = "minecart:buffer",
	recipe = {
		{"dye:red", "", "dye:white"},
		{"default:steel_ingot", "default:junglewood", "default:steel_ingot"},
	},
})
