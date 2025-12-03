local M = {}

---@class GlueContext
---@field version string|nil Plugin version
---@field answers string[]|nil Channels this context answers
---@field emits string[]|nil Channels this context emits to
---@field listens string[]|nil Channels this context listens to

---@alias Answerer fun(args: table): any
---@alias Listener fun(channel: string, data: any, meta: table): nil

---@class GlueRegistry
---@field contexts table<string, GlueContext> Registered contexts by name
---@field answerers table<string, table<string, Answerer>> Answerers by channel and context
---@field listeners table<string, table<string, Listener>> Listeners by pattern and context

---@type GlueRegistry
local registry = {
  contexts = {},
  answerers = {},
  listeners = {},
}

---Check if a string matches a glob pattern
---@param str string The string to test
---@param pattern string The glob pattern (* and ? supported)
---@return boolean match True if the string matches the pattern
---@private
local function matches_pattern(str, pattern)
  if not pattern:find('[*?]') then
    return str == pattern
  end

  -- Escape dots and convert glob to lua pattern
  local regex = pattern:gsub('%.', '%%.'):gsub('%*', '.*'):gsub('%?', '.')
  return str:match('^' .. regex .. '$') ~= nil
end

---@class GlueInstance
---@field answer fun(channel: string, handler: Answerer): nil Register an answerer
---@field ask fun(channel: string, args?: table): any|nil Query for an answer
---@field emit fun(channel: string, data: any): nil Emit an event
---@field listen fun(pattern: string, handler: Listener): nil Register a listener
---@field clear fun(pattern: string): nil Clear listeners matching a pattern

---Register a context and return namespaced glue instance
---@param name string Unique name for this context
---@param context GlueContext|nil Registration context
---@return GlueInstance glue Namespaced glue instance for this context
---@usage
---```lua
---local glue = require("glue").register("my-plugin", {
---  version = "v1.0",
---  answers = { "formatting.buffer-state" },
---  emits = { "formatting.changed" },
---  listens = { "file-browser.*" },
---})
---```
function M.register(name, context)
  context = context or {}

  registry.contexts[name] = context

  -- Return namespaced glue instance with closures
  ---@type GlueInstance
  return {
    ---Register an answer handler for a channel
    ---@param channel string The exact channel to answer on
    ---@param handler Answerer The handler function
    answer = function(channel, handler)
      registry.answerers[channel] = registry.answerers[channel] or {}
      registry.answerers[channel][name] = handler
    end,

    ---Ask a question on a channel
    ---@param channel string The exact channel to query
    ---@param args table|nil Arguments to pass to the answerer
    ---@return any|nil result The answer, or nil if no answerer found
    ask = function(channel, args)
      args = args or {}

      -- Direct lookup by exact channel name
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

    ---Emit an event on a channel
    ---@param channel string The exact channel to emit on
    ---@param data any Data to send with the event
    emit = function(channel, data)
      -- Match exact channel against listener patterns
      for pattern, listeners in pairs(registry.listeners) do
        if matches_pattern(channel, pattern) then
          for context_name, listener in pairs(listeners) do
            ---@type table
            local meta = { from = name, channel = channel }
            local ok, err = pcall(listener, channel, data, meta)
            if not ok then
              vim.notify(
                string.format(
                  "[glue] Listener error in '%s' for channel '%s': %s",
                  context_name,
                  channel,
                  err
                ),
                vim.log.levels.ERROR
              )
            end
          end
        end
      end
    end,

    ---Register a listener for channel events
    ---@param pattern string The channel pattern to listen on (supports glob patterns)
    ---@param handler Listener The handler function
    ---@return nil
    listen = function(pattern, handler)
      registry.listeners[pattern] = registry.listeners[pattern] or {}
      registry.listeners[pattern][name] = handler
    end,

    ---Clear listeners for this context maptching a pattern
    ---@param pattern string The channel pattern to clear listeners for
    ---@return nil
    ---@usage
    ---```lua
    ---glue.clear("file-browser.*")
    ---```
    clear = function(pattern)
      for listener_pattern, listeners in pairs(registry.listeners) do
        if matches_pattern(listener_pattern, pattern) then
          listeners[name] = nil
          -- Clean up empty listener tables
          if next(listeners) == nil then
            registry.listeners[listener_pattern] = nil
          end
        end
      end
    end,
  }
end

---List answerers matching channel and name patterns
---@param channel_pattern string|nil Channel pattern to filter by (default: "*")
---@param name_pattern string|nil Context name pattern to filter by (default: "*")
---@return table<string, string[]> answerers Map of channels to context names
---@usage
---```lua
---local answerers = glue.list_answerers("formatting.*", "conform*")
---```
function M.list_answerers(channel_pattern, name_pattern)
  channel_pattern = channel_pattern or '*'
  name_pattern = name_pattern or '*'

  ---@type table<string, string[]>
  local results = {}
  for channel, answerers in pairs(registry.answerers) do
    if matches_pattern(channel, channel_pattern) then
      for context_name, _ in pairs(answerers) do
        if matches_pattern(context_name, name_pattern) then
          results[channel] = results[channel] or {}
          table.insert(results[channel], context_name)
        end
      end
    end
  end
  return results
end

---List listeners matching pattern and name patterns
---@param pattern_filter string|nil Pattern to filter by (default: "*")
---@param name_pattern string|nil Context name pattern to filter by (default: "*")
---@return table<string, string[]> listeners Map of patterns to context names
---@usage
---```lua
---local listeners = glue.list_listeners("formatting.*")
---```
function M.list_listeners(pattern_filter, name_pattern)
  pattern_filter = pattern_filter or '*'
  name_pattern = name_pattern or '*'

  ---@type table<string, string[]>
  local results = {}
  for pattern, listeners in pairs(registry.listeners) do
    if matches_pattern(pattern, pattern_filter) then
      for context_name, _ in pairs(listeners) do
        if matches_pattern(context_name, name_pattern) then
          results[pattern] = results[pattern] or {}
          table.insert(results[pattern], context_name)
        end
      end
    end
  end
  return results
end

---List contexts matching name pattern
---@param name_pattern string|nil Name pattern to filter by (default: "*")
---@return table<string, GlueContext> contexts Map of context names to their info
---@usage
---```lua
---local contexts = glue.list_contexts("*format*")
---```
function M.list_contexts(name_pattern)
  name_pattern = name_pattern or '*'
  ---@type table<string, GlueContext>
  local results = {}
  for name, context in pairs(registry.contexts) do
    if matches_pattern(name, name_pattern) then
      results[name] = context
    end
  end
  return results
end

---List all registered channels
---@param channel_pattern string|nil Channel pattern to filter by (default: "*")
---@return string[] channels List of channel names
---@usage
---```lua
---local channels = glue.list_channels("formatting.*")
---```
function M.list_channels(channel_pattern)
  channel_pattern = channel_pattern or '*'
  ---@type table<string, boolean>
  local all_channels = {}

  -- Collect from answerers
  for channel, _ in pairs(registry.answerers) do
    all_channels[channel] = true
  end

  -- Collect from listeners
  for pattern, _ in pairs(registry.listeners) do
    all_channels[pattern] = true
  end

  ---@type string[]
  local results = {}
  for channel, _ in pairs(all_channels) do
    if matches_pattern(channel, channel_pattern) then
      table.insert(results, channel)
    end
  end

  table.sort(results)
  return results
end

---Reset the registry (for testing only)
---@private
function M._reset()
  registry.contexts = {}
  registry.answerers = {}
  registry.listeners = {}
end

return M
