minecart.doc = {}

if not minetest.get_modpath("doc") then
	return
end

local S = minecart.S

local summary_doc = table.concat({
	S("Summary"),
	"------------",
	"",
	S("1. Place your rails and build a route with two ends. Junctions are allowed as long as each route has its own start and end point."),
	S("2. Place a Railway Buffer at both ends."),
	S("3. Protect your rails with the Protection Landmarks (one Landmark at least every 16 blocks)"),
	S("4. Drive the route in both directions (route recording), starting at the Railway Buffers."),
	S("5. Now you can drop items into the Minecart and punch the cart to get started."),
	S("6. Sneak+click the cart to get the items back"),
	S("7. Dig the empty cart with a second sneak+Click (as usual).")
}, "\n")

local cart_doc = S("Primary used to transport items. You can drop items into the Minecart and punch the cart to get started. Sneak+click the cart to get the items back")

local buffer_doc = S("Used as buffer on both rail ends. Needed to be able to record the cart routes")

local landmark_doc = S("Protect your rails with the Landmarks (one Landmark at least every 16 blocks near the rail)")

local function formspec(data)
	if data.image then
		local image = "image["..(doc.FORMSPEC.ENTRY_WIDTH - 3)..",0;3,2;"..data.image.."]"
		local formstring = doc.widgets.text(data.text, doc.FORMSPEC.ENTRY_START_X, doc.FORMSPEC.ENTRY_START_Y+1.6, doc.FORMSPEC.ENTRY_WIDTH, doc.FORMSPEC.ENTRY_HEIGHT - 1.6)
		return image..formstring
	elseif data.item then
		local box = "box["..(doc.FORMSPEC.ENTRY_WIDTH - 1.6)..",0;1,1.1;#BBBBBB]"
		local image = "item_image["..(doc.FORMSPEC.ENTRY_WIDTH - 1.5)..",0.1;1,1;"..data.item.."]"
		local formstring = doc.widgets.text(data.text, doc.FORMSPEC.ENTRY_START_X, doc.FORMSPEC.ENTRY_START_Y+0.8, doc.FORMSPEC.ENTRY_WIDTH, doc.FORMSPEC.ENTRY_HEIGHT - 0.8)
		return box..image..formstring
	else
		return doc.entry_builders.text(data.text)
	end
end

doc.add_category("minecart",
{
	name = S("Minecart"),
	description = S("A minecart running through unloaded areas, mainly used for item transportation"),
	sorting = "custom",
	sorting_data = {"summary", "cart"},
	build_formspec = formspec,
})

doc.add_entry("minecart", "summary", {
	name = S("Summary"),
	data = {text=summary_doc, image="minecart_doc_image.png"},
})

doc.add_entry("minecart", "cart", {
	name = S("Minecart Cart"),
	data = {text=cart_doc, item="minecart:cart"},
})

doc.add_entry("minecart", "buffer", {
	name = S("Minecart Railway Buffer"),
	data = {text=buffer_doc, item="minecart:buffer"},
})

doc.add_entry("minecart", "landmark", {
	name = S("Minecart Landmark"),
	data = {text = landmark_doc, item="minecart:landmark"},
})

