vim9script noclear

# TODO:
# We shouldn't  create matches.  We shouldn't  use the complex ad  hoc mechanism
# around  `matches_any_qfl`.  Instead  we should  create ad  hoc syntax  file.
# Look at how Neovim has solved the issue in `ftplugin/qf.vim` for TOC menus.

# TODO: Split the code: one feature per file.

import 'lg.vim'
import 'lg/window.vim'

# Variables {{{1

const EFM_TYPE: dict<string> = {
    e: 'error',
    w: 'warning',
    i: 'info',
    n: 'note',
    # we use  this ad-hoc  flag in `vim-stacktrace`  to distinguish  Vim9 errors
    # which are given at compile time, from those given at runtime
    c: 'compiling',
}

# What's the purpose of `matches_any_qfl`?{{{
#
# Suppose we  have a  plugin which  populates a  qfl, opens  the qf  window, and
# applies a match.   The latter is local  to the window.  And if  we close, then
# re-open the qf window, its id changes.  So, we lose the match.
#
# To fix this, we need to achieve 2 things:
#
#    - don't apply a match directly from a third-party plugin,
#      it must be done from `after/ftplugin/qf.vim`, because the latter
#      is always sourced whenever we open a qf window
#
#      We can't  rely on the buffer  number, nor on the  window id, because
#      they both change.
#
#    - save the information of a match, so that `after/ftplugin/qf.vim`
#      can reapply it
#
# We need to bind the information of a  match (HG name, regex) to a qfl (through
# its 'context' key) or to its id.
# Atm, I don't want to use the 'context' key because it could be used by another
# third-party  plugin with  a data  type different  than a  dictionary (risk  of
# incompatibility/interference)
#
# So, instead, we bind the info to the qfl id in the variable `matches_any_qfl`.
#}}}
# How is it structured?{{{
#
# It stores  a dictionary  whose keys  are qfl  ids.  The  value of  a key  is a
# sub-dictionary describing matches.
#
# Each  key in  this sub-dictionary  describes an  “origin”.  By  convention, we
# build the text of an origin like this:
#
#     {plugin_name}:{function_name}
#
# This kind  of info  could be useful  when debugging.  It  tells us  from which
# function in which plugin does the match come from.
#
# Finally, the value associated to an “origin” key is a list of sub-sub-dictionaries.
# Why a  list? Because a *single* function  from a plugin could  need to install
# *several* matches.  These final sub-sub-dictionaries contain 2 keys/values:
#
#    - 'group' → HG name
#    - 'pat'   → regex
#}}}
# Example of simple value for `matches_any_qfl`:{{{
#
#        ┌ qf id
#        │     ┌ origin
#        │     │
#     { '1': {'myfuncs:searchTodo': [
#     \     {'group': 'Conceal', 'pat': '^.\{-}|\s*\d\+\%(\s\+col\s\+\d\+\s*\)\=\s*|\s\='},
#     \     {'group': 'Todo', 'pat': '\cfixme\|todo'}
#     \ ]}}
#}}}
# How is it used?{{{
#
# In a plugin, when we populate a qfl and want to apply a match to its window,
# we invoke:
#
#     SetMatches({origin}, {HG}, {pat})
#
# It will register a match in `matches_any_qfl`.
# Then, we invoke `CreateMatches()` to create the matches.
# Finally, we  also invoke `CreateMatches()` in  `after/ftplugin/qf.vim` so that
# the matches are re-applied whenever we close/re-open the qf window.
#
# `CreateMatches()`  checks   whether  the   id  of  the   current  qfl   is  in
# `matches_any_qfl`.  If it  is, it installs all the matches  which are bound to
# it.
#}}}
# Why call `CreateMatches()` in every third-party plugin?{{{

