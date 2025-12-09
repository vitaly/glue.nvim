local glue = require('glue')

vim.api.nvim_create_user_command('Glue', function(opts)
  local args = vim.split(opts.args, '%s+')
  local verb = args[1]

  if verb == 'list' then
    local what = args[2]
    local filter1 = args[3] or '*'
    local filter2 = args[4] or '*'

    if what == 'handlers' then
      print(vim.inspect(glue.list_handlers(filter1, filter2)))
    elseif what == 'channels' then
      print(vim.inspect(glue.list_channels(filter1)))
    elseif what == 'contexts' then
      print(vim.inspect(glue.list_contexts(filter1)))
    else
      vim.notify('[glue] Unknown list target: ' .. what, vim.log.levels.ERROR)
    end
  elseif verb == 'inspect' then
    local channel = args[2] or '*'
    local handlers = glue.list_handlers(channel)

    print('=== Channel: ' .. channel .. ' ===')
    print('\nHandlers:')
    print(vim.inspect(handlers))
  else
    vim.notify('[glue] Unknown command: ' .. verb, vim.log.levels.ERROR)
  end
end, {
  nargs = '+',
  complete = function(arg_lead, cmdline, _)
    local args = vim.split(cmdline, '%s+', { trimempty = true })

    if #args == 1 or (#args == 2 and not cmdline:match('%s$')) then
      return { 'list', 'inspect' }
    elseif #args == 2 or (#args == 3 and not cmdline:match('%s$')) then
      if args[2] == 'list' then
        return { 'channels', 'contexts', 'handlers' }
      end
    end
    return {}
  end,
})
