minetest.register_node("minecart:buffer", {
	description = "Minecart Buffer Stop",
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