# Why not just relying on the autocmd opening the qf window?
#
#         vim-window:
#             autocmd QuickFixCmdPost cwindow
#
#         a plugin:
#             doautocmd <nomodeline> QuickFixCmdPost cwindow
#
#                 → open qf window
#                 → FileType qf
#                 → source qf ftplugin
#                 → call CreateMatches()
#
# So, in this scenario, we would need to set the matches BEFORE opening
# the qf window (currently we do it AFTER).
#
# First: we would need to refactor several functions.
#
#    - SetMatches()
#      GetId()
#
#      → they should be passed a numeric flag, to help them determine
#        whether we operate on a loclist or a qfl
#
#    - `GetId()` should stop relying on `win_gettype()`
#       and use the flag we pass instead
#
#       This is because when we would invoke `SetMatches()`,
#       the qf window would NOT have been opened, so `win_gettype()`
#       would be wrong.
#
# Second:
# Suppose the qf window  is already opened, and one of our  plugin creates a new
# qfl, with a new custom match.  It won't be applied.
#
# Why?
# Because, when `setloclist()` or `setqflist()` is invoked, if the qf window is already
# opened, it triggers `BufReadPost` → `FileType` → `Syntax`.
# So, our  filetype plugin would  be immediately sourced,  and `CreateMatches()`
# would be executed too early (before `SetMatches()` has set the match).
#
# As a result, we would need to also trigger `FileType qf`:
#
#     doautocmd <nomodeline> QuickFixCmdPost cwindow
#     if &buftype != 'quickfix'
#         return
#     endif
#     doautocmd <nomodeline> FileType qf
#
# To avoid sourcing the qf filetype plugin when populating the qfl, we could use
# `:noautocmd`:
#
#     noautocmd call setqflist(...)
#
# Conclusion:
# Even with all  that, the qf filetype  plugin would be sourced twice  if the qf
# window is not already opened.  Indeed:
#
#     vim-window:
#         autocmd QuickFixCmdPost cwindow
#
#     a plugin:
#         doautocmd <nomodeline> QuickFixCmdPost cwindow
#
# ... will fire `FileType qf` iff the window is not opened.
# I don't like a filetype plugin being sourced several times.
#}}}
var matches_any_qfl: dict<dict<list<dict<string>>>>

# What's the use of `KNOWN_PATTERNS`?{{{
#
# If you  often use the same  regex to describe some  text on which you  want to
# apply a match, add it to this  dictionary, with a telling name.  Then, instead
# of writing this:
#
#     SetMatches({origin}, {HG}, {complex_regex})
#
# ... you can write this:
#
#     SetMatches({origin}, {HG}, {telling_name})
#}}}
const KNOWN_PATTERNS: dict<string> = {
    location: '^.\{-}|\s*\%(\d\+\)\=\s*\%(col\s\+\d\+\)\=\s*|\s\=',
    double_bar: '^|\s*|\s*\|\s*|\s*|\s*$',
}

var VENDOR: list<string>
# `$MYVIMRC` is empty when we start with `-Nu /tmp/vimrc`.
if $MYVIMRC != ''
    import $MYVIMRC as vimrc
    VENDOR = vimrc.VENDOR
    lockvar! VENDOR
endif

# Interface {{{1
export def Quit() #{{{2
    if reg_recording() != ''
        feedkeys('q', 'in')
        return
    endif
    quit
enddef

