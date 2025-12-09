---@diagnostic disable: undefined-field
local inspect = require('inspect')

_G.vim = {
  inspect = inspect,
  notify = function(msg, level)
    _G.vim._notifications = _G.vim._notifications or {}
    table.insert(_G.vim._notifications, { msg = msg, level = level })
  end,
  tbl_contains = function(t, value)
    for _, v in ipairs(t) do
      if v == value then
        return true
      end
    end
    return false
  end,
  log = { levels = { ERROR = 4, WARN = 3, INFO = 2, DEBUG = 1 } },
}

local glue = require('glue')

local function reset()
  glue._reset()
  _G.vim._notifications = {}
end

describe('register', function()
  before_each(reset)

  it('stores context metadata', function()
    glue.register('test-plugin', {
      version = 'v1.0',
      handles = { 'test.question', 'test.*' },
      casts = { 'test.event' },
    })

    local ctx = glue.list_contexts('test-plugin')['test-plugin']
    assert.equals('v1.0', ctx.version)
    assert.same({ 'test.question', 'test.*' }, ctx.handles)
    assert.same({ 'test.event' }, ctx.casts)
  end)

  it('works without metadata', function()
    local g = glue.register('simple')
    assert.is_function(g.handle)
    assert.is_function(g.call)
    assert.is_function(g.cast)
    assert.is_function(g.clear)
  end)

  it('overwrites on re-registration', function()
    glue.register('plugin', { version = 'v1' })
    glue.register('plugin', { version = 'v2' })
    assert.equals('v2', glue.list_contexts('plugin')['plugin'].version)
  end)
end)

describe('call/handle', function()
  before_each(reset)

  it('calls handler with channel, args and meta', function()
    local handler_glue = glue.register('handler')
    local caller = glue.register('caller')

    handler_glue.handle('q', function(channel, args, meta)
      return { channel = channel, got = args.x, from = meta.from }
    end)

    local result = caller.call('q', { x = 42 })
    assert.equals('q', result.channel)
    assert.equals(42, result.got)
    assert.equals('handler', result.from)
  end)

  it('returns nil when no handler', function()
    local g = glue.register('caller')
    assert.is_nil(g.call('missing'))
  end)

  it('matches channel against handler patterns', function()
    local handler_glue = glue.register('handler')
    local caller = glue.register('caller')

    handler_glue.handle('test.*', function(channel, args, meta)
      return channel
    end)

    assert.equals('test.specific', caller.call('test.specific'))
    assert.equals('test.foo', caller.call('test.foo'))
    assert.is_nil(caller.call('other'))
  end)

  it('filters by prefer pattern', function()
    local h1 = glue.register('conform.nvim')
    local h2 = glue.register('lsp-format')
    local caller = glue.register('caller')

    h1.handle('format', function()
      return 'conform'
    end)
    h2.handle('format', function()
      return 'lsp'
    end)

    assert.equals('conform', caller.call('format', { prefer = 'conform.*' }))
  end)

  it('tries prefer patterns in order', function()
    local h1 = glue.register('handler1')
    local h2 = glue.register('handler2')
    local caller = glue.register('caller')

    h1.handle('test', function()
      return { from = 'h1' }
    end)
    h2.handle('test', function()
      return { from = 'h2' }
    end)

    -- Try h1 first, then h2
    local result = caller.call('test', { prefer = { 'handler1', 'handler2' } })
    assert.equals('h1', result.from)

    -- Try nonexistent first, then h2
    result = caller.call('test', { prefer = { 'nonexistent', 'handler2' } })
    assert.equals('h2', result.from)
  end)

  it('supports wildcard in prefer list', function()
    local h1 = glue.register('handler1')
    local caller = glue.register('caller')

    h1.handle('test', function()
      return { found = true }
    end)

    -- Try specific first, fall back to wildcard
    local result = caller.call('test', { prefer = { 'nonexistent', '*' } })
    assert.is_not_nil(result)
    assert.is_true(result.found)
  end)

  it('remains backwards compatible with string prefer', function()
    local h1 = glue.register('handler1')
    local caller = glue.register('caller')

    h1.handle('test', function()
      return { found = true }
    end)

    -- String still works
    local result = caller.call('test', { prefer = 'handler1' })
    assert.is_not_nil(result)
    assert.is_true(result.found)
  end)

  it('propagates errors', function()
    local handler_glue = glue.register('handler')
    local caller = glue.register('caller')

    handler_glue.handle('fail', function()
      error('boom')
    end)

    assert.has_error(function()
      caller.call('fail')
    end)
  end)
end)

