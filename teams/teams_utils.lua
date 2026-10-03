---Check if LuaEntity / LuaPlayer is valid
---@param entity LuaEntity | LuaPlayer | nil
---@return boolean
function is_valid(entity)
    if entity and entity.valid then
        return true
    end
    return false
end

---Check if player is a valid admin
---@param player LuaPlayer?
---@return boolean
function is_valid_admin(player)
    return is_valid(player) and player.admin
end

local teams_utils = {
    is_valid = is_valid,
    is_valid_admin = is_valid_admin,
}

return teams_utils