export def Align(info: dict<number>): list<string> #{{{2
    var qfl: list<any>
    if info.quickfix
        qfl = getqflist({id: info.id, items: 0}).items
    else
        qfl = getloclist(info.winid, {id: info.id, items: 0}).items
    endif
    var l: list<string>
    var range: list<number> = range(info.start_idx - 1, info.end_idx - 1)
    var lnum_width: number = range
        ->copy()
        ->map((_, v: number) => qfl[v]['lnum'])
        ->max()
        ->len()
    var col_width: number = range
        ->copy()
        ->map((_, v: number) => qfl[v]['col'])
        ->max()
        ->len()
    var pat_width: number = range
        ->copy()
        ->map((_, v: number) => strcharlen(qfl[v]['pattern']))
        ->max()
    var fname_width: number = range
        ->copy()
        ->map((_, v: number) =>
            qfl[v]['bufnr']->bufname()->fnamemodify(':t')->strcharlen())
        ->max()
    var type_width: number = range
        ->copy()
        ->map((_, v: number) =>
            get(EFM_TYPE, qfl[v]['type'], '')->strcharlen())
        ->max()
    var errnum_width: number = range
        ->copy()
        ->map((_, v: number) => qfl[v]['nr'])
        ->max()
        ->len()
    for idx: number in range
        var e: dict<any> = qfl[idx]
        if !e.valid
            l->add($'|| {e.text}')
        # happens  if you  re-open  the  qf window  after  wiping  out a  buffer
        # containing an entry from the qfl
        elseif e.bufnr == 0
            l->add('the buffer no longer exists')
        else
            # case where the entry does not  refer to a particular location in a
            # file, but just to a file as a whole (e.g. `:Find`, `:PluginsToCommit`, ...)
            if e.lnum == 0 && e.col == 0 && e.pattern == ''
                l->add(bufname(e.bufnr))
            else
                var fname: string = printf('%-*S', fname_width, bufname(e.bufnr)
                    ->fnamemodify(full_filepath ? ':p' : ':t'))
                var lnum: string = printf('%*d', lnum_width, e.lnum)
                var col: string = printf('%*d', col_width, e.col)
                var pat: string = printf('%-*S', pat_width, e.pattern)
                var type: string = printf('%-*S', type_width, get(EFM_TYPE, e.type, ''))
                var errnum: string = ''
                if e.nr > 0
                    errnum = printf('%*d', errnum_width + 1, e.nr)
                endif
                if e.pattern == ''
                    l->add(printf('%s|%s col %s %s%s| %s', fname, lnum, col, type, errnum, e.text))
                else
                    l->add(printf('%s|%s %s%s| %s', fname, pat, type, errnum, e.text))
                endif
            endif
        endif
    endfor
    return l
enddef

export def Cfilter( #{{{2
    bang: bool,
    arg_pat: string,
    mod: string
)
    # get a qfl with(out) the entries we want to filter
    var list: list<dict<any>> = Getqflist()
    var pat: string = GetPat(arg_pat)
    var old_size: number = len(list)
    var Filter: func
    # TODO: `:Cfilter[!]` should only filter based on the text; not the filepath.
    # TODO: `:Cfilter[!] /pat/f` should only filter based on the filepath; not the path.
    # Rationale: Mixing the two is too confusing, and can give unexpected results.
    if bang
        # Why the question mark in the comparison operators?{{{
        #
        # Without, the comparisons would be case-sensitive by default.
        # That's not what we want.  If that bothers you, you can always override
        # it by including `\C` in the pattern you provide to `:Cfilter`.
        #}}}
        Filter = (_, v: dict<any>): bool =>
            bufname(v.bufnr)->fnamemodify(':p') !~? pat && v.text !~? pat
    else
        Filter = (_, v: dict<any>): bool =>
            bufname(v.bufnr)->fnamemodify(':p') =~? pat || v.text =~? pat
    endif
    filter(list, Filter)

    if len(list) == old_size
        echo 'No entry was removed'
        return
    endif

    var title: string = GetTitle()->AddFilterIndicatorToTitle(arg_pat, bang)
    var action: string = GetAction(mod)
    Setqflist([], action, {items: list, title: title})

    MaybeResizeHeight()

    # tell me what you did and why
    echo printf('(%d) items were removed because they %s match %s',
            old_size - len(list),
            bang
            ?    'DID'
            :    'did NOT',
            strcharlen(pat) <= 50
            ?    pat
            :    'the pattern')
enddef

export def CfilterComplete(_, _, _): string #{{{2
    # We disable `-commented` because it's not reliable.
    # See fix_me in this file.
    #
    #     return ['-commented', '-vendor', '-tmp']->join("\n")
    return ['-vendor', '-tmp']->join("\n")
enddef

