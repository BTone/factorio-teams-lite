---Per-team sidecar data for things LuaForce doesn't store.
---@class TeamData
---@field force LuaForce The force this team wraps; the source of truth for membership
---@field display_name string? Preferred name shown to players; nil means force.name is used
---@field hidden boolean Hidden teams are never listed, shown or targetable by commands
---@field admins table<uint32, true> Set of team-admin player indices (reserved, no commands yet)
---@field whitelist table<string, true> Set of player names allowed to join (reserved, not enforced yet)

---Root of persistent teams data, stored in `storage.teams`.
---@class TeamsStorage
---@field by_force table<uint32, TeamData> force.index → team sidecar
---@field by_name table<string, TeamData> force.name and display_name → the same TeamData (shared reference)

---Maximum number of forces Factorio allows, including the built-in ones.
local MAX_FORCES = 64

local registry = {}

---@return TeamsStorage
local function data()
    return storage.teams
end

---Register a force as a team.
---@param force LuaForce
---@param opts { display_name: string?, hidden: boolean? }?
---@return TeamData
function registry.register(force, opts)
    opts = opts or {}
    local teams = data()

    assert(not teams.by_force[force.index], "Force is already registered: " .. force.name)
    assert(not teams.by_name[force.name], "Team name is already taken: " .. force.name)
    if opts.display_name then
        assert(not teams.by_name[opts.display_name], "Team name is already taken: " .. opts.display_name)
    end

    ---@type TeamData
    local team = {
        force = force,
        display_name = opts.display_name,
        hidden = opts.hidden or false,
        admins = {},
        whitelist = {},
    }

    teams.by_force[force.index] = team
    teams.by_name[force.name] = team
    if team.display_name then
        teams.by_name[team.display_name] = team
    end

    return team
end

---Unregister a team. Takes the force's index and name rather than the force, because the force is already invalid
---by the time `on_forces_merged` fires.
---@param force_index uint32
---@param force_name string
function registry.unregister(force_index, force_name)
    local teams = data()
    local team = teams.by_force[force_index]
    if not team then
        return
    end

    -- The index was reused by a different, newer force; this unregister is stale.
    if team.force.valid and team.force.name ~= force_name then
        return
    end

    teams.by_force[force_index] = nil
    teams.by_name[force_name] = nil
    if team.display_name then
        teams.by_name[team.display_name] = nil
    end
end

---Create storage and register the built-in forces.
function registry.init()
    storage.teams = {
        by_force = {},
        by_name = {},
    }

    registry.register(game.forces["player"], { display_name = "Default" })
    registry.register(game.forces["enemy"], { hidden = true })
    registry.register(game.forces["neutral"], { hidden = true })
end

---Initialize storage if it hasn't been yet. Safe to call any time `game` is available.
function registry.ensure()
    if storage.teams then
        return
    end
    registry.init()
    game.print("Teams initialized")
end

---Get the team for a force, if the force is a team.
---@param force LuaForce
---@return TeamData?
function registry.get(force)
    return data().by_force[force.index]
end

---Get the team a player is on, if any.
---@param player LuaPlayer
---@return TeamData?
function registry.of_player(player)
    return registry.get(player.force)
end

---Find a team by force name or display name.
---@param name string
---@param include_hidden boolean?
---@return TeamData?
function registry.find(name, include_hidden)
    local team = data().by_name[name]
    if team and team.hidden and not include_hidden then
        return nil
    end
    return team
end

---The name players should see for a team.
---@param team TeamData
---@return string
function registry.name(team)
    return team.display_name or team.force.name
end

---Create a new force and register it as a team.
---@param force_name string
---@return TeamData? team
---@return string? error
function registry.create(force_name)
    if force_name == "" then
        return nil, "Missing team name"
    end
    if data().by_name[force_name] or game.forces[force_name] then
        return nil, string.format("Team %s already exists", force_name)
    end
    if #game.forces >= MAX_FORCES then
        return nil, "Too many teams"
    end

    return registry.register(game.create_force(force_name))
end

---Delete a team, moving its players and entities to the default team.
---@param team TeamData
---@return boolean ok
---@return string? error
function registry.delete(team)
    local force = team.force
    local default_force = game.forces["player"]
    if force == default_force then
        return false, string.format("Team %s cannot be deleted", registry.name(team))
    end

    registry.unregister(force.index, force.name)
    game.merge_forces(force, default_force)
    return true
end

---Iterate over all teams.
---@param include_hidden boolean?
---@return fun(): TeamData?
function registry.each(include_hidden)
    local by_force = data().by_force
    local index = nil
    return function()
        local team
        repeat
            index, team = next(by_force, index)
        until index == nil or include_hidden or not team.hidden
        return team
    end
end

return registry
