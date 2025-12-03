---@diagnostic disable: undefined-field
local inspect = require('inspect')

-- Mock vim APIs before requiring glue
_G.vim = {
  inspect = inspect,

  notify = function(msg, level)
    -- Store notifications for testing if needed
    _G.vim._notifications = _G.vim._notifications or {}
    table.insert(_G.vim._notifications, { msg = msg, level = level })
  end,

  split = function(str, sep, opts)
    opts = opts or {}
    local parts = {}
    local pattern = '([^' .. sep .. ']+)'
    for part in string.gmatch(str, pattern) do
      if not opts.trimempty or part ~= '' then
        table.insert(parts, part)
      end
    end
    return parts
  end,

  tbl_contains = function(t, value)
    for _, v in ipairs(t) do
      if v == value then
        return true
      end
    end
    return false
  end,

  tbl_count = function(t)
    local count = 0
    for _ in pairs(t) do
      count = count + 1
    end
    return count
  end,

  log = {
    levels = {
      ERROR = 4,
      WARN = 3,
      INFO = 2,
      DEBUG = 1,
    },
  },
}

local glue = require('glue')

-- Helper to reset registry between tests
local function reset_glue()
  if glue._reset then
    glue._reset()
  end
  -- Clear notification history
  _G.vim._notifications = {}
end

describe('glue registration', function()
  before_each(reset_glue)

  it('should register a context with metadata', function()
    local my_glue = glue.register('test-plugin', {
      version = 'v1.0',
      answers = { 'test.question' },
      emits = { 'test.event' },
      listens = { 'other.*' },
    })

    assert.is_not_nil(my_glue)

    local contexts = glue.list_contexts('test-plugin')
    assert.is_not_nil(contexts['test-plugin'])
    assert.equals('v1.0', contexts['test-plugin'].version)
    assert.same({ 'test.question' }, contexts['test-plugin'].answers)
    assert.same({ 'test.event' }, contexts['test-plugin'].emits)
    assert.same({ 'other.*' }, contexts['test-plugin'].listens)
  end)

  it('should allow registration without metadata', function()
    local my_glue = glue.register('simple-plugin')
    assert.is_not_nil(my_glue)
  end)

  it('should return instance with methods', function()
    local my_glue = glue.register('test-plugin')
    assert.is_function(my_glue.answer)
    assert.is_function(my_glue.ask)
    assert.is_function(my_glue.emit)
    assert.is_function(my_glue.listen)
  end)
end)

describe('ask/answer', function()
  before_each(reset_glue)

  it('should call answerer when asked', function()
    local answerer = glue.register('answerer')
    local asker = glue.register('asker')

    local called = false
    local received_args = nil

    answerer.answer('test.question', function(args)
      called = true
      received_args = args
      return { answer = 42 }
    end)

    local result = asker.ask('test.question', { param = 'value' })

    assert.is_true(called)
    assert.equals(42, result.answer)
    assert.is_not_nil(received_args)
    ---@diagnostic disable-next-line: need-check-nil
    assert.equals('value', received_args.param)
  end)

  it('should return nil when no answerer exists', function()
    local asker = glue.register('asker')
    local result = asker.ask('nonexistent.channel')
    assert.is_nil(result)
  end)

  it('should use exact channel match only', function()
    local answerer = glue.register('answerer')
    local asker = glue.register('asker')

    answerer.answer('test.specific.channel', function()
      return { found = true }
    end)

    -- Exact match works
    local result = asker.ask('test.specific.channel')
    assert.is_not_nil(result)
    assert.is_true(result.found)

    -- Pattern in ask doesn't work
    local result2 = asker.ask('test.*')
    assert.is_nil(result2)
  end)

  it("should filter by 'from' pattern", function()
    local answerer1 = glue.register('conform.nvim')
    local answerer2 = glue.register('lsp-format')
    local asker = glue.register('asker')

    answerer1.answer('format', function()
      return { provider = 'conform' }
    end)
    answerer2.answer('format', function()
      return { provider = 'lsp' }
    end)

    local result = asker.ask('format', { from = 'conform.*' })
    assert.equals('conform', result.provider)
  end)

  it('should propagate errors from answerer', function()
    local answerer = glue.register('answerer')
    local asker = glue.register('asker')

    answerer.answer('test.error', function()
      error('intentional error')
    end)

    assert.has_error(function()
      asker.ask('test.error')
    end)
  end)
end)