export def CfreeStack(loclist = false) #{{{2
    if loclist
        setloclist(0, [], 'f')
        lhistory
    else
        setqflist([], 'f')
        chistory
    endif
enddef

export def CgrepBuffer( #{{{2
    lnum1: number,
    lnum2: number,
    pat: string,
    loclist = false
)
    var pfx1: string = loclist ? 'l' : 'c'
    var pfx2: string = loclist ? 'l' : ''
    var range: string = $':{lnum1},{lnum2}'

    # ┌ we don't want the title of the qfl separating `:` from `cexpr`
    # │
    execute $'{pfx1}expr []'
    var cmd: string = printf(
        # if the pattern is absent from a buffer, it will give an error
        'silent!'
        # to  prevent a possible autocmd  from opening the qf  window every time
        # the qfl is expanded; it could make Vim open a new split for every buffer
        .. ' noautocmd'
        .. ' :%s bufdo :%s vimgrepadd /%s/gj %%', range, pfx2, pat)
    execute cmd

    execute $'{pfx1}window'

    if loclist
        setloclist(0, [], 'a', {title: $':{cmd}'})
    else
        setqflist([], 'a', {title: $':{cmd}'})
    endif
enddef

export def ConcealLtagPatternColumn() #{{{2
# We don't  want to  see the middle  column displaying a  pattern in  a location
# window opened by an `:ltag` command.
    if get(w:, 'quickfix_title', '')[: 4] != 'ltag '
        return
    endif
    if get(w:, 'ltag_conceal_match', 0) >= 1
        matchdelete(w:ltag_conceal_match)
    endif
    w:ltag_conceal_match = matchadd('Conceal', '|.\{-}\\\$\s*|' .. '\|' .. '|.\{-}|')
    &l:concealcursor = 'nvc'
    &l:conceallevel = 3
enddef

export def CreateMatches() #{{{2
    var id: number = GetId()

    var matches_this_qfl: dict<list<dict<string>>> = get(matches_any_qfl, id, {})
    if !empty(matches_this_qfl)
        for matches_from_all_origins: list<dict<string>> in values(matches_this_qfl)
            for a_match: dict<string> in matches_from_all_origins
                var group: string
                var pat: string
                [group, pat] = [a_match.group, a_match.pat]
                if group == 'Conceal'
                    &l:concealcursor = 'nc'
                    &l:conceallevel = 3
                endif
                call('matchadd', [group, pat, 0, -1]
                    + (group =~ 'Conceal'
                       ?    [{conceal: 'x'}]
                       :    []))
            endfor
        endfor
    endif
enddef

export def RemoveInvalidEntries() #{{{2
    var qfl: list<dict<any>> = getqflist()
        ->filter((_, v: dict<any>): bool => v.valid)
    var title: string = getqflist({title: 0}).title
    setqflist([], 'r', {items: qfl, title: title})
enddef

export def Cupdate(mod: string) #{{{2
    # to restore later
    var pos: number = line('.')

    # get a qfl where the text is updated
    var list: list<dict<any>> = Getqflist()
        # Why `extend()`?{{{
        #
        # There  will be  a conflict  between the  old value  associated to  the key
        # `text`, and the new one.
        #
        # And in  case of conflict, by  default `extend()` overwrites the  old value
        # with the  new one.  So,  in effect, `extend()`  will replace the  old text
        # with the new one.
        #}}}
        ->map((_, v: dict<any>) => extend(v, {
                text: getbufline(v.bufnr, v.lnum)
                    # Why `get()`?{{{
                    #
                    # `getbufline()` should  return a  list with a  single item,
                    # `the line lnum` in the buffer `bufnr`.
                    # But, if the buffer is unloaded, it will just return an empty list.
                    # From `:help getbufline()`:
                    #
                    #    > This function  works only  for loaded  buffers.  For  unloaded and
                    #    > non-existing buffers, an empty |List| is returned.
                    #
                    # Therefore, if an  entry in the qfl is present  in a buffer
                    # which you  didn't visit in  the past, it won't  be loaded,
                    # and `getbufline()` will return an empty list.
                    #
                    # In  this case,  we want  the text field  to stay  the same
                    # (hence `v.text`).
                    #}}}
                    ->get(0, v.text),
        }))

    # set this new qfl
    var action: string = GetAction(mod)
    Setqflist([], action, {items: list})

    MaybeResizeHeight()

    # restore position
    execute $'normal! {pos}G'
