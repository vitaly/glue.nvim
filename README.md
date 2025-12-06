# glue.nvim

A message broker for Neovim plugins. Lets plugins communicate without knowing about each other.

## The Problem

Switch file browsers and you're rewiring keymaps. Want your statusline to show formatting status? Now it depends on your formatter plugin. Everything ends up coupled to everything else.

## The Solution

Plugins register what they can do and what they need. Glue handles the routing.

```lua
-- formatter plugin
local glue = require("glue").register("conform")
glue.answer("formatting.state", function() return { enabled = true } end)

-- statusline plugin (doesn't need to know about conform)
local glue = require("glue").register("statusline")
local state = glue.ask("formatting.state")
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

### Ask/Answer

Request/response pattern. One plugin answers, others ask.

```lua
local glue = require("glue").register("my-plugin")

-- answer questions
glue.answer("my.channel", function(args)
  return { some = "data" }
end)

-- ask questions
local result = glue.ask("some.channel", { arg = "value" })
```

`ask` returns `nil` if nobody answers. Errors propagate to the caller.

### Emit/Listen

Fire-and-forget events. One emits, many can listen.

```lua
-- emit
glue.emit("file-browser.opened", { path = "/foo" })

-- listen (pattern matching with * and ?)
glue.listen("file-browser.*", function(channel, data, meta)
  print(meta.from .. " sent " .. channel)
end)
```

Listener errors are caught and logged, they won't crash the emitter.

### Clear

Remove your own listeners:

```lua
glue.clear("file-browser.*")
```

### Filter by Source

```lua
-- only ask conform, not other formatters
glue.ask("formatting.state", { from = "conform*" })
```

## Pattern Matching

Channels support `*` (any chars) and `?` (single char):

```lua
glue.listen("formatting.*", handler)  -- formatting.state, formatting.changed
glue.listen("*tree*", handler)        -- neo-tree.toggle, nvim-tree.open
glue.listen("test.?", handler)        -- test.a, test.b (not test.ab)
```

## Introspection

```vim
:Glue list contexts
:Glue list channels
:Glue list answerers formatting.*
:Glue list listeners file-browser.*
:Glue inspect formatting.state
```

```lua
local glue = require("glue")
glue.list_contexts("*format*")
glue.list_answerers("formatting.*")
glue.list_listeners("file-browser.*")
glue.list_channels()
```

## Example: Swappable File Browser

Bind once, swap implementations whenever:

```lua
-- keymaps.lua
vim.keymap.set("n", "<leader>e", function()
  require("glue").register("keymaps").emit("file-browser.toggle")
end)

-- neo-tree config
require("glue").register("neo-tree").listen("file-browser.toggle", function()
  require("neo-tree.command").execute({ toggle = true })
end)

-- or oil config (just swap this in)
require("glue").register("oil").listen("file-browser.toggle", function()
  require("oil").toggle_float()
end)
```

## License

MIT
