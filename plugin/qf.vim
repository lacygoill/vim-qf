if exists('g:loaded_qf')
    finish
endif
let g:loaded_qf = 1

" TODO: Maybe implement a popup window to preview the context of some entry in the qfl.
" https://github.com/bfrg/vim-qf-preview

" Options {{{1

" don't let the default qf filetype plugin set `'stl'`, we'll do it ourselves
let g:qf_disable_statusline = 1

" Commands {{{1

" `:CC 3` loads the third qfl in the stack, regardless of your current position.
com -bar -nargs=? CC call qf#cc(<q-args>, 'c')
com -bar -nargs=? LL call qf#cc(<q-args>, 'l')
" TODO: Get rid of `:CC` and `:LL` once 8.1.1281 has been ported to Nvim.{{{
"
" The  latter  patch has  extended  `:[cl]history`  to  allow  it to  select  an
" arbitrary qfl in the stack, via a count.
"
" Just use `:[count]chi` and `:[count]lhi`.
"}}}

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
    "
    " ---
    "
    " For example,  without `++nested`, the status  line of the window  which is
    " left may be wrong whenever you open the qf window via sth like:
    "
    "     do <nomodeline> QuickFixCmdPost copen
    "
    " This is because:
    "
    "    - when `:do` is run, it triggers the next autocmd
    "
    "    - the autocmd opens the qf window, but without `++nested`, it does not trigger `WinLeave`
    "
    "    - if you update the value of `'stl'` from an autocmd listening to `WinLeave`,
    "      the value is not correctly updated
    "
    " Atm, this example only affects Nvim, and  it could be fixed in the future,
    " once we  don't need  autocmds to  set the status  line anymore  (i.e. when
    " 8.1.1372 is ported and we can  use `g:statusline_winid`); but it shows the
    " importance of  `++nested`, and  how its  absence can  create hard-to-debug
    " issues.
    "}}}
    au QuickFixCmdPost * ++nested call qf#open_auto(expand('<amatch>'))
    "  │                                            │
    "  │                                            └ name of the command which was run
    "  └ after a quickfix command is run

    au FileType qf call qf#preview#mappings()
augroup END

