---Per-kind interpreters. Each entry's `---@param` narrows `e` to the matching Effect class.
---@type { [EffectKind]: fun(e: Effect) }
local apply = {
    ---@param e Effect.CreateForce
    create_force = function(e) game.create_force(e.name) end,
    ---@param e Effect.MergeForces
    merge_forces = function(e) game.merge_forces(e.from, e.into) end,
    ---@param e Effect.SetForce
    set_force = function(e) game.get_player(e.player).force = e.force end,
    ---@param e Effect.SetAdmin
    set_admin = function(e) game.get_player(e.player).admin = e.value end,
    ---@param e Effect.SetSpawn
    set_spawn = function(e) game.forces[e.force].set_spawn_position(e.position, e.surface) end,
    ---@param e Effect.SetFriend
    set_friend = function(e) game.forces[e.force].set_friend(e.other, e.value) end,
    ---@param e Effect.SetCeaseFire
    set_cease_fire = function(e) game.forces[e.force].set_cease_fire(e.other, e.value) end,
    ---@param e Effect.SetShareChart
    set_share_chart = function(e) game.forces[e.force].share_chart = e.value end,
}

---Carry out effects in order. The only place that writes to `game`.
---@param effects Effect[]?
local function run_effects(effects)
    for _, effect in ipairs(effects or {}) do
        apply[effect.kind](effect)
    end
end

return run_effects
