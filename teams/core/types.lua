---@meta
-- Type definitions only; never required at runtime.

------------------------------------------------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------------------------------------------------

---Per-team sidecar data for things LuaForce doesn't store. Plain data only, safe for `storage`.
---@class Team
---@field force string Name of the force this team wraps; also its key in `TeamsState.teams`
---@field display_name string? Preferred name shown to players; nil means `force` is used
---@field hidden boolean Hidden teams are never listed, shown or targetable by commands
---@field admins table<uint32, true> Set of team-admin player indices (reserved, no commands yet)
---@field whitelist table<string, true> Set of player names allowed to join (reserved, not enforced yet)

---Options accepted when creating a `Team`.
---@class TeamOpts
---@field display_name string?
---@field hidden boolean?

---Root of persistent teams data, stored in `storage.teams`. Treated as immutable: every change produces a new value.
---@class TeamsState
---@field teams table<string, Team> force name → team
---@field version integer Schema version, for future migrations

------------------------------------------------------------------------------------------------------------------------
-- World snapshot (read-only view of `game`, built by the shell)
------------------------------------------------------------------------------------------------------------------------

---@class PlayerView
---@field name string
---@field admin boolean

---The player running a command.
---@class Caller
---@field index uint32
---@field name string
---@field admin boolean Game admin, not team admin
---@field force string Name of the caller's current force
---@field position MapPosition
---@field surface string Surface name

---@class ForceView
---@field name string
---@field players PlayerView[]
---@field friends table<string, true> Names of forces this force is friends with
---@field ceasefire table<string, true> Names of forces this force has a cease-fire with
---@field share_chart boolean

---Everything a pure command needs to know about the game.
---@class World
---@field caller Caller? nil when the command comes from the server console
---@field forces table<string, ForceView> force name → view
---@field force_count integer
---@field max_forces integer

------------------------------------------------------------------------------------------------------------------------
-- Effects (side effects described as data, carried out by shell/effects.lua)
------------------------------------------------------------------------------------------------------------------------

---@class Effect.CreateForce
---@field kind "create_force"
---@field name string

---@class Effect.MergeForces
---@field kind "merge_forces"
---@field from string
---@field into string

---@class Effect.SetForce
---@field kind "set_force"
---@field player uint32
---@field force string

---@class Effect.SetAdmin
---@field kind "set_admin"
---@field player uint32
---@field value boolean

---@class Effect.SetSpawn
---@field kind "set_spawn"
---@field force string
---@field position MapPosition
---@field surface string

---@class Effect.SetFriend
---@field kind "set_friend"
---@field force string
---@field other string
---@field value boolean

---@class Effect.SetCeaseFire
---@field kind "set_cease_fire"
---@field force string
---@field other string
---@field value boolean

---@class Effect.SetShareChart
---@field kind "set_share_chart"
---@field force string
---@field value boolean

---@alias Effect
---| Effect.CreateForce
---| Effect.MergeForces
---| Effect.SetForce
---| Effect.SetAdmin
---| Effect.SetSpawn
---| Effect.SetFriend
---| Effect.SetCeaseFire
---| Effect.SetShareChart

---@alias EffectKind
---| "create_force"
---| "merge_forces"
---| "set_force"
---| "set_admin"
---| "set_spawn"
---| "set_friend"
---| "set_cease_fire"
---| "set_share_chart"

------------------------------------------------------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------------------------------------------------------

---Lines to print back to the caller.
---@alias CommandOutput string | string[]

---What a successful command wants to happen. Every field is optional; `{}` means "do nothing, say nothing".
---@class CommandOutcome
---@field state TeamsState? Replacement state; nil leaves state unchanged
---@field effects Effect[]? Side effects to carry out before saving state
---@field output CommandOutput? Message for the caller

---A pure command: no access to `game`, `storage` or `commands`.
---@alias CommandRun fun(s: TeamsState, w: World, arg: string?): Result<CommandOutcome>

---@class CommandSpec
---@field name string Console command name, e.g. "teams-join"
---@field help string Help text shown by /help
---@field run CommandRun

------------------------------------------------------------------------------------------------------------------------
-- Events (plain payloads built by the shell from EventData.*)
------------------------------------------------------------------------------------------------------------------------

---@class TeamsEvent.PlayerJoined
---@field player_index uint32
---@field name string
---@field admin boolean

---@class TeamsEvent.PlayerChangedForce
---@field player_index uint32
---@field old_force string

---@class TeamsEvent.PlayerRemoved
---@field player_index uint32

---@class TeamsEvent.ForcesMerged
---@field source_name string

---A pure event handler: returns the next state and any side effects.
---@alias Reducer<E> fun(s: TeamsState, ev: E): TeamsState, Effect[]

------------------------------------------------------------------------------------------------------------------------
-- Migrations
------------------------------------------------------------------------------------------------------------------------

---A Teams Lite team, flattened by the shell from `storage.teams_lite` (valid forces only).
---@class LiteTeamView
---@field name string Teams Lite name; differs from `force` only for display-named teams
---@field force string Force name
---@field member_count integer
