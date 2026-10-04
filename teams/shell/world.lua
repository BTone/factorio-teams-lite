---Builds read-only snapshots of `game` for the pure core.
---@class world
local world = {}

---Maximum number of forces Factorio allows, including the built-in ones.
local MAX_FORCES = 64

---@param player LuaPlayer?
---@return boolean
function world.is_valid(player)
    return player ~= nil and player.valid
end

---@param force LuaForce
---@return ForceView
local function force_view(force)
    ---@type ForceView
    local view = {
        name = force.name,
        players = {},
        friends = {},
        ceasefire = {},
        share_chart = force.share_chart,
    }
    for _, player in pairs(force.players) do
        table.insert(view.players, { name = player.name, admin = player.admin })
    end
    for other_name, other in pairs(game.forces) do
        if other ~= force then
            if force.is_friend(other) then
                view.friends[other_name] = true
            end
            if force.get_cease_fire(other) then
                view.ceasefire[other_name] = true
            end
        end
    end
    return view
end

---@param player LuaPlayer
---@return Caller
local function caller_view(player)
    return {
        index = player.index,
        name = player.name,
        admin = player.admin,
        force = player.force.name,
        position = player.position,
        surface = player.surface.name,
    }
end

---Snapshot everything a command might read.
---This is O(forces²), which is fine for rare commands and at most 64 forces.
---@param player_index uint32? nil for the server console
---@return World
function world.snapshot(player_index)
    ---@type table<string, ForceView>
    local forces = {}
    for name, force in pairs(game.forces) do
        forces[name] = force_view(force)
    end

    local player = player_index and game.get_player(player_index) or nil
    return {
        caller = world.is_valid(player) and caller_view(player --[[@as LuaPlayer]]) or nil,
        forces = forces,
        force_count = #game.forces,
        max_forces = MAX_FORCES,
    }
end

return world
