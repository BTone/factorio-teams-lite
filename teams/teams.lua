local S = require("teams/core/state")
local reducers = require("teams/core/events")
local migrations = require("teams/core/migrations")
local command_specs = require("teams/core/commands")
local world = require("teams/shell/world")
local run_effects = require("teams/shell/effects")

---Saves from Teams Lite hold `LiteTeam` tables in `storage.teams_lite`. Factorio refuses to load a save whose
---storage references an unregistered metatable, so the name must stay registered until no such saves remain.
script.register_metatable("LiteTeam", {})

---Teams Lite storage layout (see teams-lite.lua before commit 5f31529).
---@class LiteTeam
---@field name string Team name; the force name, except "Default" which wraps the player force
---@field force LuaForce
---@field members table<uint32, LuaPlayer>
---@field builtin boolean

---@class TeamsLiteStorage
---@field initialized boolean
---@field team_members table<uint32, LiteTeam>
---@field teams table<string, LiteTeam>
---@field default_team LiteTeam?

---@class (partial) storage
---@field teams TeamsState?
---@field teams_lite TeamsLiteStorage?

---Current state, initializing it if this script was added to an existing save (where on_init never runs).
---@return TeamsState
local function current()
    if not storage.teams then
        storage.teams = S.initial()
        game.print("Teams initialized")
    end
    return storage.teams --[[@as TeamsState]]
end

---Run a reducer against current state, save the result and carry out its effects.
---@generic E
---@param reducer Reducer<E>
---@param ev E
local function step(reducer, ev)
    local new_state, effects = reducer(current(), ev)
    storage.teams = new_state
    run_effects(effects)
end

---@param out fun(message: string)
---@param output CommandOutput?
local function print_output(out, output)
    if type(output) == "table" then
        for _, line in ipairs(output) do
            out(line)
        end
    elseif output then
        out(output)
    end
end

---Run a command, then carry out its effects before saving its state, so a failing effect leaves state untouched.
---@param spec CommandSpec
---@param data CustomCommandData
---@return Result<CommandOutcome>
local function execute(spec, data)
    local result = spec.run(current(), world.snapshot(data.player_index), data.parameter)
    if result.ok then
        ---@cast result Ok<CommandOutcome>
        run_effects(result.value.effects)
        if result.value.state then
            storage.teams = result.value.state
        end
    end
    return result
end

---Run a pure command spec on behalf of a console command invocation.
---@param spec CommandSpec
---@param data CustomCommandData
local function dispatch(spec, data)
    local player = data.player_index and game.get_player(data.player_index) or nil
    ---@type fun(message: string)
    local out = player and player.print or print

    local ok, result = xpcall(execute, debug.traceback, spec, data)
    if not ok then
        log(string.format("Error in /%s: %s", spec.name, result))
        out("Internal error, see the server log for details")
        return
    end
    ---@cast result Result<CommandOutcome>

    if not result.ok then
        ---@cast result Err
        out(result.error)
        return
    end
    ---@cast result Ok<CommandOutcome>
    print_output(out, result.value.output)
end

---Flatten Teams Lite storage into plain views, dropping teams whose force is gone.
---@param lite TeamsLiteStorage
---@return LiteTeamView[]
local function lite_views(lite)
    ---@type LiteTeamView[]
    local views = {}
    for _, lite_team in pairs(lite.teams or {}) do
        local force = lite_team.force
        if force and force.valid then
            table.insert(views, { name = lite_team.name, force = force.name, member_count = #force.players })
        end
    end
    return views
end

---@param event EventData.on_player_joined_game
local function on_player_joined_game(event)
    local player = game.get_player(event.player_index)
    if not world.is_valid(player) then
        return
    end
    ---@cast player LuaPlayer
    step(reducers.player_joined, { player_index = player.index, name = player.name, admin = player.admin })
end

---@param event EventData.on_player_changed_force
local function on_player_changed_force(event)
    if not event.force.valid then
        return
    end
    step(reducers.player_changed_force, { player_index = event.player_index, old_force = event.force.name })
end

---@param event EventData.on_player_removed
local function on_player_removed(event)
    step(reducers.player_removed, { player_index = event.player_index })
end

---@param event EventData.on_forces_merged
local function on_forces_merged(event)
    step(reducers.forces_merged, { source_name = event.source_name })
end

---If necessary, initialize and migrate on the first tick after the script is added to an existing save, where
---on_init never runs.
---@param event EventData.on_tick
local function on_tick(event)
    local s = current()
    local lite = storage.teams_lite
    if not lite then
        return
    end
    storage.teams_lite = nil

    local new_state, messages = migrations.teams_lite(s, lite_views(lite))
    storage.teams = new_state
    for _, message in ipairs(messages) do
        game.print(message)
    end
end

local teams = {}

teams.on_init = function()
    storage.teams = S.initial()
end

teams.add_commands = function()
    for _, spec in ipairs(command_specs) do
        commands.add_command(spec.name, spec.help,
            ---@param data CustomCommandData
            function(data) dispatch(spec, data) end)
    end
end

---@type event_handler.events
teams.events = {
    [defines.events.on_player_joined_game] = on_player_joined_game,
    [defines.events.on_player_changed_force] = on_player_changed_force,
    [defines.events.on_player_removed] = on_player_removed,
    [defines.events.on_forces_merged] = on_forces_merged,
    [defines.events.on_tick] = on_tick,
}

return teams