describe('cast/handle', function()
  before_each(reset)

  it('calls matching handlers with channel, data and meta', function()
    local caster = glue.register('caster')
    local handler_glue = glue.register('handler')

    local received
    handler_glue.handle('test.event', function(channel, data, meta)
      received = { channel = channel, data = data, meta = meta }
    end)

    caster.cast('test.event', { x = 1 })

    assert.equals('test.event', received.channel)
    assert.equals(1, received.data.x)
    assert.equals('caster', received.meta.from)
  end)

  it('matches glob patterns', function()
    local caster = glue.register('caster')
    local handler_glue = glue.register('handler')

    local calls = {}
    handler_glue.handle('test.*', function(ch)
      table.insert(calls, ch)
    end)
    handler_glue.handle('*tree*', function(ch)
      table.insert(calls, ch)
    end)

    caster.cast('test.foo', {})
    caster.cast('neo-tree.toggle', {})
    caster.cast('other', {})

    assert.equals(2, #calls)
    assert.is_true(vim.tbl_contains(calls, 'test.foo'))
    assert.is_true(vim.tbl_contains(calls, 'neo-tree.toggle'))
  end)

  it('matches ? wildcard', function()
    local caster = glue.register('caster')
    local handler_glue = glue.register('handler')

    local called = false
    handler_glue.handle('test.?', function()
      called = true
    end)

    caster.cast('test.x', {})
    assert.is_true(called)

    called = false
    caster.cast('test.xx', {})
    assert.is_false(called)
  end)

  it('escapes dots in patterns', function()
    local caster = glue.register('caster')
    local handler_glue = glue.register('handler')

    local called = false
    handler_glue.handle('a.b', function()
      called = true
    end)

    caster.cast('aXb', {})
    assert.is_false(called)

    caster.cast('a.b', {})
    assert.is_true(called)
  end)

  it('catches handler errors without crashing', function()
    local caster = glue.register('caster')
    glue.register('bad').handle('test', function()
      error('boom')
    end)

    local good_called = false
    glue.register('good').handle('test', function()
      good_called = true
    end)

    assert.has_no.errors(function()
      caster.cast('test', {})
    end)
    assert.is_true(good_called)
    assert.is_true(#_G.vim._notifications > 0)
  end)

  it('returns count of handlers called', function()
    local caster = glue.register('caster')
    glue.register('h1').handle('test', function() end)
    glue.register('h2').handle('test', function() end)
    glue.register('h3').handle('other', function() end)

    local count = caster.cast('test', {})
    assert.equals(2, count)
  end)

  it('count does not include handlers that errored', function()
    local caster = glue.register('caster')
    glue.register('bad').handle('test', function()
      error('boom')
    end)
    glue.register('good').handle('test', function() end)

    local count = caster.cast('test', {})
    assert.equals(1, count)
  end)
end)

describe('clear', function()
  before_each(reset)

  it('removes handler', function()
    local handler_glue = glue.register('handler')
    local caster = glue.register('caster')

    local called = false
    handler_glue.handle('test', function()
      called = true
    end)

    handler_glue.clear('test')
    caster.cast('test', {})
    assert.is_false(called)
  end)

  it('clears by pattern', function()
    local handler_glue = glue.register('handler')
    local caster = glue.register('caster')

    local count = 0
    handler_glue.handle('test.a', function()
      count = count + 1
    end)
    handler_glue.handle('test.b', function()
      count = count + 1
    end)
    handler_glue.handle('other', function()
      count = count + 1
    end)

    handler_glue.clear('test.*')
    caster.cast('test.a', {})
    caster.cast('test.b', {})
    caster.cast('other', {})
    assert.equals(1, count)
  end)

  it('only clears own handlers', function()
    local h1 = glue.register('h1')
    local h2 = glue.register('h2')
    local caster = glue.register('caster')

    local h1_called, h2_called = false, false
    h1.handle('test', function()
      h1_called = true
    end)
    h2.handle('test', function()
      h2_called = true
    end)

    h1.clear('test')
    caster.cast('test', {})
    assert.is_false(h1_called)
    assert.is_true(h2_called)
  end)

  it('cleans up empty tables', function()
    local handler_glue = glue.register('handler')
    handler_glue.handle('test', function() end)

    handler_glue.clear('test')
    assert.is_nil(glue.list_handlers('test')['test'])
  end)
end)

describe('introspection', function()
  before_each(reset)

  it('list_contexts filters by pattern', function()
    glue.register('conform.nvim', {})
    glue.register('lsp-format', {})
    glue.register('other', {})

    local ctx = glue.list_contexts('*form*')
    assert.is_not_nil(ctx['conform.nvim'])
    assert.is_not_nil(ctx['lsp-format'])
    assert.is_nil(ctx['other'])
  end)

  it('list_handlers filters by channel and name', function()
    glue.register('p1').handle('fmt.a', function() end)
    glue.register('p2').handle('fmt.b', function() end)
    glue.register('p2').handle('other', function() end)

    local handlers = glue.list_handlers('fmt.*')
    assert.is_not_nil(handlers['fmt.a'])
    assert.is_not_nil(handlers['fmt.b'])
    assert.is_nil(handlers['other'])

    handlers = glue.list_handlers('*', 'p1')
    assert.equals(1, #handlers['fmt.a'])
  end)

  it('list_channels returns all channels', function()
    local p = glue.register('p')
    p.handle('ch1', function() end)
    p.handle('ch2', function() end)

    local channels = glue.list_channels()
    assert.is_true(vim.tbl_contains(channels, 'ch1'))
    assert.is_true(vim.tbl_contains(channels, 'ch2'))
  end)
end)
