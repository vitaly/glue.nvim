---@class GlueContext
---@field version? string
---@field handles? string[]
---@field casts? string[]

---@class GlueCallArgs
---@field prefer? string|string[] Context pattern(s) to filter by, tried in order

---@class GlueMeta
---@field from string Context name that emitted the event

---@alias Handler fun(channel: string, args: any, meta: GlueMeta): any

---@class GlueInstance
---@field handle fun(channel: string, handler: Handler)
---@field call fun(channel: string, args?: GlueCallArgs): any?
---@field cast fun(channel: string, data: any): number
---@field clear fun(pattern: string)

---@class GlueRegistry
---@field contexts table<string, GlueContext>
---@field handlers table<string, table<string, Handler>>

---@type GlueRegistry
local registry = {
  contexts = {},
  handlers = {},
}

---@param str string
---@param pattern string
---@return boolean
local function matches_pattern(str, pattern)
  if not pattern:find('[*?]') then
    return str == pattern
  end
  local lua_pattern = pattern:gsub('%.', '%%.'):gsub('%*', '.*'):gsub('%?', '.')
  return str:match('^' .. lua_pattern .. '$') ~= nil
end

---@class Glue
local M = {}

---@param name string
---@param context? GlueContext
---@return GlueInstance
function M.register(name, context)
  registry.contexts[name] = context or {}

  return {
    ---@param channel string
    ---@param handler Handler
    handle = function(channel, handler)
      if 'string' ~= type(channel) then
        error(
          ('handle(channel, handler): channel must be a string. received %s (a %s) instead'):format(
            vim.inspect(channel),
            type(channel)
          )
        )
      end
      registry.handlers[channel] = registry.handlers[channel] or {}
      registry.handlers[channel][name] = handler
    end,

    ---@param channel string
    ---@param args? GlueCallArgs
    ---@return any?
    call = function(channel, args)
      args = args or {}

      -- Normalize prefer to always be a list
      local prefer_patterns = args.prefer
      if type(prefer_patterns) == "string" then
        prefer_patterns = { prefer_patterns }
      elseif not prefer_patterns then
        prefer_patterns = { "*" }  -- default: match any
      end

      -- Try each pattern in order
      for _, prefer_pattern in ipairs(prefer_patterns) do
        for pattern, handlers in pairs(registry.handlers) do
          if matches_pattern(channel, pattern) then
            for context_name, handler in pairs(handlers) do
              if matches_pattern(context_name, prefer_pattern) then
                local meta = { from = context_name }
                return handler(channel, args, meta)
              end
            end
          end
        end
      end

      return nil
    end,

    ---@param channel string
    ---@param data any
    ---@return number
    cast = function(channel, data)
      local count = 0
      for pattern, handlers in pairs(registry.handlers) do
        if matches_pattern(channel, pattern) then
          for context_name, handler in pairs(handlers) do
            local meta = { from = name }
            local ok, err = pcall(handler, channel, data, meta)
            if not ok then
              vim.notify(
                ('[glue] Handler error in %s on %s: %s'):format(context_name, channel, err),
                vim.log.levels.ERROR
              )
            else
              count = count + 1
            end
          end
        end
      end
      return count
    end,

    ---@param pattern string
    clear = function(pattern)
      for handler_pattern, handlers in pairs(registry.handlers) do
        if matches_pattern(handler_pattern, pattern) then
          handlers[name] = nil
          if next(handlers) == nil then
            registry.handlers[handler_pattern] = nil
          end
        end
      end
    end,
  }
end

---@param channel_pattern? string
---@param name_pattern? string
---@return table<string, string[]>
function M.list_handlers(channel_pattern, name_pattern)
  channel_pattern = channel_pattern or '*'
  name_pattern = name_pattern or '*'
  local results = {}
  for channel, handlers in pairs(registry.handlers) do
    if matches_pattern(channel, channel_pattern) then
      for context_name in pairs(handlers) do
        if matches_pattern(context_name, name_pattern) then
          results[channel] = results[channel] or {}
          table.insert(results[channel], context_name)
        end
      end
    end
  end
  return results
end

---@param name_pattern? string
---@return table<string, GlueContext>
function M.list_contexts(name_pattern)
  name_pattern = name_pattern or '*'
  local results = {}
  for ctx_name, context in pairs(registry.contexts) do
    if matches_pattern(ctx_name, name_pattern) then
      results[ctx_name] = context
    end
  end
  return results
end

---@param channel_pattern? string
---@return string[]
function M.list_channels(channel_pattern)
  channel_pattern = channel_pattern or '*'
  local results = {}
  for pattern in pairs(registry.handlers) do
    if matches_pattern(pattern, channel_pattern) then
      table.insert(results, pattern)
    end
  end
  table.sort(results)
  return results
end

---@private
function M._reset()
  registry.contexts = {}
  registry.handlers = {}
end

return M
