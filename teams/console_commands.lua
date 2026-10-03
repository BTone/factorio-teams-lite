local util = require("util")
local registry = require("registry")
local teams_utils = require("teams_utils")

---Error thrown for expected failures, whose message is shown to the caller as-is.
---@class UserError
---@field user_error string

---Abort the current command with a message for the caller.
---@param message string
local function fail(message)
    error({ user_error = message })
end

---Get player from command data, or nil if called from the server console.
---@param data CustomCommandData
---@return LuaPlayer?
local function command_player(data)
    return data.player_index and game.get_player(data.player_index) or nil
end

---Trim leading and trailing whitespace from a command parameter.
---@param parameter string?
---@return string
local function trim(parameter)
    return parameter and parameter:match("^%s*(.-)%s*$") or ""
end

---@param player LuaPlayer?
---@return LuaPlayer
local function require_player(player)
    if not player then
        fail("You must be a player to use this command")
    end
    ---@cast player LuaPlayer
    return player
end

---Fail unless the caller is an admin. The server console (no player) counts as admin.
---@param player LuaPlayer?
local function require_admin(player)
    if player and not teams_utils.is_valid_admin(player) then
        fail("You must be an admin to use this command")
    end
end

---Find a visible team by name or fail.
---@param parameter string?
---@return TeamData
local function require_team(parameter)
    local name = trim(parameter)
    if name == "" then
        fail("Missing team name")
    end

    local team = registry.find(name)
    if not team then
        fail(string.format("Team %s does not exist", name))
    end
    ---@cast team TeamData
    return team
end

---Get the caller's own visible team or fail.
---@param player LuaPlayer
---@return TeamData
local function require_own_team(player)
    local team = registry.of_player(player)
    if not team or team.hidden then
        fail("You are not in a team")
    end
    ---@cast team TeamData
    return team
end

---@class ConsoleCommand
---@field name string The name of the command
---@field help string The help text for the command
---@field handler fun(data: CustomCommandData): string | string[] | nil The handler function for the command

---@type ConsoleCommand[]
local console_commands = {
    {
        name = "teams-list",
        help = "List teams",
        handler = function(data)
            local lines = {}

            for team in registry.each() do
                local players = team.force.players

                local line = string.format("%s (%d members)", registry.name(team), #players)
                if #players > 0 then
                    line = line .. ":"
                end
                table.insert(lines, line)

                for _, member in pairs(players) do
                    line = string.format("    - %s", member.name)
                    if member.admin then
                        line = line .. " (admin)"
                    end
                    table.insert(lines, line)
                end
            end

            return lines
        end
    },
    {
        name = "teams-create",
        help = "<name> - Create a new team",
        handler = function(data)
            require_admin(command_player(data))

            local team, err = registry.create(trim(data.parameter))
            if not team then
                fail(err --[[@as string]])
            end
            ---@cast team TeamData

            return string.format("Team %s created", registry.name(team))
        end
    },
    {
        name = "teams-delete",
        help = "<team> - Delete a team, moving its members to the default team",
        handler = function(data)
            require_admin(command_player(data))

            local team = require_team(data.parameter)
            local name = registry.name(team)

            local ok, err = registry.delete(team)
            if not ok then
                fail(err --[[@as string]])
            end

            return string.format("Team %s deleted", name)
        end
    },
    {
        name = "teams-join",
        help = "<team> - Join a team",
        handler = function(data)
            local player = require_player(command_player(data))
            local team = require_team(data.parameter)

            if registry.of_player(player) == team then
                return
            end

            player.force = team.force
            return string.format("Player %s joined team %s", player.name, registry.name(team))
        end
    },
    {
        name = "teams-set-spawn",
        help = "Set the spawn point for your team",
        handler = function(data)
            local player = require_player(command_player(data))
            require_admin(player)
            local team = require_own_team(player)

            local spawn_position = player.position
            team.force.set_spawn_position(spawn_position, player.surface)
            return string.format("Spawn point for team %s set to %s", registry.name(team),
                util.positiontostr(spawn_position))
        end
    },
    {
        name = "teams-diplomacy",
        help = "Show diplomacy status between our team and other teams",
        handler = function(data)
            local player = require_player(command_player(data))
            local team = require_own_team(player)

            local friends = {}
            local ceasefires = {}

            for other_team in registry.each() do
                if other_team ~= team then
                    if team.force.is_friend(other_team.force) then
                        table.insert(friends, registry.name(other_team))
                    end
                    if team.force.get_cease_fire(other_team.force) then
                        table.insert(ceasefires, registry.name(other_team))
                    end
                end
            end

            local lines = {}

            if #friends > 0 then
                table.insert(lines, string.format("Friends: %s", table.concat(friends, ", ")))
            end

            if #ceasefires > 0 then
                table.insert(lines, string.format("Ceasefires: %s", table.concat(ceasefires, ", ")))
            end

            return lines
        end
    },
    {
        name = "teams-toggle-friend",
        help = "<team> - Toggle friendship with another team",
        handler = function(data)
            local player = require_player(command_player(data))
            require_admin(player)
            local team = require_own_team(player)
            local other_team = require_team(data.parameter)

            if team == other_team then
                return
            end

            local new_status = not team.force.is_friend(other_team.force)
            team.force.set_friend(other_team.force, new_status)

            return string.format("Team %s is %s friends with team %s", registry.name(team),
                new_status and "now" or "no longer", registry.name(other_team))
        end
    },
    {
        name = "teams-toggle-ceasefire",
        help = "<team> - Toggle cease-fire with another team",
        handler = function(data)
            local player = require_player(command_player(data))
            require_admin(player)
            local team = require_own_team(player)
            local other_team = require_team(data.parameter)

            if team == other_team then
                return
            end

            local new_status = not team.force.get_cease_fire(other_team.force)
            team.force.set_cease_fire(other_team.force, new_status)

            return string.format("Team %s is %s ceasing fire with team %s", registry.name(team),
                new_status and "now" or "no longer", registry.name(other_team))
        end
    },
    {
        name = "teams-toggle-chart",
        help = "Toggle chart sharing",
        handler = function(data)
            local player = require_player(command_player(data))
            require_admin(player)
            local team = require_own_team(player)

            local new_status = not team.force.share_chart
            team.force.share_chart = new_status

            return string.format("Team %s is %s sharing chart", registry.name(team),
                new_status and "now" or "no longer")
        end
    },
}

---Pass user errors through untouched; turn anything else into a traceback for the log.
---@param err any
---@return UserError | { internal: string }
local function on_error(err)
    if type(err) == "table" and err.user_error then
        return err
    end
    return { internal = debug.traceback(tostring(err), 2) }
end

return {
    add_commands = function()
        for _, command in pairs(console_commands) do
            commands.add_command(command.name, command.help, function(data)
                local player = command_player(data)
                local print_func = player and player.print or print

                registry.ensure()
                local ok, result = xpcall(command.handler, on_error, data)

                if not ok then
                    if result.user_error then
                        print_func(result.user_error)
                    else
                        log(string.format("Error in /%s: %s", command.name, result.internal))
                        print_func("Internal error, see the server log for details")
                    end
                    return
                end

                if type(result) == "table" then
                    for _, line in pairs(result) do
                        print_func(line)
                    end
                elseif result then
                    print_func(result)
                end
            end)
        end
    end,
}
