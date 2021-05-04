vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# Interface {{{1
def qf#preview#open(persistent = false) #{{{2
    # Why the `w:` scope?  Why not `b:`?{{{
    #
    # The code  would be much more  verbose/complex; you would probably  need an
    # intermediate key describing the qf window currently focused at the root of
    # the dictionary.
    #
    # Remember that a qf buffer can be  displayed in several windows at the same
    # time.
    #}}}
    if !exists('w:_qfpreview')
        w:_qfpreview = {
            persistent: false,
            height: GetWinheight(),
        }
        # increase the height of the window when we zoom the tmux pane where Vim is displayed
        augroup QfpreviewResetHeight
            au! * <buffer>
            au VimResized <buffer> w:_qfpreview.height = GetWinheight()
                | PopupClose()
                | qf#preview#open()
        augroup END
    endif

    if persistent
        # toggle the persistent mode
        w:_qfpreview.persistent = !w:_qfpreview.persistent
        # just close the popup when we toggle the mode off
        if !w:_qfpreview.persistent
            # Why don't you include `unlet` in `PopupClose()`?{{{
            #
            # `PopupClose()` is also called on `CursorMoved` and `WinLeave`.
            # We don't want  to remove the variable on these  events, because we
            # may need it to recreate the popup shortly after.
            #}}}
            PopupClose()
            unlet! w:_qfpreview
            return
        endif
    elseif w:_qfpreview.persistent
        # When we press `p`, it doesn't make sense to create a popup if we're in
        # persistent mode; there's already a popup.
        # In fact,  it would break the  persistent mode (the popup  would not be
        # updated anymore).
        return
    endif

    PopupCreate()
enddef

def qf#preview#mappings()
    # Purpose of this function:{{{
    #
    # We currently  use `M-m` as a  prefix for various commands  which highlight
    # lines.   Because of  this,  we can't  use `M-m`  to  decrease the  popup's
    # height.  Indeed, mappings are applied before popup filters.
    #
    # We could fix the issue by passing `mapping: false` to `PopupCreate()`, but
    # it would disable *all* mappings while the popup is visible.
    #}}}
    if !exists('b:undo_ftplugin')
        b:undo_ftplugin = 'exe'
    endif
    for key in FILTER_LHS
        exe 'nno <buffer><nowait> ' .. key .. ' ' .. key
        var unmap_cmd: string = '|exe "nunmap <buffer> ' .. key .. '"'
        # sanity check; unmapping the same key twice could raise an error
        if stridx(b:undo_ftplugin, unmap_cmd) == -1
            b:undo_ftplugin ..= unmap_cmd
        endif
    endfor
enddef
#}}}1
# Core {{{1
def PopupCreate() #{{{2
    # need some info about the window (its geometry and whether it's a location window or qf window)
    var wininfo: dict<any> = win_getid()->getwininfo()[0]

    var items: list<dict<any>> = wininfo.loclist
        ?     getloclist(0, {items: 0}).items
        :     getqflist({items: 0}).items
    if empty(items)
        return
    endif

    # need some info about the current entry in the qfl (whether it's valid, and its line number)
    var curentry: dict<any> = items[line('.') - 1]
    if !curentry.valid
        return
    endif

    var opts: dict<any> = GetLineAndAnchor(wininfo)
    if typename(opts) !~ '^dict'
        return
    endif

    w:_qfpreview.firstline = curentry.lnum
    extend(opts, {
        line: opts.line,
        col: wininfo.wincol,
        height: w:_qfpreview.height,
        width: wininfo.width,
        firstline: w:_qfpreview.firstline,
        filter: PopupFilter,
        # only filter keys in normal mode (the default is "a"; all modes)
        filtermode: 'n',
    })

    if !ShouldPersist()
        opts.moved = 'any'
    endif

    # `:nos` to suppress `E325` in case the file is already open in another Vim instance
    # See: https://github.com/vim/vim/issues/5822
    nos w:_qfpreview.winid = Popup_create(curentry.bufnr, opts)[1]
    SetSigncolumn()
    SetSign(curentry.bufnr, curentry.lnum)
    # hide ad-hoc characters used for syntax highlighting (like bars and stars in help files)
    setwinvar(w:_qfpreview.winid, '&cole', 3)

    CloseWhenQuit()
    if ShouldPersist()
        w:_qfpreview.validitems = items->mapnew((_, v: dict<any>): bool => v.valid)
        Persist()
    endif
enddef

