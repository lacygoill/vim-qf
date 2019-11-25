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
    " Without, the status line may be wrong whenever you open the qf window via sth like:
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
    " ---
    "
    " More generally, other plugins may need to be informed when the qf window is opened.
    " See: https://github.com/romainl/vim-qf/pull/70
    "}}}
    au QuickFixCmdPost * ++nested call qf#open_maybe(expand('<amatch>'))
    "  │                                             │
    "  │                                             └ name of the command which was run
    "  └ after a quickfix command is run

    au FileType qf call lg#set_stl('qf',
        \ '%{qf#statusline#buffer()}%=    %-'..winwidth(0)/8..'(%l/%L%) ',
        \ '%{get(b:, "qf_is_loclist", 0) ? "[LL] ": "[QF] "}%=    %-'..winwidth(0)/8..'(%l/%L%) ')
augroup END

