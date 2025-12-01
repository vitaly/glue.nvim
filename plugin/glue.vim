" Lazy load command definitions
if !exists('g:loaded_glue')
  let g:loaded_glue = 1
  lua require('glue.commands')
endif