def PopupClose() #{{{2
    # Why this `if` guard?{{{
    #
    #
    #     $ vim +'helpg foobar' +'tabnew' +'tabfirst'
    #     " press "p" to preview qf entry
    #     :tabclose
    #     Error detected while processing BufWinLeave Autocommands for "<buffer=29>":~
    #     E121: Undefined variable: w:_qfpreview~
    #     E116: Invalid arguments for function popup_close~
    #
    # It appears that – in that case – when `BufWinLeave` is fired, we're not in
    # the qf window anymore, but in the window of the newly focused tab.
    #}}}
    if exists('w:_qfpreview')
        popup_close(w:_qfpreview.winid)
    endif
enddef

def PopupFilter(winid: number, key: string): bool #{{{2
    if !FILTER_CMD->has_key(key)
        return false
    endif
    get(FILTER_CMD, key)(winid)
    return true
enddef

def SetSigncolumn() #{{{2
    # Why is this function called multiple times for the same popup?{{{
    #
    # For some reason, `popup_setoptions()` resets `'signcolumn'`.
    # So, whenever `popup_setoptions()` is invoked, we need to recall this function.
    #
    # If we didn't do  this, after pressing `M-m` or `M-p`  to change the height
    # of the  popup, or  `M-r` to reset  its topline, the  sign(s) would  not be
    # visible anymore.
    #}}}
    # sanity check
    if !exists('w:_qfpreview')
        return
    endif
    # Why `number`?  Why not `auto` or `yes`?{{{
    #
    # If we enable the number column, we don't want 2 columns (one for the signs
    # and one for the numbers); we just want one column.
    # IOW, we want to merge the two; i.e. draw the signs in the number column.
    #}}}
    setwinvar(w:_qfpreview.winid, '&signcolumn', 'number')
enddef

def SetSign(bufnr: number, lnum: number) #{{{2
    # Remove possible stale sign.{{{
    #
    # It can happen if:
    #
    #    - the buffer in which you're previewing a qf entry contains more than 1 entry
    #    - you've already previewed another entry from the same buffer
    #}}}
    sil! sign_undefine('QfPreviewCurrentEntryLine')
    # define a new sign named `QfPreviewCurrentEntryLine`, used for the previewed qf entry
    sign_define('QfPreviewCurrentEntryLine', {text: '>>', texthl: 'PopupSign'})
    # place it
    sign_place(0, 'PopUpQfPreview', 'QfPreviewCurrentEntryLine', bufnr, {lnum: lnum})
    #          │   │                 │{{{
    #          │   │                 └ name of the sign
    #          │   │
    #          │   └ name of the group of the sign
    #          │     (here, it *must* start with "PopUp"; see `:h sign-group /PopUp`)
    #          │
    #          └ automatically allocate a new identifier to the sign
    #}}}
enddef

def CloseWhenQuit() #{{{2
    # Need an augroup  to prevent the duplication of the  autocmds when we press
    # `p` several times in the same qf window.
    augroup QfpreviewClose
        au! * <buffer>
        # close the popup when the qf window is closed or left
        # Why not `QuitPre` or `BufWinLeave`?{{{
        #
        # `QuitPre` is fired when we close the qf window with `:q`, but not with `:close`.
        # `BufWinLeave` is  fired when we  close the  qf window, no  matter how,
        # provided no other window still displays the qf buffer.
        #
        # But *none* of these  events is fired when we close  the qf window with
        # `:close`, and the qf buffer is still displayed somewhere.
        #
        # ---
        #
        # Besides,  if we've  enabled the  persistent mode,  and we  temporarily
        # leave the qf window (e.g. with  `:cnext`), we want to close the popup;
        # otherwise, it would hide a regular buffer as well as the cursor, which
        # is totally unexpected.
        #}}}
        au WinLeave <buffer> ++once PopupClose()
        if w:_qfpreview.persistent
            # re-open the popup if we've temporarily left the qf window and came back
            au WinEnter <buffer> ++once FireCursormoved()
            # Don't listen to `QuitPre` nor `WinClosed`.{{{
            #
            # The qf  buffer could still be  displayed in other windows,  and in
            # one of them the persistent mode could be enabled.
            #}}}
            # clear the autocmds when the qf buffer is no longer displayed anywhere
            au BufWinLeave <buffer> ++once ClearAutocmds()
        endif
    augroup END
enddef

