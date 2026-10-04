local util = require("util")
local fp = require("teams/fp")
local S = require("teams/core/state")

---Trim leading and trailing whitespace from a command parameter.
---@param parameter string?
---@return string
local function trim(parameter)
    return parameter and parameter:match("^%s*(.-)%s*$") or ""
end

---@param now boolean
---@return string
local function now_or_no_longer(now)
    return now and "now" or "no longer"
end

------------------------------------------------------------------------------------------------------------------------
-- Guards: small Result-returning checks that commands compose
------------------------------------------------------------------------------------------------------------------------

---@param w World
---@return Result<Caller>
local function need_player(w)
    if not w.caller then
        return fp.err("You must be a player to use this command")
    end
    return fp.ok(w.caller)
end

---The server console (no caller) counts as admin.
---@param w World
---@return Result<Caller?>
local function need_admin(w)
    if w.caller and not w.caller.admin then
        return fp.err("You must be an admin to use this command")
    end
    return fp.ok(w.caller)
end

---@param name string
---@return Result<string>
local function need_name(name)
    if name == "" then
        return fp.err("Missing team name")
    end
    return fp.ok(name)
end

---Find a visible team by name.
---@param s TeamsState
---@param arg string?
---@return Result<Team>
local function need_team(s, arg)
    return fp.and_then(need_name(trim(arg)),
        ---@param name string
        ---@return Result<Team>
        function(name)
            local team = S.find(s, name)
            if not team then
                return fp.err(string.format("Team %s does not exist", name))
            end
            return fp.ok(team)
        end)
end

---The caller's own visible team.
---@param s TeamsState
---@param caller Caller
---@return Result<Team>
local function need_own_team(s, caller)
    local team = S.of_force(s, caller.force)
    if not team or team.hidden then
        return fp.err("You are not in a team")
    end
    return fp.ok(team)
end

---The caller must be a player, an admin and on a visible team.
---@param s TeamsState
---@param w World
---@return Result<Team>
local function need_own_team_as_admin(s, w)
    return fp.chain(need_player(w),
        ---@return Result<Caller?>
        function() return need_admin(w) end,
        ---@param caller Caller
        ---@return Result<Team>
        function(caller) return need_own_team(s, caller) end)
end

------------------------------------------------------------------------------------------------------------------------
-- Combinators
------------------------------------------------------------------------------------------------------------------------

---@alias RelationField "friends" | "ceasefire"

---Build a "toggle a relation with another team" command.
---@param field RelationField Which ForceView set to read the current status from
---@param verb string Phrase used in the output, e.g. "friends with"
---@param make_effect fun(force: string, other: string, value: boolean): Effect
---@return CommandRun
local function toggle_relation(field, verb, make_effect)
    ---@type CommandRun
    return function(s, w, arg)
        return fp.chain(need_own_team_as_admin(s, w),
            ---@param team Team
            ---@return Result<CommandOutcome>
            function(team)
                return fp.and_then(need_team(s, arg),
                    ---@param other Team
                    ---@return Result<CommandOutcome>
                    function(other)
                        if other == team then
                            return fp.ok({})
                        end
                        local now = not w.forces[team.force][field][other.force]
                        ---@type CommandOutcome
                        local outcome = {
                            effects = { make_effect(team.force, other.force, now) },
                            output = string.format("Team %s is %s %s team %s",
                                S.name(team), now_or_no_longer(now), verb, S.name(other)),
                        }
                        return fp.ok(outcome)
                    end)
            end)
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------------------------------------------------------

