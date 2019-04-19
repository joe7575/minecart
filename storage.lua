local S = function(pos) if pos then return minetest.pos_to_string(pos) end end

local storage = minetest.get_mod_storage()

local function data_maintenance()
	print("[MOD] minecart maintenance")
	local day_count = minetest.get_day_count()
	local tbl = storage:to_table()
	for key,s in pairs(tbl.fields) do
		local val = minetest.deserialize(s)
		--print(key, dump(val))
		if not val.data or not val.best_before or val.best_before < day_count then
			storage:set_string(key, "")
		else
			print(key, val.best_before, #(val.data))
		end
	end
end
minetest.after(1, data_maintenance)

--Routes = {
--	spos = {data = {spos, spos, spos}, best_before = ...},
--	spos = {data = {spos, spos, spos}, best_before = ...},
--}
local Routes = {}

local DAYS_VALID = (30 * 72) -- 30 real days

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