describe('emit/listen', function()
  before_each(reset_glue)

  it('should call all matching listeners', function()
    local emitter = glue.register('emitter')
    local listener1 = glue.register('listener1')
    local listener2 = glue.register('listener2')

    local calls = {}

    listener1.listen('test.*', function(channel, data, meta)
      table.insert(calls, { listener = 'l1', channel = channel, data = data, meta = meta })
    end)

    listener2.listen('test.event', function(channel, data, meta)
      table.insert(calls, { listener = 'l2', channel = channel, data = data, meta = meta })
    end)

    emitter.emit('test.event', { foo = 'bar' })

    assert.equals(2, #calls)
    assert.equals('test.event', calls[1].channel)
    assert.equals('bar', calls[1].data.foo)
    assert.equals('emitter', calls[1].meta.from)
  end)

  it('should not crash emitter when listener errors', function()
    local emitter = glue.register('emitter')
    local listener1 = glue.register('bad-listener')
    local listener2 = glue.register('good-listener')

    local good_called = false

    listener1.listen('test.*', function()
      error('boom')
    end)

    listener2.listen('test.*', function()
      good_called = true
    end)

    -- Should not throw
    assert.has_no.errors(function()
      emitter.emit('test.event', {})
    end)

    -- Good listener should still be called
    assert.is_true(good_called)

    -- Error should be logged
    assert.is_true(#_G.vim._notifications > 0)
    local found_error = false
    for _, notif in ipairs(_G.vim._notifications) do
      if notif.level == vim.log.levels.ERROR and notif.msg:match('Listener error') then
        found_error = true
        break
      end
    end
    assert.is_true(found_error)
  end)

  it('should match complex glob patterns', function()
    local emitter = glue.register('emitter')
    local listener = glue.register('listener')

    local called = false

    listener.listen('*tree*', function()
      called = true
    end)

    emitter.emit('neo-tree.toggle', {})
    assert.is_true(called)
  end)

  it('should not call listeners for non-matching channels', function()
    local emitter = glue.register('emitter')
    local listener = glue.register('listener')

    local called = false

    listener.listen('formatting.*', function()
      called = true
    end)

    emitter.emit('file-browser.toggle', {})
    assert.is_false(called)
  end)
end)

describe('glob matching', function()
  before_each(reset_glue)

  it('should match exact strings in listeners', function()
    local emitter = glue.register('emitter')
    local listener = glue.register('listener')

    local called = false
    listener.listen('exact.match', function()
      called = true
    end)

    emitter.emit('exact.match', {})
    assert.is_true(called)
  end)

  it('should match * wildcard in listeners', function()
    local emitter = glue.register('emitter')
    local listener = glue.register('listener')

    local called = false
    listener.listen('formatting.*', function()
      called = true
    end)

    emitter.emit('formatting.buffer.state', {})
    assert.is_true(called)
  end)

  it('should match * in middle of pattern', function()
    local emitter = glue.register('emitter')
    local listener = glue.register('listener')

    local called = false
    listener.listen('*tree*', function()
      called = true
    end)

    emitter.emit('neo-tree.toggle', {})
    assert.is_true(called)
  end)

  it('should escape dots in patterns', function()
    local emitter = glue.register('emitter')
    local listener = glue.register('listener')

    local called = false
    listener.listen('test.channel', function()
      called = true
    end)

    -- Should match exact
    emitter.emit('test.channel', {})
    assert.is_true(called)

    -- Should NOT match "testXchannel"
    called = false
    emitter.emit('testXchannel', {})
    assert.is_false(called)
  end)
end)

describe('introspection', function()
  before_each(reset_glue)

  it('should list all contexts', function()
    glue.register('plugin1', { version = 'v1.0' })
    glue.register('plugin2', { version = 'v2.0' })

    local contexts = glue.list_contexts()
    assert.is_not_nil(contexts['plugin1'])
    assert.is_not_nil(contexts['plugin2'])
  end)

  it('should filter contexts by pattern', function()
    glue.register('conform.nvim', {})
    glue.register('lsp-format', {})
    glue.register('other-plugin', {})

    local contexts = glue.list_contexts('*form*')
    assert.is_not_nil(contexts['conform.nvim'])
    assert.is_not_nil(contexts['lsp-format'])
    assert.is_nil(contexts['other-plugin'])
  end)

  it('should list answerers with filters', function()
    local p1 = glue.register('plugin1')
    local p2 = glue.register('plugin2')

    p1.answer('formatting.state', function() end)
    p2.answer('formatting.buffer', function() end)
    p2.answer('other.channel', function() end)

    local answerers = glue.list_answerers('formatting.*')
    assert.is_not_nil(answerers['formatting.state'])
    assert.is_not_nil(answerers['formatting.buffer'])
    assert.is_nil(answerers['other.channel'])
  end)

  it('should list answerers with name filter', function()
    local p1 = glue.register('conform.nvim')
    local p2 = glue.register('lsp-format')

    p1.answer('format', function() end)
    p2.answer('format', function() end)

    local answerers = glue.list_answerers('format', 'conform.*')
    assert.equals(1, #answerers['format'])
    assert.equals('conform.nvim', answerers['format'][1])
  end)

  it('should list listeners with filters', function()
    local p1 = glue.register('plugin1')
    local p2 = glue.register('plugin2')

    p1.listen('formatting.*', function() end)
    p2.listen('file-browser.*', function() end)

    local listeners = glue.list_listeners('formatting.*')
    assert.is_not_nil(listeners['formatting.*'])
    assert.is_nil(listeners['file-browser.*'])
  end)

  it('should list all channels', function()
    local p1 = glue.register('plugin1')
    local p2 = glue.register('plugin2')

    p1.answer('channel1', function() end)
    p2.answer('channel2', function() end)
    p2.listen('channel3', function() end)

    local channels = glue.list_channels()
    assert.is_true(vim.tbl_contains(channels, 'channel1'))
    assert.is_true(vim.tbl_contains(channels, 'channel2'))
    assert.is_true(vim.tbl_contains(channels, 'channel3'))
  end)
end)

describe('duplicate registration', function()
  before_each(reset_glue)

  it('should allow different names for same logical plugin', function()
    local glue1 = glue.register('myplugin-maps')
    local glue2 = glue.register('myplugin-status')

    assert.is_not_nil(glue1)
    assert.is_not_nil(glue2)

    local contexts = glue.list_contexts('myplugin*')
    assert.is_not_nil(contexts['myplugin-maps'])
    assert.is_not_nil(contexts['myplugin-status'])
  end)
end)

describe('integration scenarios', function()
  before_each(reset_glue)

  it('should support formatting status workflow', function()
    -- Setup formatter plugin
    local formatter = glue.register('conform.nvim', {
      answers = { 'formatting.buffer-state' },
      emits = { 'formatting.state-changed' },
    })

    -- Setup statusline plugin
    local statusline = glue.register('lualine', {
      listens = { 'formatting.state-changed' },
    })

    local state_changed = false

    -- Formatter answers state queries
    formatter.answer('formatting.buffer-state', function(args)
      return { status = 'enabled', bufnr = args.bufnr }
    end)

    -- Statusline listens for changes
    statusline.listen('formatting.state-changed', function(channel, data)
      state_changed = true
    end)

    -- Query state
    local state = statusline.ask('formatting.buffer-state', { bufnr = 1 })
    assert.equals('enabled', state.status)

    -- Emit change
    formatter.emit('formatting.state-changed', { status = 'disabled' })
    assert.is_true(state_changed)
  end)

  it('should support file browser abstraction', function()
    -- Setup file browser plugins
    local neo_tree = glue.register('neo-tree', {
      listens = { 'file-browser.*' },
    })

    local oil = glue.register('oil.nvim', {
      listens = { 'file-browser.*' },
    })

    -- User config
    local user = glue.register('user-config', {
      emits = { 'file-browser.toggle' },
    })

    local neo_tree_toggled = false
    local oil_toggled = false

    neo_tree.listen('file-browser.toggle', function()
      neo_tree_toggled = true
    end)

    oil.listen('file-browser.toggle', function()
      oil_toggled = true
    end)

    -- User toggles browser
    user.emit('file-browser.toggle', {})

    -- Both plugins receive the event (in real usage, only one would be active)
    assert.is_true(neo_tree_toggled)
    assert.is_true(oil_toggled)
  end)

  it('should support translation pattern via wrapper', function()
    -- Original provider
    local original = glue.register('original-plugin')
    original.answer('old.format', function(args)
      return { state = 'active', info = 'details' }
    end)

    -- Translator plugin
    local translator = glue.register('translator')
    translator.answer('new.format', function(args)
      local old_data = translator.ask('old.format', args)
      return {
        status = old_data.state == 'active' and 'enabled' or 'disabled',
        details = old_data.info,
      }
    end)

    -- Consumer uses new format
    local consumer = glue.register('consumer')
    local result = consumer.ask('new.format', {})

    assert.equals('enabled', result.status)
    assert.equals('details', result.details)
  end)
end)
