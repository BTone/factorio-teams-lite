local S = require("teams/core/state")

---Pure migrations from older storage layouts.
---@class migrations
local migrations = {}

---Register the forces of Teams Lite teams. Teams Lite already put members on their team's force, so membership
---carries over without changes.
---@param s TeamsState
---@param lite LiteTeamView[]
---@return TeamsState new_state
---@return string[] messages Lines to broadcast to all players
function migrations.teams_lite(s, lite)
    ---@type string[]
    local messages = { "Migrating Teams Lite to Teams..." }

    for _, lite_team in ipairs(lite) do
        -- Already a team: the built-in player force (Teams Lite's "Default") is registered by S.initial.
        if not S.of_force(s, lite_team.force) then
            local display_name = lite_team.name ~= lite_team.force and lite_team.name or nil
            local team = S.new_team(lite_team.force, { display_name = display_name })
            local r = S.register(s, team)
            if r.ok then
                ---@cast r Ok<TeamsState>
                s = r.value
                table.insert(messages,
                    string.format("Migrated team %s (%d members)", S.name(team), lite_team.member_count))
            else
                table.insert(messages, string.format("Skipping team %s: name already taken", lite_team.name))
            end
        end
    end

    table.insert(messages, "Migration complete")
    return s, messages
end

return migrations
