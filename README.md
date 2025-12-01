# glue.nvim

A message broker for Neovim plugins. Think of it as a lightweight event bus that lets your plugins talk to each other without knowing about each other.

## Why?

Ever switch from one file browser to another and spend hours rewiring all your keymaps? Or wish your statusline could show formatting status without importing half your config? Yeah, me too.

`glue.nvim` solves this by being the middleman. Plugins register what they can do (answer questions, listen for events) and what they need (ask questions, emit events). No tight coupling, no imports, no mess.

## Installation

### lazy.nvim

```lua
{
  "yourusername/glue.nvim",
  config = function()
    -- Optional: load the :Glue command
    require("glue.commands")
  end
}
```

### packer.nvim

```lua
use {
  'yourusername/glue.nvim',
  config = function()
    require('glue.commands')
  end
}
```

## Core Concepts

### Ask/Answer (Pull Pattern)

One plugin **answers** questions, others **ask** them. Like calling a function, but decoupled.

```lua
-- Plugin A: answer questions
local glue = require("glue").register("plugin-a")

glue.answer("git.is-ignored", function(args)
  local result = vim.fn.system("git check-ignore " .. args.file)
  return { ignored = vim.v.shell_error == 0 }
end)

-- Plugin B: ask questions
local glue = require("glue").register("plugin-b")

local info = glue.ask("git.is-ignored", { file = "/path/to/file" })
if info and info.ignored then
  print("File is ignored")
end
```

### Emit/Listen (Push Pattern)

One plugin **emits** events, others **listen** for them. Like observers, but without the boilerplate.

```lua
-- Plugin A: emit events
local glue = require("glue").register("plugin-a")

glue.emit("file-browser.toggled", {
  open = true,
  side = "left"
})

-- Plugin B: listen for events
local glue = require("glue").register("plugin-b")

glue.listen("file-browser.*", function(channel, data, meta)
  print(string.format("%s emitted on %s", meta.from, channel))
  if data.open then
    -- do something
  end
end)
```

## Registration

Every plugin registers with a unique name:

```lua
local glue = require("glue").register("my-plugin", {
  version = "v1.0",           -- optional: version info
  answers = { "my.*" },       -- optional: channels you answer
  emits = { "my.events.*" },  -- optional: channels you emit on
  listens = { "other.*" },    -- optional: channels you listen to
})
```

**Important:** Each name can only be registered once. If you need multiple glue instances in the same plugin, use different names:

```lua
local maps_glue = require("glue").register("myplugin-maps")
local status_glue = require("glue").register("myplugin-status")
```

This is intentional - it keeps things explicit and makes debugging easier.

## Pattern Matching

All channel names support glob patterns with `*` and `?`:

```lua
-- Exact match
glue.answer("formatting.state", handler)
glue.ask("formatting.state")

-- Prefix match
glue.answer("formatting.buffer-state", handler)
glue.ask("formatting.*")  -- matches the above

-- Contains match
glue.listen("*tree*", handler)  -- matches "neo-tree.toggle", "nvim-tree.open", etc.

-- Suffix match
glue.listen("*.toggle", handler)  -- matches "neo-tree.toggle", "file-browser.toggle", etc.
```

You can also filter by participant name:

```lua
-- Only ask conform.nvim, not other formatters
local state = glue.ask("formatting.state", { from = "conform.*" })

-- Only listen to events from neo-tree
glue.listen("file-browser.*", { from = "neo-tree" }, function(channel, data, meta)
  -- handle it
end)
```

## Introspection

Want to see what's connected?

### From Vim

```vim
:Glue list participants           " all registered plugins
:Glue list channels               " all registered channels
:Glue list answerers formatting.* " who answers formatting questions
:Glue list listeners file-browser.*  " who listens for file browser events

:Glue inspect formatting.state    " everything about a channel
```

### From Lua

```lua
local glue = require("glue")

-- List all participants matching a pattern
local formatters = glue.list_participants("*format*")
-- Returns: { ["conform.nvim"] = { version = "v1.0", ... }, ... }

-- List answerers for a channel
local answerers = glue.list_answerers("formatting.*")
-- Returns: { ["formatting.state"] = { "conform.nvim", "lsp-format" } }

-- List listeners for a pattern
local listeners = glue.list_listeners("file-browser.*")
-- Returns: { ["file-browser.*"] = { "neo-tree", "oil.nvim" } }

-- List all channels
local channels = glue.list_channels()
-- Returns: { "formatting.state", "file-browser.toggle", ... }
```

## Real-World Examples

### Swapping File Browsers

The dream: bind `<leader>e` once, swap file browsers without touching keymaps.

```lua
-- In your keymaps (once!)
vim.keymap.set("n", "<leader>e", function()
  require("glue").register("user-keymaps", {
    emits = { "file-browser.actions.*" }
  }).emit("file-browser.actions.toggle")
end)

-- In a neo-tree config (or a separate neo-tree-glue plugin)
local glue = require("glue").register("neo-tree")
glue.listen("file-browser.actions.toggle", function()
  require("neo-tree.command").execute({ toggle = true })
end)

-- Later: switch to oil.nvim, just change this parAt
local glue = require("glue").register("oil.nvim")
glue.listen("file-browser.actions.toggle", function()
  require("oil").toggle_float()
end)
```

