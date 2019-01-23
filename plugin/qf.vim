if exists('g:loaded_qf')
    finish
endif
let g:loaded_qf = 1

" Commands {{{1

" `:CC 3` loads the third qfl in the stack, regardless of your current position.
com! -bar -nargs=1 CC  call qf#cc(<q-args>, 'c')
com! -bar -nargs=1 LL  call qf#cc(<q-args>, 'l')

com! -bar CFreeStack call qf#cfree_stack(0)
com! -bar LFreeStack call qf#cfree_stack(1)

com! -nargs=1 -range=% -addr=buffers  CGrepBuffer  call qf#cgrep_buffer(<line1>, <line2>, <q-args>, 0)
com! -nargs=1 -range=% -addr=buffers  LGrepBuffer  call qf#cgrep_buffer(<line1>, <line2>, <q-args>, 1)

" Autocmds {{{1

" Does a new window have a location list?{{{
"
" It may. It depends on the window from which it was created.
" When you open  a window, in the current  tabpage or in a new  one, it inherits
" every window-local  settings of the  window from  which you created  it.  This
" includes the location list.
"}}}
" How to empty it?{{{
"
" Maybe with sth like:
"
"     augroup prevent_location_list_inheritance
"         au!
"         au WinNew * sil! call setloclist(0, [], 'f')
"         " Why is the loclist of the location window never emptied?{{{
"         "
"         " Previously, I  thought the  following code was  necessary, to  prevent the
"         " autocmd from emptying the loclist of the location window:
"         "
"         "         au QuickFixCmdPre  * let s:loclist_inheritance = 1
"         "         au WinNew          * if !get(s:, 'loclist_inheritance', 0)
"         "         \|                       call setloclist(0, [])
"         "         \|                   endif
"         "         au QuickFixCmdPost * let s:loclist_inheritance = 0
"         "
"         " But it doesn't seem  to be necessary as our autocmd  opening the ll window
"         " doesn't empty the loclist of the latter (even though it causes `WinNew` to
"         " be fired, and even if we use the `nested` flag).
"         " Even when  we close /  re-open the ll  window manually, its  loclist stays
"         " intact.
"         "
"         " Theory:
"         " From `:h setloclist()`:
"         "
"         "         For a location list window, the DISPLAYED LOCATION LIST is modified.
"         "               └──────────────────┤
"         "                                  └ != regular window
"         "
"         " When WinNew is fired, there's probably NO displayed location list yet.
"         " So, the  autocmd fails to mutate  the location list, which  is good,
"         " because that's what we want anyway.
"         "
"         " Confirmed by the  fact that if we slightly delay  the autocmd, it DOES
"         " empty the loclist:
"         "
"         "         au WinNew * call timer_start(0, {-> setloclist(0, [], 'r')})
"     "}}}
"     augroup END
"}}}
" Why is it a bad idea?{{{

" When you  press `C-w  CR` in a  qf window,  Vim creates a  new window  with an
" unnamed buffer, then it tries to open  the entry in the location list on which
" you pressed the keys.
"
" If you have an autocmd emptying the location list, there won't be anything for
" Vim to display in the new window. This will raise the error:
"
"                                                      ┌─ replace current loclist
"                                                      │
"         - E42:  No Errors         , if you gave the 'r' action to `setloclist()`
"         - E776: No location list  , "               'f' "
"                                                      │
"                                                      └─ delete all loclists
"
" Besides,  at the  moment,  the  'f' (free)  action  passed to  `setloclist()`
" doesn't exist in Neovim.
"}}}

" Automatically open the qf/ll window after a quickfix command.
augroup my_quickfix
    au!

    " FIXME:
    "     https://github.com/romainl/vim-qf/pull/70
    "
    " Should we re-add the nested flag in all autocmds in this plugin?

    "  ┌─ after a quickfix command is run
    "  │                                             ┌─ expanded into the name of the command
    "  │                                             │  which was run
    "  │                                             │
    au QuickFixCmdPost * call qf#open_maybe(expand('<amatch>'))

    " show position in quickfix list (not in location list)
    " location list is too easily populated by various commands (like `:Man`)
    au QuickFixCmdPost [^l]* call qf#stl_position()
augroup END

