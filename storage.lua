local S = function(pos) if pos then return minetest.pos_to_string(pos) end end
local DAYS_VALID = (30 * 72) -- 30 real days

local storage = minetest.get_mod_storage()

local function data_maintenance()
	minetest.log("info", "[MOD] minecart maintenance")
	local day_count = minetest.get_day_count()
	local tbl = storage:to_table()
	for key,s in pairs(tbl.fields) do
		local val = minetest.deserialize(s)
		if not val.data or not val.best_before or val.best_before < day_count then
			storage:set_string(key, "")
		else
			minetest.log("info", "[minecart] Route: start="..key.." length="..#(val.data))
		end
	end
end
minetest.after(1, data_maintenance)


-- Store data of running carts
minecart.CartsOnRail = {}

for key,val in pairs(minetest.deserialize(storage:get_string("CartsOnRail")) or {}) do
	-- use invalid keys to force the cart spawning
	minecart.CartsOnRail[-key] = val
end

minetest.register_on_shutdown(function()
	data_maintenance()
	storage:set_string("CartsOnRail", minetest.serialize(minecart.CartsOnRail))
end)


--Routes = {
--	spos = {data = {spos, spos, spos}, best_before = ...},
--	spos = {data = {spos, spos, spos}, best_before = ...},
--}
local Routes = {}

function minecart.new_route(key)
	Routes[key] = {data = {}, best_before = minetest.get_day_count() + DAYS_VALID}
	return Routes[key].data
end

function minecart.get_route(key)
	if not Routes[key] then
		Routes[key] = minetest.deserialize(storage:get_string(key))
	end
	if not Routes[key] then
		return minecart.new_route(key)
	end
	Routes[key].best_before = minetest.get_day_count() + DAYS_VALID
	return Routes[key].data
end

function minecart.del_route(key)
	Routes[key] = nil  -- remove from memory
	storage:set_string(key, "") -- and from storage
end

function minecart.store_route(key)
	if Routes[key] then
		storage:set_string(key, minetest.serialize(Routes[key]))
	end
end