enddef

export def ConcealOrDelete(type = ''): string #{{{2
# Purpose:
#    - conceal visual block
#    - delete anything else (and update the qfl)

    if type == ''
        &operatorfunc = ConcealOrDelete
        return 'g@'
    endif

    var range: list<number>
    if ['char', 'line']->index(type) >= 0
        range = [line("'["), line("']")]
    elseif type == 'block'
        var vcol1: number = virtcol("'[", true)[0]
        var vcol2: number = virtcol("']", true)[0]
        # We could also use:{{{
        #
        #     var pat: string = '\%V.*\%V'
        #
        # ... but the match would disappear when we change the focused window,
        # probably because the visual marks would be set in another buffer.
        #}}}
        var pat: string = $'\%{vcol1}v.*\%{vcol2}v.'
        matchadd('Conceal', pat, 0, -1, {conceal: 'x'})
        &l:concealcursor = 'nc'
        &l:conceallevel = 3
        return ''
    endif
    # for future restoration
    var pos: number = min(range)

    # get a qfl without the entries we want to delete
    var qfl: list<dict<any>> = Getqflist()
    remove(qfl, range[0] - 1, range[1] - 1)

    # we need to preserve conceal options, because our qf filetype plugin resets them
    var conceallevel_save: number = &l:conceallevel
    var concealcursor_save: string = &l:concealcursor
    # set this new qfl
    Setqflist([], 'r', {items: qfl})
    [&l:conceallevel, &l:concealcursor] = [conceallevel_save, concealcursor_save]

    MaybeResizeHeight()

    # restore position
    execute $'normal! {pos}G'
    return ''
enddef

export def DisableSomeKeys(keys: list<string>) #{{{2
    if !exists('b:undo_ftplugin') || b:undo_ftplugin == ''
        b:undo_ftplugin = 'execute'
    endif
    for key: string in keys
        execute $'silent nnoremap <buffer><nowait> {key} <Nop>'
        b:undo_ftplugin ..= $'|execute "nunmap <buffer> {key}"'
    endfor
enddef


export def Nv(errorfile: string): string #{{{2
    var file: list<string> = readfile(errorfile)
    if empty(file)
        return ''
    endif
    var title: string = file->remove(0)
    # we use simple error formats suitable for a grep-like command
    var qfl: dict<any> = getqflist({
        lines: file,
        efm: '%f:%l:%c:%m,%f:%l:%m'
    })
    var items: list<dict<any>> = get(qfl, 'items', [])
    setqflist([], ' ', {items: items, title: title})
    cwindow
    return ''
enddef

export def OpenAuto(cmd: string) #{{{2
    # `:lhelpgrep`, like `:helpgrep`, opens a help window (with 1st match).{{{
    #
    # But, contrary to `:helpgrep`, the location list is local to a window.
    # Which one?
    # The one where we executed `:lhelpgrep`? No.
    # The help window opened by `:lhelpgrep`? Yes.
    #
    # So, the ll window will NOT be associated with the window where we executed
    # `:lhelpgrep`, but to the help window (with 1st match).
    #
    # And,  `:cwindow` will  succeed from  any window,  but `:lwindow`  can only
    # succeed from the help window (with 1st match).
    # But, when `QuickFixCmdPost` is fired, this help window hasn't been created yet.
    #
    # We need to delay `:lwindow` with a one-shot autocmd listening to `BufWinEnter`.
    #}}}
    if cmd == 'lhelpgrep'
        #       ┌ next time a buffer is displayed in a window
        #       │                    ┌ call this function to open the location window
        #       │                    │
        autocmd BufWinEnter * ++once timer_start(0, (_) => Open('lhelpgrep'))
    else
        Open(cmd)
    endif
