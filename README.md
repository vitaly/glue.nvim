# glue.nvim

A message broker for Neovim plugins. Lets plugins communicate without knowing about each other.

## The Problem

Switch file browsers and you're rewiring keymaps. Want your statusline to show formatting status? Now it depends on your formatter plugin. Everything ends up coupled to everything else.

## The Solution

Plugins register what they can do and what they need. Glue handles the routing.

```lua
-- formatter plugin
local glue = require("glue").register("conform")
glue.handle("formatting.state", function(channel, args, meta)
  return { enabled = true }
end)

-- statusline plugin (doesn't need to know about conform)
local glue = require("glue").register("statusline")
local state = glue.call("formatting.state")
```

## Installation

```lua
-- lazy.nvim
{ "vitaly/glue.nvim" }

-- packer
use "vitaly/glue.nvim"
```

Load the `:Glue` command if you want it:

```lua
require("glue.commands")
```

## API

### Call/Handle

Request/response pattern. One plugin handles, others call.

```lua
local glue = require("glue").register("my-plugin")

-- handle requests (can use patterns like * and ?)
glue.handle("my.channel", function(channel, args, meta)
  return { some = "data" }
end)

-- call handlers
local result = glue.call("some.channel", { arg = "value" })
```

`call` returns `nil` if no handler matches. Errors propagate to the caller.

### Cast/Handle

Fire-and-forget events. One casts, many can handle.

```lua
-- cast events
local count = glue.cast("file-browser.opened", { path = "/foo" })
print(count .. " handlers called")

-- handle events (pattern matching with * and ?)
glue.handle("file-browser.*", function(channel, data, meta)
  print(meta.from .. " sent " .. channel)
end)
```

Handler errors are caught and logged. `cast` returns the count of successfully called handlers.

### Clear

Remove your own handlers:

```lua
glue.clear("file-browser.*")
```

### Prefer Specific Handlers

Filter which handlers to call by context name pattern:

```lua
-- prefer conform, fall back to any
glue.call("formatting.state", { prefer = "conform*" })

-- try handlers in order: telescope first, then lsp, then anyone
glue.call("lsp.actions.definition", {
  prefer = { "telescope.*", "lsp.*", "*" }
})

-- only specific handlers, no fallback
glue.call("lsp.actions.definition", {
  prefer = { "telescope.*", "lsp.*" }
})
```

## Pattern Matching

Channels and context names support `*` (any chars) and `?` (single char):

```lua
glue.handle("formatting.*", handler)  -- formatting.state, formatting.changed
glue.handle("*tree*", handler)        -- neo-tree.toggle, nvim-tree.open
glue.handle("test.?", handler)        -- test.a, test.b (not test.ab)
```

## Introspection

```vim
:Glue list contexts
:Glue list channels
:Glue list handlers formatting.*
:Glue inspect formatting.state
```

```lua
local glue = require("glue")
glue.list_contexts("*format*")
glue.list_handlers("formatting.*")
glue.list_channels()
```

## Example: Swappable File Browser

Bind once, swap implementations whenever:

```lua
-- keymaps.lua
vim.keymap.set("n", "<leader>e", function()
  require("glue").register("keymaps").cast("file-browser.toggle")
end)

-- neo-tree config
require("glue").register("neo-tree").handle("file-browser.toggle", function()
  require("neo-tree.command").execute({ toggle = true })
end)

-- or oil config (just swap this in)
require("glue").register("oil").handle("file-browser.toggle", function()
  require("oil").toggle_float()
end)
```

## License

MIT
