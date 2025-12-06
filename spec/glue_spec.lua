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
      answers = { 'test.question' },
      emits = { 'test.event' },
      listens = { 'other.*' },
    })

    local ctx = glue.list_contexts('test-plugin')['test-plugin']
    assert.equals('v1.0', ctx.version)
    assert.same({ 'test.question' }, ctx.answers)
  end)

  it('works without metadata', function()
    local g = glue.register('simple')
    assert.is_function(g.answer)
    assert.is_function(g.ask)
    assert.is_function(g.emit)
    assert.is_function(g.listen)
    assert.is_function(g.clear)
  end)

  it('overwrites on re-registration', function()
    glue.register('plugin', { version = 'v1' })
    glue.register('plugin', { version = 'v2' })
    assert.equals('v2', glue.list_contexts('plugin')['plugin'].version)
  end)
end)

describe('ask/answer', function()
  before_each(reset)

  it('calls answerer and returns result', function()
    local answerer = glue.register('answerer')
    local asker = glue.register('asker')

    answerer.answer('q', function(args)
      return { got = args.x }
    end)

    local result = asker.ask('q', { x = 42 })
    assert.equals(42, result.got)
  end)

  it('returns nil when no answerer', function()
    local g = glue.register('asker')
    assert.is_nil(g.ask('missing'))
  end)

  it('requires exact channel match', function()
    local answerer = glue.register('answerer')
    local asker = glue.register('asker')

    answerer.answer('test.specific', function()
      return true
    end)

    assert.is_true(asker.ask('test.specific'))
    assert.is_nil(asker.ask('test.*'))
  end)

  it('filters by from pattern', function()
    local a1 = glue.register('conform.nvim')
    local a2 = glue.register('lsp-format')
    local asker = glue.register('asker')

    a1.answer('format', function()
      return 'conform'
    end)
    a2.answer('format', function()
      return 'lsp'
    end)

    assert.equals('conform', asker.ask('format', { from = 'conform.*' }))
  end)

  it('propagates errors', function()
    local answerer = glue.register('answerer')
    local asker = glue.register('asker')

    answerer.answer('fail', function()
      error('boom')
    end)

    assert.has_error(function()
      asker.ask('fail')
    end)
  end)
end)

describe('emit/listen', function()
  before_each(reset)

  it('calls matching listeners with data and meta', function()
    local emitter = glue.register('emitter')
    local listener = glue.register('listener')

    local received
    listener.listen('test.event', function(channel, data, meta)
      received = { channel = channel, data = data, meta = meta }
    end)

    emitter.emit('test.event', { x = 1 })

    assert.equals('test.event', received.channel)
    assert.equals(1, received.data.x)
    assert.equals('emitter', received.meta.from)
  end)

  it('matches glob patterns', function()
    local emitter = glue.register('emitter')
    local listener = glue.register('listener')

    local calls = {}
    listener.listen('test.*', function(ch)
      table.insert(calls, ch)
    end)
    listener.listen('*tree*', function(ch)
      table.insert(calls, ch)
    end)

    emitter.emit('test.foo', {})
    emitter.emit('neo-tree.toggle', {})
    emitter.emit('other', {})

    assert.equals(2, #calls)
    assert.is_true(vim.tbl_contains(calls, 'test.foo'))
    assert.is_true(vim.tbl_contains(calls, 'neo-tree.toggle'))
  end)

  it('matches ? wildcard', function()
    local emitter = glue.register('emitter')
    local listener = glue.register('listener')

    local called = false
    listener.listen('test.?', function()
      called = true
    end)

    emitter.emit('test.x', {})
    assert.is_true(called)

    called = false
    emitter.emit('test.xx', {})
    assert.is_false(called)
  end)

  it('escapes dots in patterns', function()
    local emitter = glue.register('emitter')
    local listener = glue.register('listener')

    local called = false
    listener.listen('a.b', function()
      called = true
    end)

    emitter.emit('aXb', {})
    assert.is_false(called)

    emitter.emit('a.b', {})
    assert.is_true(called)
  end)

  it('catches listener errors without crashing', function()
    local emitter = glue.register('emitter')
    glue.register('bad').listen('test', function()
      error('boom')
    end)

    local good_called = false
    glue.register('good').listen('test', function()
      good_called = true
    end)

    assert.has_no.errors(function()
      emitter.emit('test', {})
    end)
    assert.is_true(good_called)
    assert.is_true(#_G.vim._notifications > 0)
  end)
end)

describe('clear', function()
  before_each(reset)

  it('removes listener', function()
    local listener = glue.register('listener')
    local emitter = glue.register('emitter')

    local called = false
    listener.listen('test', function()
      called = true
    end)

    listener.clear('test')
    emitter.emit('test', {})
    assert.is_false(called)
  end)

  it('clears by pattern', function()
    local listener = glue.register('listener')
    local emitter = glue.register('emitter')

    local count = 0
    listener.listen('test.a', function()
      count = count + 1
    end)
    listener.listen('test.b', function()
      count = count + 1
    end)
    listener.listen('other', function()
      count = count + 1
    end)

    listener.clear('test.*')
    emitter.emit('test.a', {})
    emitter.emit('test.b', {})
    emitter.emit('other', {})
    assert.equals(1, count)
  end)

  it('only clears own listeners', function()
    local l1 = glue.register('l1')
    local l2 = glue.register('l2')
    local emitter = glue.register('emitter')

    local l1_called, l2_called = false, false
    l1.listen('test', function()
      l1_called = true
    end)
    l2.listen('test', function()
      l2_called = true
    end)

    l1.clear('test')
    emitter.emit('test', {})
    assert.is_false(l1_called)
    assert.is_true(l2_called)
  end)

  it('cleans up empty tables', function()
    local listener = glue.register('listener')
    listener.listen('test', function() end)

    listener.clear('test')
    assert.is_nil(glue.list_listeners('test')['test'])
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

  it('list_answerers filters by channel and name', function()
    glue.register('p1').answer('fmt.a', function() end)
    glue.register('p2').answer('fmt.b', function() end)
    glue.register('p2').answer('other', function() end)

    local ans = glue.list_answerers('fmt.*')
    assert.is_not_nil(ans['fmt.a'])
    assert.is_not_nil(ans['fmt.b'])
    assert.is_nil(ans['other'])

    ans = glue.list_answerers('*', 'p1')
    assert.equals(1, #ans['fmt.a'])
  end)

  it('list_listeners filters by pattern', function()
    glue.register('p1').listen('fmt.*', function() end)
    glue.register('p2').listen('file.*', function() end)

    local lst = glue.list_listeners('fmt.*')
    assert.is_not_nil(lst['fmt.*'])
    assert.is_nil(lst['file.*'])
  end)

  it('list_channels returns all channels', function()
    local p = glue.register('p')
    p.answer('ch1', function() end)
    p.listen('ch2', function() end)

    local channels = glue.list_channels()
    assert.is_true(vim.tbl_contains(channels, 'ch1'))
    assert.is_true(vim.tbl_contains(channels, 'ch2'))
  end)
end)
