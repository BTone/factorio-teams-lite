---@alias PlayerIndex uint32

---@class Team
---@field name string The name of the team
---@field builtin boolean Whether the team is a built-in team. Built-in teams cannot be deleted
---@field force LuaForce The force associated with the team
---@field members table<PlayerIndex, LuaPlayer> Team members
---@field admins table<PlayerIndex, LuaPlayer> Team admins
local Team = {}
Team.__index = Team
script.register_metatable("Team", Team)

---Create new team.
---@param name string The name of the team
---@param force? LuaForce The force associated with the team. If not provided, a new force will be created with the same name as the team.
---@param builtin? boolean Whether the team is a built-in team. Built-in teams cannot be deleted. Defaults to false.
function Team.new(name, builtin, force)
    local self = setmetatable({}, Team)

    self.name = name
    self.builtin = builtin or false
    self.force = force or game.create_force(name)
    self.members = {}
    self.admins = {}

    return self
end

---Add a player to the team if they aren't already.
---@param player LuaPlayer
function Team:add_member(player)
    if self.members[player.index] then
        return
    end

    self.members[player.index] = player
    player.force = self.force
end

---Remove a player from the team if they are a member.
---@param player LuaPlayer
function Team:remove_member(player)
    if not self.members[player.index] then
        return
    end

    self.members[player.index] = nil
    player.force = game.forces["player"]
end

local team = {}

team.Team = Team

return team
