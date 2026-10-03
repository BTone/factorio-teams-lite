local registry = require("registry")

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

local migrations = {}

---Register the forces of Teams Lite teams. Teams Lite already put members on their team's force, so membership
---carries over without changes.
local function migrate_teams_lite()
    ---@type TeamsLiteStorage
    local teams_lite = storage.teams_lite
    storage.teams_lite = nil

    game.print("Migrating Teams Lite to Teams...")

    for _, lite_team in pairs(teams_lite.teams or {}) do
        local force = lite_team.force
        -- Already a team: the built-in player force (Teams Lite's "Default") is registered by registry.init.
        if force and force.valid and not registry.get(force) then
            local display_name = lite_team.name ~= force.name and lite_team.name or nil
            if registry.find(force.name, true) or (display_name and registry.find(display_name, true)) then
                game.print(string.format("Skipping team %s: name already taken", lite_team.name))
            else
                local team = registry.register(force, { display_name = display_name })
                game.print(string.format("Migrated team %s (%d members)", registry.name(team), #force.players))
            end
        end
    end

    game.print("Migration complete")
end

---Run any pending migrations. Requires storage.teams to be initialized.
function migrations.run()
    if storage.teams_lite then
        migrate_teams_lite()
    end
end

return migrations
