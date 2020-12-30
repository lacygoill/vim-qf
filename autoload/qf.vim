if exists('g:autoloaded_qf')
    finish
endif
let g:autoloaded_qf = 1

" TODO:
" We shouldn't  create matches.  We shouldn't  use the complex ad  hoc mechanism
" around  `s:matches_any_qfl`.  Instead  we should  create ad  hoc syntax  file.
" Look at how Neovim has solved the issue in `ftplugin/qf.vim` for TOC menus.

" TODO: Split the code: one functionality per file.

import Catch from 'lg.vim'
import GetWinMod from 'lg/window.vim'

" Variables {{{1

const s:EFM_TYPE = #{
    \ e: 'error',
    \ w: 'warning',
    \ i: 'info',
    \ n: 'note',
    "\ we use this ad-hoc flag in `vim-stacktrace` to distinguish Vim9 errors
    "\ which are raised at compile time, from those raised at runtime
    \ c: 'compiling',
    \ }

" What's the purpose of `s:matches_any_qfl`?{{{
"
" Suppose we  have a  plugin which  populates a  qfl, opens  the qf  window, and
" applies a match.   The latter is local  to the window.  And if  we close, then
" re-open the qf window, its id changes.  So, we lose the match.
"
" To fix this, we need to achieve 2 things:
"
"    - don't apply a match directly from a third-party plugin,
"      it must be done from `after/ftplugin/qf.vim`, because the latter
"      is always sourced whenever we open a qf window
"
"      We can't  rely on the buffer  number, nor on the  window id, because
"      they both change.
"
"    - save the information of a match, so that `after/ftplugin/qf.vim`
"      can reapply it
"
" We need to bind the information of a  match (HG name, regex) to a qfl (through
" its 'context' key) or to its id.
" Atm, I don't want to use the 'context' key because it could be used by another
" third-party  plugin with  a data  type different  than a  dictionary (risk  of
" incompatibility/interference)
"
" So, instead, we bind the info to the qfl id in the variable `s:matches_any_qfl`.
"}}}
" How is it structured?{{{
"
" It stores  a dictionary  whose keys  are qfl  ids.  The  value of  a key  is a
" sub-dictionary describing matches.
"
" Each  key in  this sub-dictionary  describes an  “origin”.  By  convention, we
" build the text of an origin like this:
"
"     {plugin_name}:{function_name}
"
" This kind  of info  could be useful  when debugging.  It  tells us  from which
" function in which plugin does the match come from.
"
" Finally, the value associated to an “origin” key is a list of sub-sub-dictionaries.
" Why a  list? Because a *single* function  from a plugin could  need to install
" *several* matches.  These final sub-sub-dictionaries contain 2 keys/values:
"
"    - 'group' → HG name
"    - 'pat'   → regex
"}}}
" Example of simple value for `s:matches_any_qfl`:{{{
"
"        ┌ qf id
"        │     ┌ origin
"        │     │
"     { '1': {'myfuncs:searchTodo': [
"     \     {'group': 'Conceal', 'pat': '^.\{-}|\s*\d\+\%(\s\+col\s\+\d\+\s*\)\=\s*|\s\='},
"     \     {'group': 'Todo', 'pat': '\cfixme\|todo'}
"     \ ]}}
"}}}
" How is it used?{{{
"
" In a plugin, when we populate a qfl and want to apply a match to its window,
" we invoke:
"
"     call qf#set_matches({origin}, {HG}, {pat})
"
" It will register a match in `s:matches_any_qfl`.
" Then, we invoke `qf#create_matches()` to create the matches.
" Finally, we  also invoke  `qf#create_matches()` in  `after/ftplugin/qf.vim` so
" that the matches are re-applied whenever we close/re-open the qf window.
"
" `qf#create_matches()`  checks  whether  the  id  of  the  current  qfl  is  in
" `s:matches_any_qfl`.  If it is, it installs all the matches which are bound to
" `it.
"}}}
" Why call `qf#create_matches()` in every third-party plugin?{{{

