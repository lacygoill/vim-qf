if exists('g:loaded_qf')
    finish
endif
let g:loaded_qf = 1

" TODO: Maybe implement a popup window to preview the context of some entry in the qfl.
" https://github.com/bfrg/vim-qf-preview

" TODO: Implement a mapping/command which would fold all entries belonging to the same file.
" See here for inspiration: https://github.com/fcpg/vim-kickfix

" TODO: Add  custom  syntax highlighting  so  that  entries  from one  file  are
" highlighted  in one  way, while  the next  extries from  a different  file are
" highlighted in another way.
" See here for inspiration: https://github.com/fcpg/vim-kickfix

" Options {{{1

" don't let the default qf filetype plugin set `'stl'`, we'll do it ourselves
let g:qf_disable_statusline = 1

" Commands {{{1

com -bar CFreeStack call qf#cfree_stack(0)
com -bar LFreeStack call qf#cfree_stack(1)

com -nargs=1 -range=% -addr=buffers CGrepBuffer call qf#cgrep_buffer(<line1>, <line2>, <q-args>, 0)
com -nargs=1 -range=% -addr=buffers LGrepBuffer call qf#cgrep_buffer(<line1>, <line2>, <q-args>, 1)

" Autocmds {{{1

" Automatically open the qf/ll window after a quickfix command.
augroup my_quickfix | au!

    " Do *not* remove the `++nested` flag.{{{
    "
    " Other plugins may need to be informed when the qf window is opened.
    " See: https://github.com/romainl/vim-qf/pull/70
    "}}}
    au QuickFixCmdPost * ++nested call qf#open_auto(expand('<amatch>'))
    "  │                                            │
    "  │                                            └ name of the command which was run
    "  └ after a quickfix command is run

    au FileType qf call qf#preview#mappings()
augroup END

