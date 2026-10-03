local util = require("util")
local manager = require("manager")
local teams_utils = require("teams_utils")

local Manager = manager.Manager

---Get the print function for a player or the global print function if no player is specified.
---@param data CustomCommandData
local function get_print_func(data)
    if data.player_index then
        return game.players[data.player_index].print
    end
    return print
end

---Get player from command data, or nil if called from the server console.
---@param data CustomCommandData
---@return LuaPlayer?
local function get_command_player(data)
    return data.player_index and game.get_player(data.player_index)
end

---@param player LuaPlayer?
local function assert_command_admin(player)
    if not teams_utils.is_valid_admin(player) then
        error("You must be an admin to use this command", 0)
    end
end

---@param player LuaPlayer?
local function assert_command_player(player)
    if not player then
        error("You must be a player to use this command", 0)
    end
end

---@param team_name string?
local function assert_team_name(team_name)
    if not team_name or team_name == "" then
        error("Missing team name", 0)
    end
end

---@param manager Manager
---@param team_name string?
local function assert_team_exists(manager, team_name)
    assert_team_name(team_name)
    ---@cast team_name string
    local team = manager:get_team_by_name(team_name)
    if not team then
        error(string.format("Team %s does not exist", team_name), 0)
    end
end

---@param manager Manager
---@param player LuaPlayer
local function assert_player_in_team(manager, player)
    local team = manager:get_team_by_player(player)
    if not team then
        error("You are not in a team", 0)
    end
end

---@class ConsoleCommand
---@field name string The name of the command
---@field help string The help text for the command
---@field handler fun(data: CustomCommandData): string? The handler function for the command