" Why not just relying on the autocmd opening the qf window?
"
"         vim-window:
"             autocmd QuickFixCmdPost cwindow
"
"         a plugin:
"             do <nomodeline> QuickFixCmdPost cwindow
"
"                 → open qf window
"                 → FileType qf
"                 → source qf ftplugin
"                 → call qf#create_matches()
"
" So, in this scenario, we would need to set the matches BEFORE opening
" the qf window (currently we do it AFTER).
"
" First: we would need to refactor several functions.
"
"    - qf#set_matches()
"      s:get_id()
"
"      → they should be passed a numeric flag, to help them determine
"        whether we operate on a loclist or a qfl
"
"    - `s:get_id()` should stop relying on `b:qf_is_loclist`
"       and use the flag we pass instead
"
"       This is because when we would invoke `qf#set_matches()`,
"       the qf window would NOT have been opened, so there would
"       be no `b:qf_is_loclist`.
"
"       It couldn't even rely on the expression populating `b:qf_is_loclist`:
"
"         win_getid()->getwininfo()->get(0, {})->get('loclist', 0)
"
"       ... because, again, there would be no qf window yet.
"
" Second:
" Suppose the qf window  is already opened, and one of our  plugin creates a new
" qfl, with a new custom match.  It won't be applied.
"
" Why?
" Because, when `setloclist()` or `setqflist()` is invoked, if the qf window is already
" opened, it triggers `BufReadPost` → `FileType` → `Syntax`.
" So, our filetype plugin would be immediately sourced, and `qf#create_matches()` would
" be executed too early (before `qf#set_matches()` has set the match).
"
" As a result, we would need to also trigger `FileType qf`:
"
"     do <nomodeline> QuickFixCmdPost cwindow
"     if &bt isnot# 'quickfix'
"         return
"     endif
"     do <nomodeline> FileType qf
"
" To avoid sourcing the qf filetype plugin when populating the qfl, we could use
" `:noa`:
"
"     noa call setqflist(...)
"
" Conclusion:
" Even with all  that, the qf filetype  plugin would be sourced twice  if the qf
" window is not already opened.  Indeed:
"
"     vim-window:
"         autocmd QuickFixCmdPost cwindow
"
"     a plugin:
"         do <nomodeline> QuickFixCmdPost cwindow
"
" ... will fire `FileType qf` iff the window is not opened.
" I don't like a filetype plugin being sourced several times.
"}}}
let s:matches_any_qfl = {}

" What's the use of `KNOWN_PATTERNS`?{{{
"
" If you  often use the same  regex to describe some  text on which you  want to
" apply a match, add it to this  dictionary, with a telling name.  Then, instead
" of writing this:
"
"     call qf#set_matches({origin}, {HG}, {complex_regex})
"
" ... you can write this:
"
"     call qf#set_matches({origin}, {HG}, {telling_name})
"}}}
const s:KNOWN_PATTERNS = #{
    \ location: '^.\{-}|\s*\%(\d\+\)\=\s*\%(col\s\+\d\+\)\=\s*|\s\=',
    \ double_bar: '^|\s*|\s*\|\s*|\s*|\s*$',
    \ }

" `$MYVIMRC` is empty when we start with `-Nu /tmp/vimrc`.
if $MYVIMRC == ''
    let s:OTHER_PLUGINS = ['autoload/plug.vim']