def Persist() #{{{2
    w:_qfpreview.lastline = line('.')
    # Need an  augroup to prevent the  duplication of the autocmds  each time we
    # move the cursor.
    augroup QfpreviewPersistent
        # Is it ok to clear the augroup?  What if the buffer is displayed in several windows?{{{
        #
        # It's ok because:
        #
        #    - the autocmd is re-installed immediately afterward
        #
        #    - the command run by the autocmd is the same for all windows;
        #      it does not contain any information specific to a window;
        #      `w:_qfpreview` is a reference to a variable whose *contents*
        #      changes from one window to another,
        #      but the contents is not present right inside the command,
        #      only the *name*
        #}}}
        au! * <buffer>
        au CursorMoved <buffer> Update()
    augroup END
enddef

def Update() #{{{2
    var curlnum: number = line('.')
    # Why these checks?{{{
    #
    # This function is called from  the `QfpreviewPersistent` autocmd; when the
    # latter is *installed*, you know that:
    #
    #    - `w:_qfpreview` exists
    #    - `w:_qfpreview` has a 'persistent' key which is true
    #
    # But when its command is *executed*, those assumptions may be wrong.
    # The qf buffer  may be displayed in  a different window than  the one where
    # the autocmd was installed.
    #
    # ---
    #
    # The  `lastline` check  is  just to  improve the  performance  and avoid  a
    # useless update if  we didn't move to  another line but stayed  on the same
    # line.
    #}}}
    if !exists('w:_qfpreview') || !get(w:_qfpreview, 'persistent', false)
       || w:_qfpreview.lastline == curlnum
        return
    endif
    PopupClose()
    w:_qfpreview.lastline = curlnum
    var curentry_is_valid: bool = w:_qfpreview.validitems[curlnum - 1]
    if !curentry_is_valid
        return
    endif
    PopupCreate()
enddef

def FireCursormoved() #{{{2
    # sanity check
    if !exists('w:_qfpreview')
    || !exists('#QfpreviewPersistent#CursorMoved')
        return
    endif
    # necessary to disable a guard in `Update()`
    w:_qfpreview.lastline = 0
    do <nomodeline> QfpreviewPersistent CursorMoved
enddef

def ClearAutocmds() #{{{2
    # Is it ok to clear these autocmds?  What if we have several windows displaying the same buffer?{{{
    #
    # It's ok if you only call this function on `BufWinLeave`.
    # When this event is  fired, we have the guarantee that the  qf buffer is no
    # longer displayed anywhere; in that case,  we can safely clear the autocmds
    # tied to the buffer.
    #}}}
    # We can't clear  the augroups because there could still  be autocmds inside
    # (but for other buffers).
    au! QfpreviewPersistent * <buffer=abuf>
    au! QfpreviewClose * <buffer=abuf>
enddef
#}}}1
# Util {{{1
def GetWinheight(): number #{{{2
    var curheight: number = winheight(0)
    var prevheight: number = winnr('#')->winheight()
    var height: number = [curheight, prevheight / 2]->min()
    # if the qf  window is really small  (e.g. 2 lines), let's make  sure we can
    # see enough context
    return [5, height]->max()
enddef

def GetLineAndAnchor(wininfo: dict<any>): dict<any> #{{{2
    # compute how many screen lines are available above and below the qf window
    var lines_above: number = GetLinesAbove()
    var lines_below: number = GetLinesBelow()

    var opts: dict<any>
    # position the popup above the current window if there's enough room
    if lines_above >= w:_qfpreview.height
        # Set an anchor for the popup.{{{
        #
        # The  easiest position  we  can get  is the  upper-left  corner of  the
        # current window; via the `winrow` and `wincol` keys from `getwininfo()`.
        # We'll use a cell nearby as an anchor for our popup.
        #}}}
        opts = {
            # `-1` to start *above* the topline of the qf window,
            # and another `-1` to not hide the statusline of the window above
            line: wininfo.winrow - 2,
            # for the popup to be aligned with the current window, we need to use the cell right above
            # the upper-left corner as the *bottom left* corner of the popup
            pos: 'botleft',
        }
    # not enough room above; try below
    elseif lines_below >= w:_qfpreview.height
        opts = {
            # `+1` to not hide the status line of the window below the qf window
            line: wininfo.winrow + wininfo.height + 1,
            pos: 'topleft',
        }
    # still not enough room; if there's a little room above, reduce the height of the popup so that it fits
    elseif lines_above >= 5
        w:_qfpreview.height = lines_above
        opts = {
            line: wininfo.winrow - 2,
            pos: 'botleft',
        }
    # still not enough room; if there's a little room below, reduce the height of the popup so that it fits
    elseif lines_below >= 5
        w:_qfpreview.height = lines_below
        opts = {
            line: wininfo.winrow + wininfo.height + 1,
            pos: 'topleft',
        }
    else
        echohl ErrorMsg
        echom 'Not enough room to display popup window'
        echohl None
        unlet! w:_qfpreview
        return {}
    endif
    return opts
