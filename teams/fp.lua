---@class Ok<T>
---@field ok true
---@field value T

---@class Err
---@field ok false
---@field error string Message shown to the caller as-is

---@alias Result<T> Ok<T> | Err

---Small functional helpers. All functions are pure and never mutate their arguments.
---@class fp
local fp = {}

---Shallow copy of a table.
---@generic T: table
---@param t T
---@return T
function fp.copy(t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = v
    end
    return out
end

---Copy of `t` with `t[k] = v`.
---@generic T: table
---@param t T
---@param k any
---@param v any
---@return T
function fp.assoc(t, k, v)
    local out = fp.copy(t)
    out[k] = v
    return out
end

---Copy of `t` without key `k`.
---@generic T: table
---@param t T
---@param k any
---@return T
function fp.dissoc(t, k)
    return fp.assoc(t, k, nil)
end

---Copy of `t` with `t[k]` replaced by `f(t[k])`.
---@generic T: table
---@param t T
---@param k any
---@param f fun(old: any): any
---@return T
function fp.update(t, k, f)
    return fp.assoc(t, k, f(t[k]))
end

---Entries of `t` for which `pred` returns true, keys preserved.
---@generic K, V
---@param t table<K, V>
---@param pred fun(v: V, k: K): boolean
---@return table<K, V>
function fp.filter(t, pred)
    local out = {}
    for k, v in pairs(t) do
        if pred(v, k) then
            out[k] = v
        end
    end
    return out
end

---`f` applied to every value of `t`, keys preserved.
---@generic K, V, U
---@param t table<K, V>
---@param f fun(v: V, k: K): U
---@return table<K, U>
function fp.map(t, f)
    local out = {}
    for k, v in pairs(t) do
        out[k] = f(v, k)
    end
    return out
end

---Values of `t` sorted by `key`, for deterministic output.
---@generic K, V
---@param t table<K, V>
---@param key fun(v: V): string
---@return V[]
function fp.sorted_values(t, key)
    local out = {}
    for _, v in pairs(t) do
        table.insert(out, v)
    end
    table.sort(out, function(a, b) return key(a) < key(b) end)
    return out
end

---@generic T
---@param value T
---@return Ok<T>
function fp.ok(value)
    return { ok = true, value = value }
end

---@param message string
---@return Err
function fp.err(message)
    return { ok = false, error = message }
end

---Typed single step: run `f` on the value if `r` is ok, else pass the error through.
---@generic T, U
---@param r Result<T>
---@param f fun(value: T): Result<U>
---@return Result<U>
function fp.and_then(r, f)
    if not r.ok then
        return r
    end
    ---@cast r Ok<T>
    return f(r.value)
end

---Run Result-returning steps in order. Each step gets the previous step's value, and the first error short-circuits.
---Variadic, so types aren't inferred between steps: annotate each step's parameter at the call site.
---@param first Result<any>
---@param ... fun(value: any): Result<any>
---@return Result<any>
function fp.chain(first, ...)
    local result = first
    for _, step in ipairs({ ... }) do
        if not result.ok then
            return result
        end
        result = step(result.value)
    end
    return result
end

return fp
