local S = function(pos) if pos then return minetest.pos_to_string(pos) end end

local function on_punch(pos, node, puncher)	
	local start_key = S(pos)
	local route = minecart.get_route(start_key)
	if next(route.waypoints) then
		minetest.chat_send_player(puncher:get_player_name(), "[minecart] Route available:")
		local no_cart = true
		for key,item in pairs(minecart.CartsOnRail) do
			if item.start_key == start_key or item.start_key == route.dest_pos then
				local pos, vel = minecart.current_pos_and_vel(item)
				minetest.chat_send_player(puncher:get_player_name(), " - cart at "..S(pos)..", velocity "..vector.length(vel))
				no_cart = false
			end
		end
		if no_cart then
			minetest.chat_send_player(puncher:get_player_name(), " - no cart available")
		end
	else
		minetest.chat_send_player(puncher:get_player_name(), "[minecart] No route stored!")
	end
end

minetest.register_node("minecart:buffer", {
	description = "Minecart Railway Buffer",
	tiles = {
		'default_junglewood.png',
		'default_junglewood.png',
		'default_junglewood.png',
		'default_junglewood.png',
		'default_junglewood.png',
		'default_junglewood.png^minecart_buffer.png',
		},
	after_place_node = function(pos)
		minecart.del_route(minetest.pos_to_string(pos))
	end,
	after_dig_node = function(pos)
		minecart.del_route(minetest.pos_to_string(pos))
	end,
	on_punch = on_punch,
	sunlight_propagates = true,
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