enddef

def Open(arg_cmd: string)
    #    │
    #    └ we need to know which command was executed to decide whether
    #      we open the qf window or the ll window

    # all the commands populating a ll seem to begin with the letter l
    var prefix: string
    var size: number
    if arg_cmd =~ '^l'
        [prefix, size] = arg_cmd =~ '^l'
            ?     ['l', getloclist(0, {size: 0}).size]
            :     ['c', getqflist({size: 0}).size]
    else
        [prefix, size] = arg_cmd =~ '^l'
            ?     ['l', getloclist(0, {size: 0}).size]
            :     ['c', getqflist({size: 0}).size]
    endif

    # `true`: flag meaning we're going to open a loc window
    var mod: string = window.GetMod()

    # Wait.  `:copen` can't populate the qfl.  How could `cmd` be `copen`?{{{
    #
    # In some of our  plugins, we may want to open the qf  window even though it
    # doesn't contain any valid entry (e.g.: `:Scriptnames`).
    # In that case, we execute sth like:
    #
    #     doautocmd <nomodeline> QuickFixCmdPost copen
    #     doautocmd <nomodeline> QuickFixCmdPost lopen
    #
    # In these  examples, `:copen` and  `:lopen` are not valid  commands because
    # they don't  populate a  qfl.  We  could probably use  an ad-hoc  name, but
    # `:copen`  and `:lopen`  make the  code more  readable.  The  command names
    # express our intention: we want to open the qf window unconditionally
    #}}}
    var cmd: string = expand('<amatch>') =~ '^[cl]open$' ? 'open' : 'window'
    var how_to_open: string
    if mod =~ 'vertical'
        how_to_open = $'{mod} {prefix}{cmd} 40'
    else
        var height: number = max([min([10, size]), &winminheight + 2])
        #                     │    │
        #                     │    └ at most 10 lines high
        #                     └ at least `&winminheight + 2` lines high
        # Why `&winminheight + 2`?{{{
        #
        # First, the number passed to `:[cl]{open|window}`  must be at least 1, even
        # if the qfl is empty.  E.g., `:lwindow 0` would give `E939`.
        #
        # Second, if `'equalalways'` is reset, and the  qf window is only 1 or 2
        # lines high, pressing Enter on the qf entry would give `E36`.
        # In general, the issue is triggered when  the qf window is `&winminheight + 1` lines
        # high or lower.
        #}}}
        how_to_open = $'{mod} {prefix}{cmd} {height}'
    endif

    # it will fail if there's no loclist
    try
        execute how_to_open
    catch
        lg.Catch()
        return
    endtry

    if arg_cmd == 'helpgrep'
        # Why do you close the help window?{{{
        #
        #    - The focus switches to the 1st entry in the qfl;
        #      it's distracting.
        #
        #      I prefer to first have a look at all the results.
        #
        #    - If it's opened now, it will be from our current window,
        #      and it may be positioned in a weird place.
        #
        #      I prefer to open it later from the qf window;
        #      this way, they will be positioned next to each other.
        #}}}
        #   Why don't you close it for `:lhelpgrep`, only `:helpgrep`?{{{
        #
        # Because, the location list is attached to this help window.
        # If we close it, the ll window will be closed too.
        #}}}

        # Why the delay?{{{
        #
        # It doesn't work otherwise.
        # Probably because the help window hasn't been opened yet.
        #}}}
        # Do *not* listen to any other event.{{{
        #
        # They are full of pitfalls.
        #
        # For example, `BufWinEnter` or `BufReadPost` may give `E788` (only in Vim):
        #
        #     #                                              v---------v
        #     autocmd QuickFixCmdPost * cwindow 10 | autocmd BufWinEnter * ++once helpclose
        #     helpgrep foobar
        #     helpgrep wont_find_this
        #     helpgrep wont_find_this
        #     E788: Not allowed to edit another buffer now˜
        #
        # And `BufEnter` may give `E426` and `E433`:
        #
        #     autocmd QuickFixCmdPost * cwindow 10 | autocmd BufEnter * ++once helpclose
        #     helpgrep wont_find_this
        #     help
        #     E433: No tags file˜
        #     E426: tag not found: help.txt@en˜
        #}}}
        autocmd SafeState * ++once helpclose
    endif
