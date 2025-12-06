---@class GlueContext
---@field version? string
---@field answers? string[]
---@field emits? string[]
---@field listens? string[]

---@class GlueAskArgs
---@field from? string Filter answerers by context name pattern

---@class GlueMeta
---@field from string Context name that emitted the event
---@field channel string Channel the event was emitted on

---@alias GlueAnswerer fun(args: table): any
---@alias GlueListener fun(channel: string, data: any, meta: GlueMeta)

---@class GlueInstance
---@field answer fun(channel: string, handler: GlueAnswerer)
---@field ask fun(channel: string, args?: GlueAskArgs): any?
---@field emit fun(channel: string, data: any)
---@field listen fun(pattern: string, handler: GlueListener)
---@field clear fun(pattern: string)

---@class GlueRegistry
---@field contexts table<string, GlueContext>
---@field answerers table<string, table<string, GlueAnswerer>>
---@field listeners table<string, table<string, GlueListener>>

---@type GlueRegistry
local registry = {
  contexts = {},
  answerers = {},
  listeners = {},
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
    ---@param handler GlueAnswerer
    answer = function(channel, handler)
      registry.answerers[channel] = registry.answerers[channel] or {}
      registry.answerers[channel][name] = handler
    end,

    ---@param channel string
    ---@param args? GlueAskArgs
    ---@return any?
    ask = function(channel, args)
      args = args or {}
      local answerers = registry.answerers[channel]
      if answerers then
        for context_name, answerer in pairs(answerers) do
          if not args.from or matches_pattern(context_name, args.from) then
            return answerer(args)
          end
        end
      end
      return nil
    end,

    ---@param channel string
    ---@param data any
    emit = function(channel, data)
      for pattern, listeners in pairs(registry.listeners) do
        if matches_pattern(channel, pattern) then
          for context_name, listener in pairs(listeners) do
            local meta = { from = name, channel = channel }
            local ok, err = pcall(listener, channel, data, meta)
            if not ok then
              vim.notify(('[glue] Listener error in %s on %s: %s'):format(context_name, channel, err), vim.log.levels.ERROR)
            end
          end
        end
      end
    end,

    ---@param pattern string
    ---@param handler GlueListener
    listen = function(pattern, handler)
      registry.listeners[pattern] = registry.listeners[pattern] or {}
      registry.listeners[pattern][name] = handler
    end,

    ---@param pattern string
    clear = function(pattern)
      for listener_pattern, listeners in pairs(registry.listeners) do
        if matches_pattern(listener_pattern, pattern) then
          listeners[name] = nil
          if next(listeners) == nil then
            registry.listeners[listener_pattern] = nil
          end
        end
      end
    end,
  }
end

---@param channel_pattern? string
---@param name_pattern? string
---@return table<string, string[]>
function M.list_answerers(channel_pattern, name_pattern)
  channel_pattern = channel_pattern or '*'
  name_pattern = name_pattern or '*'
  local results = {}
  for channel, answerers in pairs(registry.answerers) do
    if matches_pattern(channel, channel_pattern) then
      for context_name in pairs(answerers) do
        if matches_pattern(context_name, name_pattern) then
          results[channel] = results[channel] or {}
          table.insert(results[channel], context_name)
        end
      end
    end
  end
  return results
end

---@param pattern_filter? string
---@param name_pattern? string
---@return table<string, string[]>
function M.list_listeners(pattern_filter, name_pattern)
  pattern_filter = pattern_filter or '*'
  name_pattern = name_pattern or '*'
  local results = {}
  for pattern, listeners in pairs(registry.listeners) do
    if matches_pattern(pattern, pattern_filter) then
      for context_name in pairs(listeners) do
        if matches_pattern(context_name, name_pattern) then
          results[pattern] = results[pattern] or {}
          table.insert(results[pattern], context_name)
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
  local seen = {}
  for channel in pairs(registry.answerers) do
    seen[channel] = true
  end
  for pattern in pairs(registry.listeners) do
    seen[pattern] = true
  end
  local results = {}
  for channel in pairs(seen) do
    if matches_pattern(channel, channel_pattern) then
      table.insert(results, channel)
    end
  end
  table.sort(results)
  return results
end

---@private
function M._reset()
  registry.contexts = {}
  registry.answerers = {}
  registry.listeners = {}
end

return M