enddef

def GetLinesAbove(): number #{{{2
    return winnr()->win_screenpos()[0] - 2 - (TablineIsVisible() ? 1 : 0)
    #                                    │
    #                                    └ we don't want to use the first line of the qf window,
    #                                      and we don't want to use the status line of the window above
enddef

def GetLinesBelow(): number #{{{2
    var n: number = &lines - (GetLinesAbove() + winheight(0))
    #                         │                 │ {{{
    #                         │                 └ the lines inside are also irrelevant
    #                         └ the lines above the qf window are irrelevant
    #}}}
    n -= &cmdheight + 2 + (TablineIsVisible() ? 1 : 0)
    #    │            │    │{{{
    #    │            │    └ the tabline is irrelevant (because above)
    #    │            │
    #    │            └ the status line of the window above is irrelevant (because above),
    #    │              and we don't want to use the status line of the qf window
    #    │
    #    └ we don't want to use the line(s) of the command-line
    #}}}
    return n
enddef

def ShouldPersist(): bool #{{{2
    return get(w:_qfpreview, 'persistent', false)
enddef

def SetHeight(step: number) #{{{2
    # Why this check?{{{
    #
    # Suppose you include the key `+` in `FILTER_CMD`:
    #
    #     \ '+': (_) => SetHeight(1),
    #
    # and then you run:
    #
    #     $ vim +'helpg foobar'
    #     " press "p" to open popup
    #     " press "C-w w" to focus other window
    #     " press "C-w +" to increase size of current window
    #     Error detected while processing function <SNR>180_popup_filter[3]..<lambda>448[1]..<SNR>180_setheight:~
    #     E121: Undefined variable: w:_qfpreview~
    #
    # In the last  `C-w +`, `C-w` is  ignored by the filter, but  not `+`, which
    # invokes this function, while the current window is not the qf window where
    # `w:_qfpreview` is set.
    #}}}
    if !exists('w:_qfpreview')
        return
    endif

    if PopupIsTooSmall() && step == -1
    || PopupIsTooBig() && step == 1
        return
    endif

    w:_qfpreview.height += step
    popup_setoptions(w:_qfpreview.winid, {
        minheight: w:_qfpreview.height,
        maxheight: w:_qfpreview.height,
    })
    SetSigncolumn()
enddef

def PopupIsWhere(where: string): bool #{{{2
    var qf_firstline: number = winnr()->win_screenpos()[0]
    var popup_firstline: number = win_screenpos(w:_qfpreview.winid)[0]
    return where == 'above'
        ? popup_firstline < qf_firstline
        : popup_firstline > qf_firstline
enddef

def PopupIsTooSmall(): bool #{{{2
    return w:_qfpreview.height == 1
enddef

def PopupIsTooBig(): bool #{{{2
    var lines_above: number = GetLinesAbove()
    var lines_below: number = GetLinesBelow()
    return PopupIsWhere('below') && w:_qfpreview.height == lines_below
        || PopupIsWhere('above') && w:_qfpreview.height == lines_above
enddef

def TablineIsVisible(): bool #{{{2
    return &stal == 2 || &stal == 1 && tabpagenr('$') >= 2
enddef
#}}}1
# Init {{{1

import MapMetaChord from 'lg/map.vim'
import Popup_create from 'lg/popup.vim'

# this tells the popup filter which keys it must handle, and how
const FILTER_CMD: dict<func> = {
    [MapMetaChord('m')]: (_) => SetHeight(-1),
    [MapMetaChord('p')]: (_) => SetHeight(1),
    # toggle number column
    [MapMetaChord('n')]: (id: number) => (!getwinvar(id, '&number'))->setwinvar(id, '&number'),
    # reset topline to the line of the quickfix entry;
    # useful to get back to original position after scrolling
    [MapMetaChord('r')]: (id: number) => {
        popup_setoptions(id, {firstline: w:_qfpreview.firstline})
        popup_setoptions(id, {firstline: 0})
        SetSigncolumn()
    }}

const FILTER_LHS: list<string> = ['m', 'p', 'n', 'r']
    ->map((_, v: string): string => MapMetaChord(v, true))
    #                                               ^--^
    #                                               don't translate the chords; we need symbolic notations