enddef

export def OpenManual(where: string) #{{{2
    var wintype: string = win_gettype()
    var size: number = wintype == 'loclist'
        ?     getloclist(0, {size: 0}).size
        :     getqflist({size: 0}).size
    if empty(size)
        echo (wintype == 'loclist' ? 'location' : 'quickfix') .. ' list is empty'
        return
    endif

    var splitbelow_was_on: bool = &splitbelow | &splitbelow = false
    try
        if where == 'nosplit'
            execute "normal! \<CR>zv" | return
        endif

        execute "normal! \<C-W>\<CR>zv"
        if where == 'vertical split'
            wincmd L
        elseif where == 'tabpage'
            var orig: number = win_getid()
            tab split
            var new: number = win_getid()
            win_gotoid(orig)
            quit
            win_gotoid(new)
        endif
    catch
        lg.Catch()
        return
    finally
        if splitbelow_was_on
            &splitbelow = true
        endif
    endtry
enddef

export def SetMatches( #{{{2
    origin: string,
    group: string,
    arg_pat: string
)
    var id: number = GetId()
    if !matches_any_qfl->has_key(id)
        matches_any_qfl[id] = {}
    endif
    var matches_this_qfl_this_origin: list<dict<string>> =
        get(matches_any_qfl[id], origin, [])
    var pat: string = get(KNOWN_PATTERNS, arg_pat, arg_pat)
    matches_any_qfl[id]['origin'] = extend(matches_this_qfl_this_origin,
        [{group: group, pat: pat}])
enddef

export def ToggleFullFilePath() #{{{2
    var pos: list<number> = getcurpos()
    full_filepath = !full_filepath
    var list: list<dict<any>> = Getqflist()
    Setqflist([], 'r', {items: list})
    setpos('.', pos)
enddef
var full_filepath: bool

export def UndoFtplugin() #{{{2
    set buflisted<
    set cursorline<
    set statusline<
    set wrap<

    nunmap <buffer> <C-Q>
    nunmap <buffer> <C-R>

    nunmap <buffer> <C-S>
    nunmap <buffer> <C-V><C-V>
    nunmap <buffer> <C-T>

    nunmap <buffer> <CR>
    nunmap <buffer> <C-W><CR>

    nunmap <buffer> D
    nunmap <buffer> DD
    xunmap <buffer> D

    nunmap <buffer> cof
    nunmap <buffer> p
    nunmap <buffer> P

    nunmap <buffer> q

    delcommand CRemoveInvalid

    delcommand Csave
    delcommand Crestore
    delcommand Cremove

    delcommand Cconceal
    delcommand Cfilter
    delcommand Cupdate
enddef
#}}}1
# Utilities {{{1
def AddFilterIndicatorToTitle( #{{{2
    title: string,
    pat: string,
    bang: bool
): string

    # What is this “filter indicator”?{{{
    #
    # If  the qfl  has  already been  filtered,  we don't  want  to add  another
    # `[:filter pat]`  in the  title.  Too  verbose.  Instead we  want to  add a
    # “branch” or a “concat”:
    #
    #         [:filter! pat1] [:filter! pat2]    ✘
    #         [:filter! pat1 | pat2]             ✔
    #
    #         [:filter pat1] [:filter pat2]      ✘
    #         [:filter pat1 & pat2]              ✔
    #}}}
    var filter_indicator: string = '\s*\[:filter' .. (bang ? '!' : '!\@!')
    var has_already_been_filtered: bool = match(title, filter_indicator) >= 0
    return has_already_been_filtered
        ?     title->substitute('\ze\]$', (bang ? ' | ' : ' \& ') .. pat, '')
        :     $'{title} [:filter{bang ? '!' : ''} {pat}]'
