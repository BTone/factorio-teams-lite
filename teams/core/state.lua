local fp = require("teams/fp")

---Pure operations on `TeamsState`. Nothing here touches `game` or `storage`.
---@class state
local state = {}

---Name of the built-in force that deleted teams merge into.
state.DEFAULT_FORCE = "player"

---@return TeamsState
function state.empty()
    return { teams = {}, version = 1 }
end

---@param force string
---@param opts TeamOpts?
---@return Team
function state.new_team(force, opts)
    opts = opts or {}
    return {
        force = force,
        display_name = opts.display_name,
        hidden = opts.hidden or false,
        admins = {},
        whitelist = {},
    }
end

---The name players should see for a team.
---@param team Team
---@return string
function state.name(team)
    return team.display_name or team.force
end

---Force names and display names → team. Derived each time, never stored.
---@param s TeamsState
---@return table<string, Team>
function state.index_by_name(s)
    ---@type table<string, Team>
    local idx = {}
    for force, team in pairs(s.teams) do
        idx[force] = team
        if team.display_name then
            idx[team.display_name] = team
        end
    end
    return idx
end

---Find a team by force name or display name.
---@param s TeamsState
---@param name string
---@param include_hidden boolean?
---@return Team?
function state.find(s, name, include_hidden)
    local team = state.index_by_name(s)[name]
    if team and (include_hidden or not team.hidden) then
        return team
    end
    return nil
end

---Get the team for a force name, hidden or not.
---@param s TeamsState
---@param force string
---@return Team?
function state.of_force(s, force)
    return s.teams[force]
end

---Visible teams, sorted by display name.
---@param s TeamsState
---@return Team[]
function state.visible(s)
    local shown = fp.filter(s.teams,
        ---@param t Team
        ---@return boolean
        function(t) return not t.hidden end)
    return fp.sorted_values(shown, state.name)
end

---Add a team. Fails if its force name or display name is already in use.
---@param s TeamsState
---@param team Team
---@return Result<TeamsState>
function state.register(s, team)
    local idx = state.index_by_name(s)
    if idx[team.force] then
        return fp.err("Team name is already taken: " .. team.force)
    end
    if team.display_name and idx[team.display_name] then
        return fp.err("Team name is already taken: " .. team.display_name)
    end
    return fp.ok(fp.update(s, "teams",
        ---@param teams table<string, Team>
        ---@return table<string, Team>
        function(teams) return fp.assoc(teams, team.force, team) end))
end

---Remove the team for a force, if any.
---@param s TeamsState
---@param force string
---@return TeamsState
function state.unregister(s, force)
    if not s.teams[force] then
        return s
    end
    return fp.update(s, "teams",
        ---@param teams table<string, Team>
        ---@return table<string, Team>
        function(teams) return fp.dissoc(teams, force) end)
end

---Copy of `team` without `player_index` in its admin set.
---@param team Team
---@param player_index uint32
---@return Team
local function without_admin(team, player_index)
    if not team.admins[player_index] then
        return team
    end
    return fp.assoc(team, "admins", fp.dissoc(team.admins, player_index))
end

---Remove a player from one team's admin set.
---@param s TeamsState
---@param force string
---@param player_index uint32
---@return TeamsState
function state.forget_admin_in(s, force, player_index)
    local team = s.teams[force]
    if not team then
        return s
    end
    return fp.update(s, "teams",
        ---@param teams table<string, Team>
        ---@return table<string, Team>
        function(teams) return fp.assoc(teams, force, without_admin(team, player_index)) end)
end

---Remove a player from every team's admin set.
---@param s TeamsState
---@param player_index uint32
---@return TeamsState
function state.forget_admin(s, player_index)
    return fp.update(s, "teams",
        ---@param teams table<string, Team>
        ---@return table<string, Team>
        function(teams)
            return fp.map(teams,
                ---@param t Team
                ---@return Team
                function(t) return without_admin(t, player_index) end)
        end)
end

---Fresh state with the built-in forces registered.
---@return TeamsState
function state.initial()
    local s = state.empty()
    ---@type Team[]
    local builtins = {
        state.new_team(state.DEFAULT_FORCE, { display_name = "Default" }),
        state.new_team("enemy", { hidden = true }),
        state.new_team("neutral", { hidden = true }),
    }
    for _, team in ipairs(builtins) do
        local r = state.register(s, team)
        assert(r.ok, "Built-in teams must not collide")
        ---@cast r Ok<TeamsState>
        s = r.value
    end
    return s
end

return state