else
    let s:VIMRC_FILE = $MYVIMRC
    let s:OTHER_PLUGINS = readfile(s:VIMRC_FILE) | unlet! s:VIMRC_FILE
    call filter(s:OTHER_PLUGINS, {_, v -> v =~# '^\s*Plug\s\+''\%(\%(lacygoill\)\@!\|lacygoill/vim-awk\)'})
    call map(s:OTHER_PLUGINS, {_, v -> 'plugged/' .. matchstr(v, '.\{-}/\zs[^,'']*')})
    let s:OTHER_PLUGINS += ['autoload/plug.vim']
    lockvar! s:OTHER_PLUGINS
endif

" Interface {{{1
fu qf#quit() abort "{{{2
    if reg_recording() != ''
        return feedkeys('q', 'in')[-1]
    endif
    q
endfu

def qf#align(info: dict<number>): list<string> #{{{2
    var qfl: list<any>
    if info.quickfix
        qfl = getqflist({id: info.id, items: 0}).items
    else
        qfl = getloclist(info.winid, {id: info.id, items: 0}).items
    endif
    var l: list<string>
    var lnum_width = range(info.start_idx - 1, info.end_idx - 1)
        ->map((_, v) => qfl[v].lnum)
        ->max()
        ->len()
    var col_width = range(info.start_idx - 1, info.end_idx - 1)
        ->map((_, v) => qfl[v].col)
        ->max()
        ->len()
    var pat_width = range(info.start_idx - 1, info.end_idx - 1)
        ->map((_, v) => strchars(qfl[v].pattern, 1))
        ->max()
    var fname_width = range(info.start_idx - 1, info.end_idx - 1)
        ->map((_, v) => qfl[v].bufnr->bufname()->fnamemodify(':t')->strchars(1))
        ->max()
    var type_width = range(info.start_idx - 1, info.end_idx - 1)
        ->map((_, v) => get(s:EFM_TYPE, qfl[v].type, '')->strlen())
        ->max()
    var errnum_width = range(info.start_idx - 1, info.end_idx - 1)
        ->map((_, v) => qfl[v].nr)
        ->max()
        ->len()
    for idx in range(info.start_idx - 1, info.end_idx - 1)
        var e = qfl[idx]
        if !e.valid
            add(l, '|| ' .. e.text)
        else
            # case where the entry does not  refer to a particular location in a
            # file, but just to a file as a whole (e.g. `:Find`, `:PluginsToCommit`, ...)
            if e.lnum == 0 && e.col == 0 && e.pattern == ''
                add(l, bufname(e.bufnr))
            else
                var fname = printf('%-*S', fname_width, bufname(e.bufnr)->fnamemodify(':t'))
                var lnum = printf('%*d', lnum_width, e.lnum)
                var col = printf('%*d', col_width, e.col)
                var pat = printf('%-*S', pat_width, e.pattern)
                var type = printf('%-*S', type_width, get(s:EFM_TYPE, e.type, ''))
                var errnum = ''
                if e.nr > 0
                    errnum = printf('%*d', errnum_width + 1, e.nr)
                endif
                if e.pattern == ''
                    add(l, printf('%s|%s col %s %s%s| %s', fname, lnum, col, type, errnum, e.text))
                else
                    add(l, printf('%s|%s %s%s| %s', fname, pat, type, errnum, e.text))
                endif
            endif
        endif
    endfor
    return l
enddef

fu qf#cfilter(bang, pat, mod) abort "{{{2
    try
        " get a qfl with(out) the entries we want to filter
        let list = s:getqflist()
        let pat = s:get_pat(a:pat)
        let [comp, logic] = s:get_comp_and_logic(a:bang)
        let old_size = len(list)
        call filter(list,
            \     printf('bufname(v:val.bufnr)->fnamemodify(":p") %s pat %s v:val.text %s pat',
            \     comp, logic, comp))

        if len(list) == old_size
            echo 'No entry was removed'
            return
        endif

        let title = s:get_title()->s:add_filter_indicator_to_title(a:pat, a:bang)
        let action = s:get_action(a:mod)
        call s:setqflist([], action, {'items': list, 'title': title})

        call s:maybe_resize_height()

        " tell me what you did and why
        echo printf('(%d) items were removed because they %s match %s',
            \       old_size - len(list),
            \       a:bang
            \       ?    'DID'
            \       :    'did NOT',
            \       strchars(pat, 1) <= 50
            \       ?    pat
            \       :    'the pattern')
    catch
        return s:Catch()
    endtry
endfu

fu qf#cfilter_complete(_a, _l, _p) abort "{{{2
    " We disable `-commented` because it's not reliable.
    " See fix_me in this file.
    "
    "     return join(['-commented', '-other_plugins', '-tmp'], "\n")
    return join(['-other_plugins', '-tmp'], "\n")
endfu

fu qf#cfree_stack(loclist) abort "{{{2
    if a:loclist
        call setloclist(0, [], 'f')
        lhi
    else
        call setqflist([], 'f')
        chi
    endif
endfu

fu qf#cgrep_buffer(lnum1, lnum2, pat, loclist) abort "{{{2
    let pfx1 = a:loclist ? 'l' : 'c'
    let pfx2 = a:loclist ? 'l' : ''
    let range = a:lnum1 .. ',' .. a:lnum2

    " ┌ we don't want the title of the qfl separating `:` from `cexpr`
    " │
    exe pfx1 .. 'expr []'
    "                    ┌ if the pattern is absent from a buffer,
    "                    │ it will raise an error
    "                    │
    "                    │   ┌ to prevent a possible autocmd from opening the qf window
    "                    │   │  every time the qfl is expanded; it could make Vim open
    "                    │   │  a new split for every buffer
    "                    │   │
    let cmd = printf('sil! noa %sbufdo %svimgrepadd /%s/gj %%', range, pfx2, a:pat)
    exe cmd

    exe pfx1 .. 'window'

    if a:loclist
        call setloclist(0, [], 'a', {'title': ':' .. cmd})
    else
        call setqflist([], 'a', {'title': ':' .. cmd})
    endif
endfu

fu qf#conceal() abort "{{{2
    " we don't  want to see the  middle column displaying a  pattern in location
    " window opened by an `:ltag` command
    if get(w:, 'quickfix_title', '')[: 4] is# 'ltag '
        " TODO: Is there a risk of piling up matches?
        " Should we run `clearmatches()`?
        " Should we save the id of the match, and use it in a guard?
        call matchadd('Conceal', '|.\{-}|')
        setl cocu=nvc cole=3
    endif
endfu

fu qf#create_matches() abort "{{{2
    try
        let id = s:get_id()

        let matches_this_qfl = get(s:matches_any_qfl, id, {})
        if !empty(matches_this_qfl)
            for matches_from_all_origins in values(matches_this_qfl)
                for a_match in matches_from_all_origins
                    let [group, pat] = [a_match.group, a_match.pat]
                    if group is? 'conceal'
                        setl cocu=nc cole=3
                    endif
                    let match_id = call('matchadd', [group, pat, 0, -1]
                        \ + (group is? 'conceal'
                        \    ?    [#{conceal: 'x'}]
                        \    :    []
                        \   ))
                endfor
            endfor
        endif

    catch
        return s:Catch()
    endtry
endfu

fu qf#remove_invalid_entries() abort "{{{2
    let qfl = getqflist()
    call filter(qfl, 'v:val.valid')
    let title = getqflist({'title': 0})
    call setqflist([], 'r', {'items': qfl, 'title': title})
endfu

fu qf#cupdate(mod) abort "{{{2
    try
        " to restore later
        let pos = line('.')

        " get a qfl where the text is updated
        let list = s:getqflist()
        " Why using `get()`?{{{
        "
        " `getbufline()`  should return  a list  with  a single  item, the  line
        " `lnum` in the buffer `bufnr`.
        " But, if the buffer is unloaded, it will just return an empty list.
        " From `:h getbufline()`:
        "
        "    > This function  works only  for loaded  buffers.  For  unloaded and
        "    > non-existing buffers, an empty |List| is returned.
        "
        " Therefore, if  an entry in  the qfl is present  in a buffer  which you
        " didn't visit in the past, it  won't be loaded, and `getbufline()` will
        " return an empty list.
        "
        " In this case, we want the text field to stay the same (hence `v.text`).
        "}}}
        "                                                                       │
        call map(list, {_, v -> extend(v, {'text': getbufline(v.bufnr, v.lnum)->get(0, v.text)})})
        "                       │
        "                       └ There will be a conflict between the old value
        "                         associated to the key `text`, and the new one.
        "
        "                         And   in  case   of   conflict,  by   default
        "                         `extend()` overwrites the  old value with the
        "                         new  one.
        "                         So,  in effect,  `extend()` will  replace the
        "                         old text with the new one.

        " set this new qfl
        let action = s:get_action(a:mod)
        call s:setqflist([], action, {'items': list})

        call s:maybe_resize_height()

        " restore position
        exe 'norm! ' .. pos .. 'G'
    catch
        return s:Catch()
    endtry
endfu

fu qf#conceal_or_delete(...) abort "{{{2
    if !a:0
        let &opfunc = 'qf#conceal_or_delete'
        return 'g@'
    endif
    let type = a:0 == 1 ? a:1 : 'Ex'
    " Purpose:
    "    - conceal visual block
    "    - delete anything else (and update the qfl)
    try
        if index(['char', 'line'], type) >= 0
            let range = [line("'["), line("']")]
        elseif type is# 'block'
            " We could also use:
            "
            "     let pat = '\%V.*\%V'
            "
            " ... but the match would disappear when we change the focused window,
            " probably because the visual marks would be set in another buffer.
            let [vcol1, vcol2] = [virtcol("'["), virtcol("']")]
            let pat = '\%' .. vcol1 .. 'v.*\%' .. vcol2 .. 'v.'
            call matchadd('Conceal', pat, 0, -1, #{conceal : 'x'})
            setl cocu=nc cole=3
            return
        elseif type is# 'Ex'
            let range = [a:1, a:2]
        endif
        " for future restoration
        let pos = min(range)

        " get a qfl without the entries we want to delete
        let list = s:getqflist()
        call remove(list, range[0]-1, range[1]-1)

        " we need to preserve conceal options, because our qf filetype plugin resets them
        let [cole_save, cocu_save] = [&l:cole, &l:cocu]
        " set this new qfl
        call s:setqflist([], 'r', #{items: list})
        let [&l:cole, &l:cocu] = [cole_save, cocu_save]

        call s:maybe_resize_height()

        " restore position
        exe 'norm! ' .. pos .. 'G'
    catch
        return s:Catch()
    endtry
endfu

fu qf#disable_some_keys(keys) abort "{{{2
    if !exists('b:undo_ftplugin') | let b:undo_ftplugin = 'exe' | endif
    for key in a:keys
        sil exe 'nno <buffer><nowait> ' .. key .. ' <nop>'
        let b:undo_ftplugin ..= '|exe "nunmap <buffer> ' .. key .. '"'
    endfor
endfu

fu qf#nv(errorfile) abort "{{{2
    let file = readfile(a:errorfile)
    if empty(file) | return | endif
    let title = remove(file, 0)
    " we use simple error formats suitable for a grep-like command
    let qfl = getqflist({'lines': file, 'efm': '%f:%l:%c:%m,%f:%l:%m'})
    let items = get(qfl, 'items', [])
    call setqflist([], ' ', {'items': items, 'title': title})
    cw
    return ''
endfu

fu qf#open_auto(cmd) abort "{{{2
    "             ┌ `:lh`, like `:helpg`, opens a help window (with 1st match). {{{
    "             │ But, contrary to `:helpg`, the location list is local to a window.
    "             │ Which one?
    "             │ The one where we executed `:lh`? No.
    "             │ The help window opened by `:lh`? Yes.
    "             │
    "             │ So, the ll window will NOT be associated with the window where we executed
    "             │ `:lh`, but to the help window (with 1st match).
    "             │
    "             │ And, `:cwindow` will succeed from any window, but `:lwindow` can only
    "             │ succeed from the help window (with 1st match).
    "             │ But, when `QuickFixCmdPost` is fired, this help window hasn't been created yet.
    "             │
    "             │ We need to delay `:lwindow` with a one-shot autocmd listening to `BufWinEnter`.
    "             │}}}
    if a:cmd is# 'lhelpgrep'
        "  ┌ next time a buffer is displayed in a window
        "  │                         ┌ call this function to open the location window
        "  │                         │
        au BufWinEnter * ++once call s:open('lhelpgrep')
    else
        call s:open(a:cmd)
    endif
endfu

fu s:open(cmd) abort
    "     │
    "     └ we need to know which command was executed to decide whether
    "       we open the qf window or the ll window

    "                                 ┌ all the commands populating a ll seem to begin with the letter l
    "                                 │
    let [prefix, size] = a:cmd =~# '^l'
        \ ?     ['l', getloclist(0, {'size': 0}).size]
        \ :     ['c', getqflist({'size': 0}).size]

    let mod = call('s:GetWinMod', a:cmd =~# '^l' ? [v:true] : [])
    "                                                 │
    "   flag meaning we're going to open a loc window ┘

    " Wait.  `:copen` can't populate the qfl.  How could `cmd` be `copen`?{{{
    "
    " In some of our  plugins, we may want to open the qf  window even though it
    " doesn't contain any valid entry (ex: `:Scriptnames`).
    " In that case, we execute sth like:
    "
    "     do <nomodeline> QuickFixCmdPost copen
    "     do <nomodeline> QuickFixCmdPost lopen
    "
    " In these  examples, `:copen` and  `:lopen` are not valid  commands because
    " they don't  populate a  qfl.  We  could probably use  an ad-hoc  name, but
    " `:copen`  and `:lopen`  make the  code more  readable.  The  command names
    " express our intention: we want to open the qf window unconditionally
    "}}}
    let cmd = expand('<amatch>') =~# '^[cl]open$' ? 'open' : 'window'
    if mod =~# 'vert'
        let how_to_open = mod .. ' ' .. prefix .. cmd .. ' ' .. s:get_width(a:cmd)
    else
        let how_to_open = mod .. ' ' .. prefix .. cmd .. ' ' .. max([min([10, size]), &wmh + 2])
        "                                                        │    │
        "                                                        │    └ at most 10 lines high
        "                                                        └ at least `&wmh + 2` lines high
        " Why `&wmh + 2`?{{{
        "
        " First, the number passed to `:[cl]{open|window}`  must be at least 1, even
        " if the qfl is empty.  E.g., `:lwindow 0` would raise `E939`.
        "
        " Second, if `'ea'` is  reset, and the qf window is only 1  or 2 lines high,
        " pressing Enter on the qf entry would raise `E36`.
        " In general, the issue is triggered when  the qf window is `&wmh + 1` lines
        " high or lower.
        "}}}
    endif

    " it will fail if there's no loclist
    try
        exe how_to_open
    catch
        return s:Catch()
    endtry

    if a:cmd is# 'helpgrep'
        " Why do you close the help window?{{{
        "
        "    - The focus switches to the 1st entry in the qfl;
        "      it's distracting.
        "
        "      I prefer to first have a look at all the results.
        "
        "    - If it's opened now, it will be from our current window,
        "      and it may be positioned in a weird place.
        "
        "      I prefer to open it later from the qf window;
        "      this way, they will be positioned next to each other.
        "}}}
        "   Why don't you close it for `:lh`, only `:helpg`?{{{
        "
        " Because, the location list is attached to this help window.
        " If we close it, the ll window will be closed too.
        "}}}

        " Why the delay?{{{
        "
        " It doesn't work otherwise.
        " Probably because the help window hasn't been opened yet.
        "}}}
        " Do *not* listen to any other event.{{{
        "
        " They are full of pitfalls.
        "
        " For example, `BufWinEnter` or `BufReadPost` may raise `E788` (only in Vim):
        "
        "                                                   v---------v
        "     $ vim -Nu NONE +'au QuickFixCmdPost * cw10|au bufwinenter * ++once helpc' +'helpg foobar' +'helpg wont_find_this' +'helpg wont_find_this'
        "     E788: Not allowed to edit another buffer now~
        "
        " And `BufEnter` may raise `E426` and `E433`:
        "
        "     $ vim -Nu NONE +'au QuickFixCmdPost * cw10|au bufenter * ++once helpc' +'helpg wont_find_this' +h
        "}}}
        au SafeState * ++once helpc
    endif
endfu

fu qf#open_manual(where) abort "{{{2
    let size = b:qf_is_loclist ? getloclist(0, {'size': 0}).size : getqflist({'size': 0}).size
    if empty(size) | echo (b:qf_is_loclist ? 'location' : 'quickfix') .. ' list is empty' | return | endif

    let sb_was_on = &sb | set nosb
    try
        if a:where is# 'nosplit'
            exe "norm! \<cr>zv" | return
        endif

        exe "norm! \<c-w>\<cr>zv"
        if a:where is# 'vert split'
            wincmd L
        elseif a:where is# 'tabpage'
            let orig = win_getid()
            tab sp
            let new = win_getid()
            call win_gotoid(orig)
            q
            call win_gotoid(new)
        endif
    catch
        return s:Catch()
    finally
        if sb_was_on | set sb | endif
    endtry
endfu

fu qf#set_matches(origin, group, pat) abort "{{{2
    try
        let id = s:get_id()
        if !has_key(s:matches_any_qfl, id)
            let s:matches_any_qfl[id] = {}
        endif
        let matches_this_qfl_this_origin = get(s:matches_any_qfl[id], a:origin, [])
        let pat = get(s:KNOWN_PATTERNS, a:pat, a:pat)
        call extend(s:matches_any_qfl[id], {
            \ a:origin : extend( matches_this_qfl_this_origin, [{ 'group': a:group, 'pat': pat }])
            \ })

    catch
        return s:Catch()
    endtry
endfu

fu qf#undo_ftplugin() abort "{{{2
    set bl< cul< efm< stl< wrap<
    unlet! b:qf_is_loclist

    nunmap <buffer> <c-q>
    nunmap <buffer> <c-r>

    nunmap <buffer> <c-s>
    nunmap <buffer> <c-v><c-v>
    nunmap <buffer> <c-t>

    nunmap <buffer> <cr>
    nunmap <buffer> <c-w><cr>

    nunmap <buffer> D
    nunmap <buffer> DD
    xunmap <buffer> D

    nunmap <buffer> p
    nunmap <buffer> P

    nunmap <buffer> q

    delc CRemoveInvalid

    delc Csave
    delc Crestore
    delc Cremove

    delc Cconceal
    delc Cfilter
    delc Cupdate
endfu
"}}}1
" Utilities {{{1
fu s:add_filter_indicator_to_title(title, pat, bang) abort "{{{2
    let pat = a:pat
    let bang = a:bang ? '!' : ''

    " What is this “filter indicator”?{{{
    "
    " If  the qfl  has  already been  filtered,  we don't  want  to add  another
    " `[:filter pat]`  in the  title.  Too  verbose.  Instead we  want to  add a
    " “branch” or a “concat”:
    "
    "         [:filter! pat1] [:filter! pat2]    ✘
    "         [:filter! pat1 | pat2]             ✔
    "
    "         [:filter pat1] [:filter pat2]      ✘
    "         [:filter pat1 & pat2]              ✔
    "}}}
    let filter_indicator = '\s*\[:filter' .. (a:bang ? '!' : '!\@!')
    let has_already_been_filtered = match(a:title, filter_indicator) >= 0
    return has_already_been_filtered
        \ ?     substitute(a:title, '\ze\]$', (a:bang ? ' | ' : ' \& ') .. pat, '')
        \ :     a:title .. ' [:filter' .. bang .. ' ' .. pat .. ']'
endfu

fu s:get_action(mod) abort "{{{2
    return a:mod =~# '^keep' ? ' ' : 'r'
    "                           │     │
    "                           │     └ don't create a new list, just replace the current one
    "                           └ create a new list
endfu

fu s:get_comp_and_logic(bang) abort "{{{2
    "                                ┌ the pattern MUST match the path of the buffer
    "                                │ do not make the comparison strict no matter what (`=~#`)
    "                                │ `:ilist` respects 'ignorecase'
    "                                │ `:Cfilter` should do the same
    "                                │
    "                                │     ┌ OR the text must match
    "                                │     │
    return a:bang ? ['!~', '&&'] : ['=~', '||']
    "                 │     │
    "                 │     └ AND the text must not match the pattern
    "                 └ the pattern must NOT MATCH the path of the buffer
endfu

fu s:get_id() abort "{{{2
    try
        let l:Getqflist_id = get(b:, 'qf_is_loclist', 0)
            \ ?    function('getloclist', [0] + [{'id': 0}])
            \ :    function('getqflist', [{'id': 0}])
        return Getqflist_id()->get('id', 0)
    catch
        return s:Catch()
    endtry
endfu

fu s:get_pat(pat) abort "{{{2
    let pat = a:pat

    " TODO:{{{
    " We guess the comment leader of the buffers in the qfl, by inspecting
    " the values of 'cms' in the first buffer of the qfl.
    " However, `getbufvar()` will return an empty string if we haven't visited
    " the buffer yet.
    " Find a way to warn the user that they should visit the first buffer...
    "}}}
    " FIXME: What if there are several filetypes?
    " Suppose the first buffer where there are entries is a Vim one.
    " But the second one is a python one.
    " The  entries in  the python  buffer would  be filtered  using the  comment
    " leader of Vim, which is totally wrong.
    let cml = getqflist()->get(0, {})->get('bufnr', 0)->getbufvar('&cms')
    let cml = split(cml, '%s')->matchstr('\S\+')->escape('\')
    if cml != ''
        let cml = '\V' .. cml .. '\m'
    else
        " An empty comment leader would make a pattern which matches all the time.
        " As a result, all the qfl would be emptied.
        let cml = '"'
    endif

    " In theory, `\S*` is wrong here.{{{
    "
    " In practice, I doubt it will cause false negatives, because we never use a
    " space in a session name, and because plugins names don't contain spaces.
    "
    " Anyway, I prefer some false negatives (i.e. entries which are not filtered
    " while they should),  rather than some false positives  (i.e. entries which
    " should *not* be filtered, but they are).
    "}}}
    let arg2pat = {
        \ '-commented': '^\s*' .. cml,
        \ '-other_plugins': '^\S*/\%(' .. join(s:OTHER_PLUGINS, '\|') .. '\)',
        \ '-tmp': '^\S*/\%(qfl\|session\|tmp\)/\S*\.vim',
        \ }

    " If `:Cfilter` was passed a special argument, interpret it.
    if pat =~# keys(arg2pat)->join('\|')
        let pat = split(pat, '\s\+')
        call map(pat, {_, v -> arg2pat[v]})
        let pat = join(pat, '\|')
        return pat
    else
        " If no pattern was provided, use the search register as a fallback.
        " Remove a possible couple of slashes before and after the pattern.
        " Otherwise, do nothing.
        return pat == ''
            \ ?     @/
            \ : pat =~ '^/.*/$'
            \ ?     pat[1 : -2]
            \ :     pat
    endif
endfu

fu s:get_title() abort "{{{2
    return get(b:, 'qf_is_loclist', 0)
        \ ?     getloclist(0, {'title': 0})->get('title', '')
        \ :     getqflist({'title': 0})->get('title', '')
endfu

fu s:get_width(cmd) abort "{{{2
    let title = a:cmd =~# '^l' ? getloclist(0, {'title': 0}).title : getqflist({'title': 0}).title
    if title is# 'TOC'
        let lines_length = getloclist(0, {'items': 0}).items->map('strchars(v:val.text, 1)')
        call remove(lines_length, 0) " ignore first line (it may be very long, and is not that useful)
        let longest_line = max(lines_length)
        let right_padding = 1
        " this should evaluate to the total width of the fold/number/sign columns
        let left_columns = wincol() - virtcol('.')
        let width = min([40, longest_line + right_padding + left_columns])
    else
        let width = 40
    endif
    return width
endfu

fu s:getqflist() abort "{{{2
    return get(b:, 'qf_is_loclist', 0)  ? getloclist(0) : getqflist()
endfu

fu s:maybe_resize_height() abort "{{{2
    if winwidth(0) == &columns
        " no more than 10 lines
        let newheight = min([10, s:getqflist()->len()])
        " at least 2 lines (to avoid `E36` if we've reset `'ea'`)
        let newheight = max([2, newheight])
        exe newheight .. 'wincmd _'
    endif
endfu

fu s:setqflist(...) abort "{{{2
    if get(b:, 'qf_is_loclist', 0)
        call call('setloclist', [0] + a:000)
    else
        call call('setqflist', a:000)
    endif
endfu