enddef

def GetAction(mod: string): string #{{{2
    return mod =~ '^keep' ? ' ' : 'r'
    #                        │     │
    #                        │     └ don't create a new list, just replace the current one
    #                        └ create a new list
enddef

def GetId(): number #{{{2
    var Getqflist_id: func: list<any> = win_gettype() == 'loclist'
        ?    function('getloclist', [0] + [{id: 0}])
        :    function('getqflist', [{id: 0}])
    return Getqflist_id()->get('id', 0)
enddef

def GetPat(arg_pat: string): string #{{{2
    # TODO:{{{
    # We guess the comment  leader of the buffers in the  qfl, by inspecting the
    # values of 'commentstring' in the first buffer of the qfl.
    # However, `getbufvar()` will return an empty string if we haven't visited
    # the buffer yet.
    # Find a way to warn the user that they should visit the first buffer...
    #}}}
    # FIXME: What if there are several filetypes?
    # Suppose the first buffer where there are entries is a Vim one.
    # But the second one is a python one.
    # The  entries in  the python  buffer would  be filtered  using the  comment
    # leader of Vim, which is totally wrong.
    var cml: string = getqflist()
        ->get(0, {})
        ->get('bufnr', 0)
        ->getbufvar('&commentstring')
        ->split('%s')
        ->matchstr('\S\+')
        ->escape('\')
    if cml != ''
        cml = $'\V{cml}\m'
    else
        # An empty comment leader would make a pattern which matches all the time.
        # As a result, all the qfl would be emptied.
        cml = '"'
    endif

    # In theory, `\S*` is wrong here.{{{
    #
    # In practice, I doubt it will cause false negatives, because we never use a
    # space in a session name, and because plugins names don't contain spaces.
    #
    # Anyway, I prefer some false negatives (i.e. entries which are not filtered
    # while they should),  rather than some false positives  (i.e. entries which
    # should *not* be filtered, but they are).
    #}}}
    var arg2pat: dict<string> = {
        -commented: $'^\s*{cml}',
        -vendor: '^\S*/pack/vendor/\%(opt\|start\)/\%(' .. VENDOR->join('\|') .. '\)/',
        -tmp:    '^\S*/\%(qfl\|session\)/[^ \t/]*\.vim'
            .. '\|^\S*/tmp/\S*\.vim',
    }

    # If `:Cfilter` was passed a special argument, interpret it.
    if arg_pat =~ arg2pat->keys()->join('\|')
        return arg_pat
            ->split('\s\+')
            ->map((_, v: string) => arg2pat[v])
            ->join('\|')
    else
        # If no pattern was provided, use the search register as a fallback.
        # Remove a possible couple of slashes before and after the pattern.
        # Otherwise, do nothing.
        return arg_pat == ''
            ?     @/
            : arg_pat =~ '^/.*/$'
            ?     arg_pat[1 : -2]
            :     arg_pat
    endif
enddef

def GetTitle(): string #{{{2
    return win_gettype() == 'loclist'
        ?     getloclist(0, {title: 0})->get('title', '')
        :     getqflist({title: 0})->get('title', '')
enddef

def Getqflist(): list<dict<any>> #{{{2
    return win_gettype() == 'loclist' ? getloclist(0) : getqflist()
enddef

def MaybeResizeHeight() #{{{2
    if winnr('$') == 1 || winwidth(0) != &columns
        return
    endif

    # no more than 10 lines
    var newheight: number = min([10, Getqflist()->len()])
    # at least 2 lines (to avoid `E36` if we've reset `'equalalways'`)
    newheight = max([2, newheight])
    execute $'resize {newheight}'
enddef

def Setqflist(...l: list<any>) #{{{2
    if win_gettype() == 'loclist'
        call('setloclist', [0] + l)
    else
        call('setqflist', l)
    endif
enddef