### Translation Between Formats

Sometimes plugins speak different dialects. No problem - just register a translator:

```lua
-- Old plugin provides this format
local old = require("glue").register("old-plugin")
old.answer("old.format", function(args)
  return { state = "active", info = "details" }
end)

-- New plugin expects different format
-- Create a translator
local translator = require("glue").register("translator")
translator.answer("new.format", function(args)
  local old_data = translator.ask("old.format", args)
  if not old_data then return nil end

  return {
    status = old_data.state == "active" and "enabled" or "disabled",
    details = old_data.info,
  }
end)

-- Consumer uses new format
local consumer = require("glue").register("consumer")
local result = consumer.ask("new.format")
```

See? Translation is just another provider. No special API needed.

### Statusline Integration

```lua
local glue = require("glue").register("lualine-glue")

-- Ask formatters for state
local function format_component()
  local state = glue.ask("formatting.buffer-state", { bufnr = 0 })
  if not state then return "" end

  local icons = {
    enabled = " ",
    disabled_global = " ",
    disabled_buffer = " [buf]",
    disabled_filetype = " [ft]",
    formatting = " ...",
  }

  return icons[state.status] or ""
end

-- Listen for changes and auto-refresh
glue.listen("formatting.changed", function()
  vim.cmd("redrawstatus")
end)

-- Use in lualine
require("lualine").setup({
  sections = {
    lualine_x = { format_component }
  }
})
```

## Error Handling

### Ask/Answer

Errors in answerers propagate to the caller - just like normal function calls:

```lua
glue.answer("risky.operation", function(args)
  error("oops")  -- this propagates
end)

-- Caller handles it
local ok, result = pcall(glue.ask, "risky.operation")
if not ok then
  print("Operation failed:", result)
end
```

If no answerer exists, `ask()` returns `nil`:

```lua
local result = glue.ask("nonexistent.channel")
if not result then
  print("No one is answering")
end
```

### Emit/Listen

Errors in listeners are caught and logged - they won't crash the emitter:

```lua
glue.listen("some.event", function()
  error("boom")  -- logged to :messages, other listeners still run
end)

glue.emit("some.event", {})  -- doesn't throw
```

This is intentional - one broken listener shouldn't take down the whole system.

## Glue Packages

Since glue doesn't require plugin authors to support it, anyone can create glue adapters:

```lua
-- neo-tree-glue.nvim
local glue = require("glue").register("neo-tree-glue")

glue.listen("file-browser.toggle", function()
  require("neo-tree.command").execute({ toggle = true })
end)

glue.listen("file-browser.reveal", function(channel, data)
  require("neo-tree.command").execute({
    action = "focus",
    reveal_file = data.path
  })
end)

glue.answer("file-browser.state", function()
  return {
    open = vim.fn.bufwinnr("neo-tree") ~= -1,
    side = "left",
    focused = vim.api.nvim_get_current_buf():match("neo-tree") ~= nil
  }
end)
```

Install it alongside neo-tree, and boom - neo-tree speaks glue.

## Tips

### Share Glue Instances Wisely

If you need glue in multiple files, you have options:

```lua
-- Option 1: Register once, export the instance
-- lua/myplugin/glue.lua
local M = {}
M.glue = require("glue").register("myplugin", {
  answers = { "myplugin.*" }
})
return M

-- Use elsewhere
local glue = require("myplugin.glue").glue
glue.answer("myplugin.state", handler)
```

```lua
-- Option 2: Multiple registrations with different names
local maps_glue = require("glue").register("myplugin-maps")
local status_glue = require("glue").register("myplugin-status")
```

Both work fine. Pick what feels cleaner.

### Channel Naming

Use dots to namespace, verbs for actions:

```
plugin.resource.action
  │      │       │
  │      │       └── toggle, enable, disable, open, close, etc.
  │      └────────── what you're acting on
  └────────────────── your plugin/domain
```

Examples:
- `formatting.buffer-state` (noun - for ask/answer)
- `file-browser.toggle` (verb - for emit/listen)
- `lsp.clients` (noun - for ask/answer)
- `git.status` (noun - for ask/answer)

### Debugging

Can't figure out why things aren't connecting?

```vim
:Glue list participants
:Glue inspect your.channel
```

Check if:
1. Both sides registered with `require("glue").register()`
2. Channel names match (accounting for globs)
3. Answerer actually registered with `glue.answer()`
4. No typos in channel names

## License

MIT

## Contributing

Found a bug? Want to add a feature? PRs welcome!

This is a small, focused library - let's keep it that way. If you're thinking about a big feature, open an issue first so we can discuss if it fits.

## Credits

Inspired by too many hours spent rewiring configs when switching plugins.