---@type ConsoleCommand[]
local console_commands = {
    {
        name = "teams-list",
        help = "List teams",
        handler = function(data)
            local manager = Manager.instance()
            local lines = {}
            local line = ""

            for _, team in pairs(manager.teams) do
                local num_members = table_size(team.members)

                line = string.format("%s (%d members)", team.name, num_members)
                if num_members > 0 then
                    line = line .. ":"
                end
                table.insert(lines, line)

                for _, member in pairs(team.members) do
                    line = string.format("    - %s", member.name)
                    if member.admin then
                        line = line .. " (admin)"
                    end
                    table.insert(lines, line)
                end
            end

            return table.concat(lines, "\n")
        end
    },
    {
        name = "teams-create",
        help = "Create a new team",
        handler = function(data)
            local player = get_command_player(data)
            if player then
                assert_command_admin(player)
            end

            local manager = Manager.instance()
            local team_name = data.parameter
            assert_team_name(team_name)
            ---@cast team_name string

            if  manager:get_team_by_name(team_name) then
                return
            end

            manager:create_team(team_name)
            return string.format("Team %s created", team_name)
        end
    },
    {
        name = "teams-delete",
        help = "Delete a team",
        handler = function(data)
            local player = get_command_player(data)
            if player then
                assert_command_admin(player)
            end

            local manager = Manager.instance()
            local team_name = data.parameter
            assert_team_exists(manager, team_name)
            ---@cast team_name string
            local team = manager:get_team_by_name(team_name)
            ---@cast team Team

            if team.builtin then
                error(string.format("Team %s is a built-in team and cannot be deleted", team_name), 0)
            end

            manager:delete_team(team)
            return string.format("Team %s deleted", team_name)
        end
    },
    {
        name = "teams-join",
        help = "Join a team",
        handler = function(data)
            local player = get_command_player(data)
            assert_command_player(player)
            ---@cast player LuaPlayer

            local manager = Manager.instance()
            local team_name = data.parameter
            assert_team_exists(manager, team_name)
            ---@cast team_name string
            local team = manager:get_team_by_name(team_name)
            ---@cast team Team

            local current_team = manager:get_team_by_player(player)
            if current_team == team then
                return
            end

            manager:add_member(player, team)
            return string.format("Player %s joined team %s", player.name, team.name)
        end
    },
    {
        name = "teams-set-spawn",
        help = "Set the spawn point for your team",
        handler = function(data)
            local player = get_command_player(data)
            assert_command_admin(player)
            ---@cast player LuaPlayer

            local manager = Manager.instance()
            assert_player_in_team(manager, player)
            local team = manager:get_team_by_player(player)
            ---@cast team Team

            local spawn_position = player.position
            team.force.set_spawn_position(spawn_position, player.surface)
            return string.format("Spawn point for team %s set to %s", team.name, util.positiontostr(spawn_position))
        end
    },
    {
        name = "teams-diplomacy",
        help = "Show diplomacy status between our team and other teams",
        handler = function(data)
            local player = get_command_player(data)
            assert_command_player(player)
            ---@cast player LuaPlayer

            local manager = Manager.instance()
            assert_player_in_team(manager, player)
            local team = manager:get_team_by_player(player)
            ---@cast team Team

            local friends = {}
            local ceasefires = {}

            for _, other_team in pairs(manager.teams) do
                if other_team ~= team then
                    if team.force.is_friend(other_team.force) then
                        table.insert(friends, other_team.name)
                    end
                    if team.force.get_cease_fire(other_team.force) then
                        table.insert(ceasefires, other_team.name)
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

            return table.concat(lines, "\n")
        end
    },
    {
        name = "teams-toggle-friend",
        help = "Toggle friendship with another team",
        handler = function(data)
            local player = get_command_player(data)
            assert_command_admin(player)
            ---@cast player LuaPlayer

            local manager = Manager.instance()
            assert_player_in_team(manager, player)
            local team = manager:get_team_by_player(player)
            ---@cast team Team

            local other_team_name = data.parameter
            assert_team_exists(manager, other_team_name)
            ---@cast other_team_name string
            local other_team = manager:get_team_by_name(other_team_name)
            ---@cast other_team Team

            if team == other_team then
                return
            end

            local status = team.force.is_friend(other_team.force)
            local new_status = not status
            team.force.set_friend(other_team.force, new_status)

            return string.format("Team %s is %s friends with team %s", team.name, new_status and "now" or "no longer",
                other_team.name)
        end
    },
    {
        name = "teams-toggle-ceasefire",
        help = "Toggle cease-fire with another team",
        handler = function(data)
            local player = get_command_player(data)
            assert_command_admin(player)
            ---@cast player LuaPlayer

            local manager = Manager.instance()
            assert_player_in_team(manager, player)
            local team = manager:get_team_by_player(player)
            ---@cast team Team

            local other_team_name = data.parameter
            assert_team_exists(manager, other_team_name)
            ---@cast other_team_name string
            local other_team = manager:get_team_by_name(other_team_name)
            ---@cast other_team Team

            if team == other_team then
                return
            end

            local status = team.force.get_cease_fire(other_team.force)
            local new_status = not status
            team.force.set_cease_fire(other_team.force, new_status)

            return string.format("Team %s is %s ceasing fire with team %s", team.name,
                new_status and "now" or "no longer",
                other_team.name)
        end
    },
    {
        name = "teams-toggle-chart",
        help = "Toggle chart sharing",
        handler = function(data)
            local player = get_command_player(data)
            assert_command_admin(player)
            ---@cast player LuaPlayer

            local manager = Manager.instance()
            assert_player_in_team(manager, player)
            local team = manager:get_team_by_player(player)
            ---@cast team Team

            local status = team.force.share_chart
            local new_status = not status
            team.force.share_chart = new_status

            return string.format("Team %s is %s sharing chart", team.name, new_status and "now" or "no longer")
        end
    }

}

return {
    add_commands = function()
        for _, command in pairs(console_commands) do
            commands.add_command(command.name, command.help, function(data)
                local print_func = get_print_func(data)
                local success, result = pcall(command.handler, data)
                if success then
                    if result then
                        print_func(result)
                    end
                else
                    print_func("Error: " .. result)
                end
            end)
        end
    end,
}
