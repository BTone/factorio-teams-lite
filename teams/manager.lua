local team = require("team")

local Team = team.Team

---Team manager
---@class Manager
---@field team_members table<PlayerIndex, Team> Mapping of player index to team
---@field teams table<string, Team> List of teams
---@field default_team Team Default team
local Manager = {}
Manager.__index = Manager
script.register_metatable("Manager", Manager)

local function new()
    local self = setmetatable({}, Manager)

    self.team_members = {}
    self.teams = {}
    self.default_team = self:create_team("Default", true, game.forces["player"])

    return self
end

---Singleton instance
---@type Manager?
local instance = nil

---Get the singleton instance of the Manager. If it doesn't exist, it will be created.
---@return Manager
function Manager.instance()
    if not instance then
        if storage.teams and storage.teams.manager then
            instance = storage.teams.manager
        else
            instance = new()
        end
    end
    ---@cast instance Manager
    return instance
end

---Create a new team.
---@param name string The name of the team
---@param builtin boolean? Whether the team is a built-in team. Built-in teams cannot be deleted. Defaults to false.
---@param force LuaForce? The force associated with the team. If not provided, a new force will be created with the same name as the team.
---@return Team
function Manager:create_team(name, builtin, force)
    if self.teams[name] then
        return self.teams[name]
    end

    local team = Team.new(name, builtin, force)
    self.teams[name] = team
    return team
end

---Delete team, optionally adding its members to the default team.
---@param team Team The team to delete.
---@param add_to_default boolean? Whether to add the members of the deleted team to the default team. Defaults to true.
function Manager:delete_team(team, add_to_default)
    add_to_default = add_to_default == nil and true or add_to_default

    if team.builtin then
        return
    end

    -- Remove all members from the team
    for _, player in pairs(team.members) do
        self:remove_member(player)

        -- Add the player to the default team if specified
        if add_to_default then
            self:add_member(player, self.default_team)
        end
    end

    -- Destroy the force associated with the team
    game.merge_forces(team.force, self.default_team.force)

    -- Remove the team from the list of teams
    self.teams[team.name] = nil
end

---Get the team that a player belongs to, if any.
---@param player LuaPlayer The player to get the team for.
---@return Team?
function Manager:get_team_by_player(player)
    return self.team_members[player.index]
end

---Get a team by its name, if it exists.
---@param name string The name of the team to get.
---@return Team?happen.
function Manager:get_team_by_name(name)
    return self.teams[name]
end

---Remove a player from their team if they are in one.
---@param player LuaPlayer The player to remove from the team.
function Manager:remove_member(player)
    local team = self:get_team_by_player(player)
    if not team then
        return
    end

    team:remove_member(player)

    if self.team_members[player.index] then
        self.team_members[player.index] = nil
    end
end

---Add a player to a team. If the player is already in a team, they will be removed from that team first.
---@param player LuaPlayer The player to add to the team.
---@param team Team The team to add the player to.
function Manager:add_member(player, team)
    local current_team = self:get_team_by_player(player)

    if current_team == team then
        return
    end

    -- Remove the player from their current team if they are in one
    if current_team then
        self:remove_member(player)
    end

    team:add_member(player)
    self.team_members[player.index] = team
end

local manager = {}

manager.Manager = Manager

return manager