---@type CommandSpec[]
local command_specs = {
    {
        name = "teams-list",
        help = "List teams",
        run = function(s, w)
            ---@type string[]
            local lines = {}
            for _, team in ipairs(S.visible(s)) do
                local players = w.forces[team.force].players
                table.insert(lines, string.format("%s (%d members)%s", S.name(team), #players,
                    #players > 0 and ":" or ""))
                for _, p in ipairs(players) do
                    table.insert(lines, "    - " .. p.name .. (p.admin and " (admin)" or ""))
                end
            end
            return fp.ok({ output = lines })
        end,
    },
    {
        name = "teams-create",
        help = "<name> - Create a new team",
        run = function(s, w, arg)
            local name = trim(arg)
            return fp.chain(need_admin(w),
                ---@return Result<string>
                function() return need_name(name) end,
                ---@param n string
                ---@return Result<TeamsState>
                function(n)
                    if w.forces[n] then
                        return fp.err(string.format("Team %s already exists", n))
                    end
                    if w.force_count >= w.max_forces then
                        return fp.err("Too many teams")
                    end
                    return S.register(s, S.new_team(n))
                end,
                ---@param new_state TeamsState
                ---@return Result<CommandOutcome>
                function(new_state)
                    ---@type Effect.CreateForce
                    local effect = { kind = "create_force", name = name }
                    return fp.ok({
                        state = new_state,
                        effects = { effect },
                        output = string.format("Team %s created", name),
                    })
                end)
        end,
    },
    {
        name = "teams-delete",
        help = "<team> - Delete a team, moving its members to the default team",
        run = function(s, w, arg)
            return fp.chain(need_admin(w),
                ---@return Result<Team>
                function() return need_team(s, arg) end,
                ---@param team Team
                ---@return Result<CommandOutcome>
                function(team)
                    if team.force == S.DEFAULT_FORCE then
                        return fp.err(string.format("Team %s cannot be deleted", S.name(team)))
                    end
                    ---@type Effect.MergeForces
                    local effect = { kind = "merge_forces", from = team.force, into = S.DEFAULT_FORCE }
                    return fp.ok({
                        state = S.unregister(s, team.force),
                        effects = { effect },
                        output = string.format("Team %s deleted", S.name(team)),
                    })
                end)
        end,
    },
    {
        name = "teams-join",
        help = "<team> - Join a team",
        run = function(s, w, arg)
            return fp.chain(need_player(w),
                ---@return Result<Team>
                function() return need_team(s, arg) end,
                ---@param team Team
                ---@return Result<CommandOutcome>
                function(team)
                    local caller = w.caller --[[@as Caller]]
                    if caller.force == team.force then
                        return fp.ok({})
                    end
                    ---@type Effect.SetForce
                    local effect = { kind = "set_force", player = caller.index, force = team.force }
                    return fp.ok({
                        effects = { effect },
                        output = string.format("Player %s joined team %s", caller.name, S.name(team)),
                    })
                end)
        end,
    },
    {
        name = "teams-set-spawn",
        help = "Set the spawn point for your team",
        run = function(s, w)
            return fp.and_then(need_own_team_as_admin(s, w),
                ---@param team Team
                ---@return Result<CommandOutcome>
                function(team)
                    local caller = w.caller --[[@as Caller]]
                    ---@type Effect.SetSpawn
                    local effect = {
                        kind = "set_spawn",
                        force = team.force,
                        position = caller.position,
                        surface = caller.surface,
                    }
                    return fp.ok({
                        effects = { effect },
                        output = string.format("Spawn point for team %s set to %s", S.name(team),
                            util.positiontostr(caller.position)),
                    })
                end)
        end,
    },
    {
        name = "teams-diplomacy",
        help = "Show diplomacy status between our team and other teams",
        run = function(s, w)
            return fp.chain(need_player(w),
                ---@param caller Caller
                ---@return Result<Team>
                function(caller) return need_own_team(s, caller) end,
                ---@param team Team
                ---@return Result<CommandOutcome>
                function(team)
                    local view = w.forces[team.force]
                    ---@type string[]
                    local friends = {}
                    ---@type string[]
                    local ceasefires = {}
                    for _, other in ipairs(S.visible(s)) do
                        if other ~= team then
                            if view.friends[other.force] then
                                table.insert(friends, S.name(other))
                            end
                            if view.ceasefire[other.force] then
                                table.insert(ceasefires, S.name(other))
                            end
                        end
                    end

                    ---@type string[]
                    local lines = {}
                    if #friends > 0 then
                        table.insert(lines, string.format("Friends: %s", table.concat(friends, ", ")))
                    end
                    if #ceasefires > 0 then
                        table.insert(lines, string.format("Ceasefires: %s", table.concat(ceasefires, ", ")))
                    end
                    return fp.ok({ output = lines })
                end)
        end,
    },
    {
        name = "teams-toggle-friend",
        help = "<team> - Toggle friendship with another team",
        run = toggle_relation("friends", "friends with",
            ---@param force string
            ---@param other string
            ---@param value boolean
            ---@return Effect.SetFriend
            function(force, other, value)
                return { kind = "set_friend", force = force, other = other, value = value }
            end),
    },
    {
        name = "teams-toggle-ceasefire",
        help = "<team> - Toggle cease-fire with another team",
        run = toggle_relation("ceasefire", "ceasing fire with",
            ---@param force string
            ---@param other string
            ---@param value boolean
            ---@return Effect.SetCeaseFire
            function(force, other, value)
                return { kind = "set_cease_fire", force = force, other = other, value = value }
            end),
    },
    {
        name = "teams-toggle-chart",
        help = "Toggle chart sharing",
        run = function(s, w)
            return fp.and_then(need_own_team_as_admin(s, w),
                ---@param team Team
                ---@return Result<CommandOutcome>
                function(team)
                    local now = not w.forces[team.force].share_chart
                    ---@type Effect.SetShareChart
                    local effect = { kind = "set_share_chart", force = team.force, value = now }
                    return fp.ok({
                        effects = { effect },
                        output = string.format("Team %s is %s sharing chart", S.name(team), now_or_no_longer(now)),
                    })
                end)
        end,
    },
}

return command_specs
