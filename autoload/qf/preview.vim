if exists('g:autoloaded_qf#preview')
    finish
endif
let g:autoloaded_qf#preview = 1

" Init {{{1

if !has('nvim')
    " this tells the popup filter which keys it must handle, and how
    const s:FILTER_KEYS = {
        \ "\<m-j>": {id -> win_execute(id, 'exe "norm! \<c-e>"')},
        \ "\<m-k>": {id -> win_execute(id, 'exe "norm! \<c-y>"')},
        \ "\<m-d>": {id -> win_execute(id, 'exe "norm! \<c-d>"')},
        \ "\<m-u>": {id -> win_execute(id, 'exe "norm! \<c-u>"')},
        \ "\<m-g>": {id -> win_execute(id, 'norm! gg')},
        \ "\<m-s-g>" : {id -> win_execute(id, 'norm! G')},
        \ "\<m-m>": {-> s:set_height(-1)},
        \ "\<m-p>": {-> s:set_height(1)},
        "\ toggle number column
        \ "\<m-n>": {id -> setwinvar(id, '&number', !getwinvar(id, '&number'))},
        "\ reset topline to the line of the quickfix entry;
        "\ useful to get back to original position after scrolling
        \ "\<m-r>": {id -> [
        \     popup_setoptions(id, #{firstline: w:_qfpreview.firstline}),
        \     popup_setoptions(id, #{firstline: 0}),
        \     s:set_signcolumn(),
        \ ]},
        \ }
endif

" Interface {{{1
fu qf#preview#open(...) abort "{{{2
    " Why the `w:` scope?  Why not `b:`?{{{
    "
    " The code  would be much more  verbose/complex; you would probably  need an
    " intermediate key describing the qf window currently focused at the root of
    " the dictionary.
    "
    " Remember that a qf buffer can be  displayed in several windows at the same
    " time.
    "}}}
    if !exists('w:_qfpreview')
        let w:_qfpreview = {
            \ 'persistent': v:false,
            \ 'height': min([winheight(0), winheight(winnr('#'))/2]),
            \ }
    endif

    if a:0
        " toggle the persistent mode
        let w:_qfpreview.persistent = !w:_qfpreview.persistent
        " just close the popup when we toggle the mode off
        if !w:_qfpreview.persistent
            " Why don't you include `unlet` in `s:popup_close()`?{{{
            "
            " `s:popup_close()` is also called on `CursorMoved` and `WinLeave`.
            " We don't want  to remove the variable on these  events, because we
            " may need it to recreate the popup shortly after.
            "}}}
            call s:popup_close()
            unlet! w:_qfpreview
            return
        endif
    elseif w:_qfpreview.persistent
        " When we press `p`, it doesn't make sense to create a popup if we're in
        " persistent mode; there's already a popup.
        " In fact,  it would break the  persistent mode (the popup  would not be
        " updated anymore).
        return
    endif

    call s:popup_create()
endfu

fu qf#preview#mappings() abort
    " Why?{{{
    "
    " We currently use  `M-j` to scroll in  the popup via a filter,  but we also
    " use it to scroll in the preview window via a global mapping.
    "
    " Because of this mapping, we can't use `M-j` to scroll in the popup.
    " Indeed, the mapping is applied before the filter.
    "
    " We could fix the issue  by passing `mapping: v:false` to `popup_create()`,
    " but it would disable *all* mappings while the popup is visible.
    "}}}
    if !has('nvim')
        for key in keys(s:FILTER_KEYS)
            exe 'nno <buffer><nowait> '..key..' '..key
        endfor
        return
    endif

    nno <buffer><nowait><silent> <m-j> :<c-u>call <sid>scroll('c-e')<cr>
    nno <buffer><nowait><silent> <m-k> :<c-u>call <sid>scroll('c-y')<cr>
    nno <buffer><nowait><silent> <m-d> :<c-u>call <sid>scroll('c-d')<cr>
    nno <buffer><nowait><silent> <m-u> :<c-u>call <sid>scroll('c-u')<cr>
    nno <buffer><nowait><silent> <m-g> :<c-u>call <sid>scroll('gg')<cr>
    nno <buffer><nowait><silent> <m-s-g> :<c-u>call <sid>scroll('G')<cr>

    nno <buffer><nowait><silent> <m-m> :<c-u>call <sid>set_height(-1)<cr>
    nno <buffer><nowait><silent> <m-p> :<c-u>call <sid>set_height(+1)<cr>

    nno <buffer><nowait><silent> <m-n> :<c-u>call <sid>toggle_numbercolumn()<cr>
    nno <buffer><nowait><silent> <m-r> :<c-u>call <sid>jump_back_to_curentry()<cr>
endfu
"}}}1
" Core {{{1
fu s:popup_create() abort "{{{2
    " need some info about the window (its geometry and whether it's a location window or qf window)
    let wininfo = getwininfo(win_getid())[0]

    let items = wininfo.loclist ? getloclist(0, {'items':0}).items : getqflist({'items':0}).items
    if empty(items) | return | endif

    " need some info about the current entry in the qfl (whether it's valid, and its line number)
    let curentry = items[line('.')-1]
    if !curentry.valid | return | endif

    let opts = s:get_line_and_anchor(wininfo)
    if type(opts) != type({}) | return | endif

    let w:_qfpreview.firstline = curentry.lnum
    call extend(opts, {
        \ 'row': opts.row,
        \ 'col': wininfo.wincol,
        \ 'height': w:_qfpreview.height,
        \ 'width': wininfo.width,
        \ 'firstline': w:_qfpreview.firstline,
        \ 'filter': function('s:popup_filter'),
        "\ only filter keys in normal mode (the default is "a"; all modes)
        \ 'filtermode': 'n',
        \ })

    if !s:should_persist()
        call extend(opts, {'moved': 'any'})
    endif

    " `sil!` to suppress `E325` in case the file is already open in another Vim instance
    " See: https://github.com/vim/vim/issues/5822
    sil! let [_, w:_qfpreview.winid] = lg#popup#create(curentry.bufnr, opts)
    call s:set_signcolumn()
    call s:set_sign(curentry.bufnr, curentry.lnum)
    " hide ad-hoc characters used for syntax highlighting (like bars and stars in help files)
    call setwinvar(w:_qfpreview.winid, '&cole', 3)

    call s:close_when_quit()
    if s:should_persist()
        let w:_qfpreview.validitems = map(items, {_,v -> v.valid})
        call s:persist()
    endif
endfu

fu s:popup_close() abort "{{{2
    " Why this `if` guard?{{{
    "
    "
    "     $ vim +'helpg foobar' +'tabnew' +'tabfirst'
    "     " press "p" to preview qf entry
    "     :tabclose
    "     Error detected while processing BufWinLeave Autocommands for "<buffer=29>":~
    "     E121: Undefined variable: w:_qfpreview~
    "     E116: Invalid arguments for function popup_close~
    "
    " It appears that – in that case – when `BufWinLeave` is fired, we're not in
    " the qf window anymore, but in the window of the newly focused tab.
    "}}}
    if exists('w:_qfpreview')
        if has('nvim')
            " `nvim_win_is_valid()` is a necessary sanity check.{{{
            "
            " `lg#popup#create()` installs a `CursorMoved` autocmd to close the float
            " when the cursor moves and emulate the `moved` key from `popup_create()`.
            " Sometimes, it may close the window before this function is invoked.
            "}}}
            if nvim_win_is_valid(w:_qfpreview.winid)
                call nvim_win_close(w:_qfpreview.winid, 1)
            endif
        else
            call popup_close(w:_qfpreview.winid)
        endif
    endif
endfu

fu s:popup_filter(winid, key) abort "{{{2
    if !has_key(s:FILTER_KEYS, a:key) | return v:false | endif
    call get(s:FILTER_KEYS, a:key)(a:winid)
    return v:true
endfu

fu s:set_signcolumn() abort "{{{2
    " Why is this function called multiple times for the same popup?{{{
    "
    " For some reason, `popup_setoptions()` resets `'signcolumn'`.
    " So, whenever `popup_setoptions()` is invoked, we need to recall this function.
    "
    " If we didn't do  this, after pressing `M-m` or `M-p`  to change the height
    " of the  popup, or  `M-r` to reset  its topline, the  sign(s) would  not be
    " visible anymore.
    "}}}
    " sanity check
    if !exists('w:_qfpreview') | return | endif
    " Why `number`?  Why not `auto` or `yes`?{{{
    "
    " If we enable the number column, we don't want 2 columns (one for the signs
    " and one for the numbers); we just want one column.
    " IOW, we want to merge the two; i.e. draw the signs in the number column.
    "}}}
    call setwinvar(w:_qfpreview.winid, '&signcolumn', 'number')
    " Note that it doesn't work in Nvim; missing Vim patch: 8.1.1564
endfu

fu s:set_sign(bufnr, lnum) abort "{{{2
    " Remove possible stale sign.{{{
    "
    " It can happen if:
    "
    "    - the buffer in which you're previewing a qf entry contains more than 1 entry
    "    - you've already previewed another entry from the same buffer
    "}}}
    sil! call sign_undefine('QfPreviewCurrentEntryLine')
    " define a new sign named `QfPreviewCurrentEntryLine`, used for the previewed qf entry
    call sign_define('QfPreviewCurrentEntryLine', {'text': '>>', 'texthl': 'PopupSign'})
    " place it
    call sign_place(0, 'PopUpQfPreview', 'QfPreviewCurrentEntryLine', a:bufnr, {'lnum': a:lnum})
    "               │   │                 │{{{
    "               │   │                 └ name of the sign
    "               │   │
    "               │   └ name of the group of the sign
    "               │     (here, it *must* start with "PopUp"; see `:h sign-group /PopUp`)
    "               │
    "               └ automatically allocate a new identifier to the sign
    "}}}
endfu

fu s:close_when_quit() abort "{{{2
    " Need an augroup  to prevent the duplication of the  autocmds when we press
    " `p` several times in the same qf window.
    augroup qfpreview_close
        au! * <buffer>
        " close the popup when the qf window is closed or left
        " Why not `QuitPre` or `BufWinLeave`?{{{
        "
        " `QuitPre` is fired when we close the qf window with `:q`, but not with `:close`.
        " `BufWinLeave` is  fired when we  close the  qf window, no  matter how,
        " provided no other window still displays the qf buffer.
        "
        " But *none* of these  events is fired when we close  the qf window with
        " `:close`, and the qf buffer is still displayed somewhere.
        "
        " ---
        "
        " Besides,  if we've  enabled the  persistent mode,  and we  temporarily
        " leave the qf window (e.g. with  `:cnext`), we want to close the popup;
        " otherwise, it would hide a regular buffer as well as the cursor, which
        " is totally unexpected.
        "}}}
        au WinLeave <buffer> ++once call s:popup_close()
        if w:_qfpreview.persistent
            " re-open the popup if we've temporarily left the qf window and came back
            au WinEnter <buffer> ++once call s:fire_cursormoved()
            " Don't listen to `QuitPre` nor `WinClosed`.{{{
            "
            " The qf  buffer could still be  displayed in other windows,  and in
            " one of them the persistent mode could be enabled.
            "}}}
            " clear the autocmds when the qf buffer is no longer displayed anywhere
            au BufWinLeave <buffer> ++once call s:clear_autocmds()
        endif
    augroup END
endfu

fu s:persist() abort "{{{2
    let w:_qfpreview.lastline = line('.')
    " Need an  augroup to prevent the  duplication of the autocmds  each time we
    " move the cursor.
    augroup qfpreview_persistent
        " Is it ok to clear the augroup?  What if the buffer is displayed in several windows?{{{
        "
        " It's ok because:
        "
        "    - the autocmd is re-installed immediately afterward
        "
        "    - the command run by the autocmd is the same for all windows;
        "      it does not contain any information specific to a window;
        "      `w:_qfpreview` is a reference to a variable whose *contents*
        "      changes from one window to another,
        "      but the contents is not present right inside the command,
        "      only the *name*
        "}}}
        au! * <buffer>
        au CursorMoved <buffer> call s:update()
    augroup END
endfu

fu s:update() abort "{{{2
    let curlnum = line('.')
    " Why these checks?{{{
    "
    " This function is called from  the `qfpreview_persistent` autocmd; when the
    " latter is *installed*, you know that:
    "
    "    - `w:_qfpreview` exists
    "    - `w:_qfpreview` has a 'persistent' key which is true
    "
    " But when its command is *executed*, those assumptions may be wrong.
    " The qf buffer  may be displayed in  a different window than  the one where
    " the autocmd was installed.
    "
    " ---
    "
    " The  `lastline` check  is  just to  improve the  performance  and avoid  a
    " useless update if  we didn't move to  another line but stayed  on the same
    " line.
    "}}}
    if !exists('w:_qfpreview') || !get(w:_qfpreview, 'persistent', v:false)
       \ || w:_qfpreview.lastline == curlnum
        return
    endif
    call s:popup_close()
    let w:_qfpreview.lastline = curlnum
    let curentry_is_valid = w:_qfpreview.validitems[curlnum-1]
    if !curentry_is_valid | return | endif
    call s:popup_create()
endfu

fu s:fire_cursormoved() abort "{{{2
    " sanity check
    if !exists('w:_qfpreview') || !exists('#qfpreview_persistent#CursorMoved')
        return
    endif
    " necessary to disable a guard in `s:update()`
    let w:_qfpreview.lastline = 0
    do <nomodeline> qfpreview_persistent CursorMoved
endfu

fu s:clear_autocmds() abort "{{{2
    " Is it ok to clear these autocmds?  What if we have several windows displaying the same buffer?{{{
    "
    " It's ok if you only call this function on `BufWinLeave`.
    " When this event is  fired, we have the guarantee that the  qf buffer is no
    " longer displayed anywhere; in that case,  we can safely clear the autocmds
    " tied to the buffer.
    "}}}
    " We can't clear  the augroups because there could still  be autocmds inside
    " (but for other buffers).
    au! qfpreview_persistent * <buffer>
    au! qfpreview_close * <buffer>
endfu

"}}}1
" Util {{{1
fu s:get_line_and_anchor(wininfo) abort "{{{2
    " compute how many screen lines are available above and below the qf window
    let lines_above = s:get_lines_above()
    let lines_below = s:get_lines_below()

    " position the popup above the current window if there's enough room
    if lines_above >= w:_qfpreview.height
        " Set an anchor for the popup.{{{
        "
        " The  easiest position  we  can get  is the  upper-left  corner of  the
        " current window; via the `winrow` and `wincol` keys from `getwininfo()`.
        " We'll use a cell nearby as an anchor for our popup.
        "}}}
        let opts = {
            "\ `-1` to start *above* the topline of the qf window,
            "\ and another `-1` to not hide the statusline of the window above
            \ 'row': a:wininfo.winrow - 2,
            "\ for the popup to be aligned with the current window, we need to use the cell right above
            "\ the upper-left corner as the *bottom left* corner of the popup
            \ 'pos': 'botleft',
            \ }
    " not enough room above; try below
    elseif lines_below >= w:_qfpreview.height
        let opts = {
            "\ `+1` to not hide the status line of the window below the qf window
            \ 'row': a:wininfo.winrow + a:wininfo.height + 1,
            \ 'pos': 'topleft',
            \ }
    " still not enough room; if there's a little room above, reduce the height of the popup so that it fits
    elseif lines_above >= 5
        let w:_qfpreview.height = lines_above
        let opts = {
            \ 'row': a:wininfo.winrow - 2,
            \ 'pos': 'botleft',
            \ }
    " still not enough room; if there's a little room below, reduce the height of the popup so that it fits
    elseif lines_below >= 5
        let w:_qfpreview.height = lines_below
        let opts = {
            \ 'row': a:wininfo.winrow + a:wininfo.height + 1,
            \ 'pos': 'topleft',
            \ }
    else
        echohl ErrorMsg
        echom 'Not enough room to display popup window'
        echohl None
        unlet! w:_qfpreview
        return
    endif
    return opts
endfu

fu s:get_lines_above() abort "{{{2
    return win_screenpos(winnr())[0] - 2 - s:tabline_is_visible()
    "                                  │
    "                                  └ we don't want to use the first line of the qf window,
    "                                    and we don't want to use the status line of the window above
endfu

fu s:get_lines_below() abort "{{{2
    let n = &lines - (s:get_lines_above() + winheight(0))
    "                 │                     │ {{{
    "                 │                     └ the lines inside are also irrelevant
    "                 └ the lines above the qf window are irrelevant
    "}}}
    let n -= &cmdheight + 2 + s:tabline_is_visible()
    "        │            │   │{{{
    "        │            │   └ the tabline is irrelevant (because above)
    "        │            │
    "        │            └ the status line of the window above is irrelevant (because above),
    "        │              and we don't want to use the status line of the qf window
    "        │
    "        └ we don't want to use the line(s) of the command-line
    "}}}
    return n
endfu

fu s:should_persist() abort "{{{2
    return get(w:_qfpreview, 'persistent', v:false)
endfu

fu s:set_height(step) abort "{{{2
    " Why this check?{{{
    "
    " Suppose you include the key `+` in `s:FILTER_KEYS`:
    "
    "     \ '+': {-> s:set_height(1)},
    "
    " and then you run:
    "
    "     $ vim +'helpg foobar'
    "     " press "p" to open popup
    "     " press "C-w w" to focus other window
    "     " press "C-w +" to increase size of current window
    "     Error detected while processing function <SNR>180_popup_filter[3]..<lambda>448[1]..<SNR>180_setheight:~
    "     E121: Undefined variable: w:_qfpreview~
    "
    " In the last  `C-w +`, `C-w` is  ignored by the filter, but  not `+`, which
    " invokes this function, while the current window is not the qf window where
    " `w:_qfpreview` is set.
    "}}}
    if !exists('w:_qfpreview') | return | endif

    if s:popup_is_too_small() && a:step == -1 || s:popup_is_too_big() && a:step == 1
        return
    endif

    let w:_qfpreview.height += a:step
    if !has('nvim')
        call popup_setoptions(w:_qfpreview.winid, #{
            \ minheight: w:_qfpreview.height,
            \ maxheight: w:_qfpreview.height,
            \ })
    else
        " to preserve the topline
        let topline = getwininfo(w:_qfpreview.winid)[0].topline
        " Why don't you just use `:12res +-34`?{{{
        "
        " Doesn't work as expected (github issue #5443).
        " If it did, you could write:
        "
        "     let winnr = win_id2win(w:_qfpreview.winid)
        "     exe winnr..'res '..(a:step > 0 ? '+': '')..a:step
        "}}}
        let cmd = 'res '..(a:step > 0 ? '+' : '')..a:step
        let cmd ..= printf(' | exe "%d" | norm! zt', topline)
        call lg#win_execute(w:_qfpreview.winid, cmd)
    endif
    call s:set_signcolumn()
endfu

fu s:scroll(cmd) abort "{{{2
    if !exists('w:_qfpreview') | return | endif
    let cmd = {
        \ 'c-e': "\<c-e>",
        \ 'c-y': "\<c-y>",
        \ 'c-u': "\<c-u>",
        \ 'c-d': "\<c-d>",
        \ 'gg': 'gg',
        \ 'G': 'G',
        \ }[a:cmd]
    call lg#win_execute(w:_qfpreview.winid, 'norm! '..cmd)
endfu

fu s:toggle_numbercolumn() abort "{{{2
    if !exists('w:_qfpreview') || !nvim_win_is_valid(w:_qfpreview.winid)
        return
    endif
    let id = w:_qfpreview.winid
    call setwinvar(id, '&number', !getwinvar(id, '&number'))
endfu

fu s:jump_back_to_curentry() abort "{{{2
    if !exists('w:_qfpreview')
       \ || !nvim_win_is_valid(w:_qfpreview.winid)
        return
    endif
    call lg#win_execute(w:_qfpreview.winid, printf('exe "%d"|norm! zt', w:_qfpreview.firstline))
endfu

fu s:popup_is_where(where) abort "{{{2
    let qf_firstline = win_screenpos(winnr())[0]
    let popup_firstline = win_screenpos(w:_qfpreview.winid)[0]
    return a:where is# 'above'
        \ ? popup_firstline < qf_firstline
        \ : popup_firstline > qf_firstline
endfu

fu s:popup_is_too_small() abort "{{{2
    return w:_qfpreview.height == 1
endfu

fu s:popup_is_too_big() abort "{{{2
    let lines_above = s:get_lines_above()
    let lines_below = s:get_lines_below()
    return s:popup_is_where('below') && w:_qfpreview.height == lines_below
        \ || s:popup_is_where('above') && w:_qfpreview.height == lines_above
endfu

fu s:tabline_is_visible() abort "{{{2
    return &stal == 2 || &stal == 1 && tabpagenr('$') >= 2
endfu

