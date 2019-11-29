if exists('g:loaded_qf')
    finish
endif
let g:loaded_qf = 1

" TODO: Maybe implement a popup window to preview the context of some entry in the qfl.
" https://github.com/bfrg/vim-qf-preview

" Commands {{{1

" `:CC 3` loads the third qfl in the stack, regardless of your current position.
com -bar -nargs=1 CC  call qf#cc(<q-args>, 'c')
com -bar -nargs=1 LL  call qf#cc(<q-args>, 'l')

com -bar CFreeStack call qf#cfree_stack(0)
com -bar LFreeStack call qf#cfree_stack(1)

com -nargs=1 -range=% -addr=buffers  CGrepBuffer  call qf#cgrep_buffer(<line1>, <line2>, <q-args>, 0)
com -nargs=1 -range=% -addr=buffers  LGrepBuffer  call qf#cgrep_buffer(<line1>, <line2>, <q-args>, 1)

" Autocmds {{{1

" Automatically open the qf/ll window after a quickfix command.
augroup my_quickfix
    au!

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
    au QuickFixCmdPost * ++nested call qf#open_maybe(expand('<amatch>'))
    "  │                                             │
    "  │                                             └ name of the command which was run
    "  └ after a quickfix command is run

    au FileType qf call lg#set_stl(
        \ '%{qf#statusline#buffer()}%=    %-'..winwidth(0)/8..'(%l/%L%) ',
        \ '%{get(b:, "qf_is_loclist", 0) ? "[LL] ": "[QF] "}%=    %-'..winwidth(0)/8..'(%l/%L%) ')
augroup END

