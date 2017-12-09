" Variables {{{1
" What's the purpose of `s:matches_any_qfl`?{{{
"
" Suppose we  have a  plugin which  populates a  qfl, opens  the qf  window, and
" applies a  match. The latter  is local  to the window. And  if we  close, then
" re-open the qf window, its id changes. So, we lose the match.
"
" To fix this, we need to achieve 2 things:
"
"         • don't apply a match directly from a third-party plugin,
"           it must be done from `after/ftplugin/qf.vim`, because the latter
"           is always sourced whenever we open a qf window
"
"           We can't  rely on the buffer  number, nor on the  window id, because
"           they both change.
"
"         • save the information of a match, so that `after/ftplugin/qf.vim`
"           can reapply it
"
" We need to bind the information of a  match (HG name, regex) to a qfl (through
" its 'context' key) or to its id.
" Atm, I don't want to use the 'context' key because:
"
"         • it's not supported in Neovim
"         • it could be used by another third-party plugin with a data type
"           different than a dictionary (risk of incompatibility/interference)
"
" So, instead, we bind the info to the qfl id in the variable `s:matches_any_qfl`.
"}}}
" How is it structured?{{{
"
" It stores a dictionary whose keys are qfl ids. The value of a key is a sub-dictionary
" describing matches.
"
" Each key in this sub-dictionary describes an “origin”. By convention, we build the
" text of an origin like this:
"         {plugin_name}:{function_name}
"
" This kind of info could be useful when debugging. It tells us from which function
" in which plugin does the match come from.
"
" Finally, the value associated to an “origin” key is a list of sub-sub-dictionaries.
" Why a list? Because a SINGLE function from a plugin could need to install SEVERAL
" matches. These final sub-sub-dictionaries contain 2 keys/values:
"
"         • 'group' → HG name
"         • 'pat'   → regex
"}}}
" Example of simple value for `s:matches_any_qfl`:{{{
"
" { '1': {'myfuncs:search_todo':
" \                             [{'group': 'Conceal', 'pat': '^\v.{-}\|\s*\d+%(\s+col\s+\d+\s*)?\s*\|\s?'},
" \                              {'group': 'Todo',    'pat': '\cfixme\|todo'}]
" \      }}
"}}}
" How is it used?{{{
"
" In a plugin, when we populate a qfl and want to apply a match to its window,
" we invoke:
"
"         call qf#set_matches({origin}, {HG}, {pat})
"
" It will register a match in `s:matches_any_qfl`.
" Then, in `after/ftplugin/qf.vim`, we invoke `qf#create_matches()`.
" The latter checks whether the id of the current qfl is in `s:matches_any_qfl`.
" If it is, it installs all the matches which are bound to it.
"}}}
let s:matches_any_qfl = {}

" What's the use of `known_patterns`?{{{
"
" If you  often use the same  regex to describe some  text on which you  want to
" apply a match, add it to this dictionary, with a telling name. Then, instead
" of writing this:
"
"         call qf#set_matches({origin}, {HG}, {complex_regex})
"
" … you can write this:
"
"         call qf#set_matches({origin}, {HG}, {telling_name})
"}}}
let s:known_patterns  = {
\                         'location'  : '^\v.{-}\|\s*\d+%(\s+col\s+\d+\s*)?\s*\|\s?',
\                         'double_bar': '^||\s*\|\s*|\s*|\s*$',
\                       }

" Functions {{{1
fu! qf#c_w(tabpage) abort "{{{2
    try
        " In a qf window populated by `:helpg` or `:lh`, `C-w CR` opens a window
        " with an unnamed buffer. We don't want that.
        "
        " Why does that happen?
        "
        " By  default, pressing  Enter  in  a qf  window  populated by  `:helpg`
        " displays the current entry in a NEW window (contrary to other commands
        " populating the qfl).  `C-w CR` ALSO opens a new window.
        "
        " So, my  guess is  that `C-w CR`  opens a new  window, then  from there
        " `:helpg` opens another window to display the current entry.
        if !get(b:, 'qf_is_loclist', 0) && get(    getqflist({'title':1}), 'title', '') =~# '^:helpg\%[rep]'
        \|| get(b:, 'qf_is_loclist', 0) && get(getloclist(0, {'title':1}), 'title', '') =~# '^:lh\%[elpgrep]'
            augroup close_noname_window
                au!
                au BufWinEnter * if empty(expand('<amatch>')) | close | endif
                \|               exe 'au! close_noname_window' | aug! close_noname_window
            augroup END
        endif

        exe "norm! \<c-w>\<cr>"
        if a:tabpage
            let orig = win_getid()
            tab sp
            let new = win_getid()
            call win_gotoid(orig)
            close
            call win_gotoid(new)
        endif
    catch
        return my_lib#catch_error()
    endtry
endfu

fu! qf#cfilter(list, bang, pat, mod) abort "{{{2
    try
        let old_title = get(a:list ==# 'qf'
        \                   ?     getqflist(   {'title': 1})
        \                   :    getloclist(0, {'title': 1}),
        \                   'title', '')

        "                                          ┌─ the pattern MUST match the path of the buffer
        "                                          │  do not make the comparison strict no matter what (`=~#`)
        "                                          │  `:ilist` respects 'ignorecase'
        "                                          │  `:Cfilter` should do the same
        "                                          │
        "                                          │     ┌─ OR the text must match
        "                                          │     │
        let [op, bool] = a:bang ? ['!~', '&&'] : ['=~', '||']
        "                           │     │
        "                           │     └─ AND the text must not match the pattern
        "                           └─ the pattern must NOT MATCH the path of the buffer

        let pat = s:get_pat(a:pat)

        let list = a:list ==# 'qf' ? getqflist() : getloclist(0)
        call filter(list, printf('bufname(v:val.bufnr) %s pat %s v:val.text %s pat',
        \                         op, bool, op))

        let action = a:mod =~# '^keep' ? ' ' : 'r'
        let new_title = {'title': ':filter '.pat.' '.old_title}
        call call('set'.a:list.'list', a:list ==# 'qf'
        \                              ?    [    list, action ]
        \                              :    [ 0, list, action ])

        call call('set'.a:list.'list', a:list ==# 'qf'
        \                              ?    [    [], 'a', new_title ]
        \                              :    [ 0, [], 'a', new_title ])

        echo printf('Filtered list:%s matching %s (%d items)',
        \           a:bang ? ' not' : '', a:pat, len(list))
    catch
        return my_lib#catch_error()
    endtry
endfu

fu! qf#cfilter_complete(arglead, _c, _p) abort "{{{2
    let candidates = [ '-not_my_plugins', '-not_relevant' ]
    return empty(a:arglead)
    \?         candidates
    \:         filter(candidates, 'v:val[:strlen(a:arglead)-1] ==# a:arglead')
endfu

fu! qf#create_matches() abort "{{{2
    try
        let qf_id = s:get_qf_id()

        let matches_this_qfl = get(s:matches_any_qfl, qf_id, {})
        if !empty(matches_this_qfl)
            for matches_from_all_origins in values(matches_this_qfl)
                for a_match in matches_from_all_origins
                    let [ group, pat ] = [ a_match.group, a_match.pat ]
                    if group ==? 'Conceal'
                        setl cocu=nc cole=3
                    endif
                    let match_id = call('matchadd',   [ group, pat, 0, -1]
                    \                               + (group ==? 'conceal'
                    \                                  ?    [{ 'conceal': 'x' }]
                    \                                  :    []
                    \                                 ))
                    let this_window = win_getid()
                endfor
            endfor
        endif

    catch
        return my_lib#catch_error()
    endtry
endfu

fu! qf#cupdate(list, mod) abort "{{{2
    try
        " save title of the qf window
        let old_title = a:list ==# 'qf'
        \                   ?    getqflist({'title': 1})
        \                   :    getloclist(0, {'title': 1})

        " update the text of the qfl entries
        let list = a:list ==# 'qf' ? getqflist() : getloclist(0)
        call map(list, { i,v -> extend(v, { 'text': get(getbufline(v.bufnr, v.lnum), 0, '') }) })
        "                       │                   │
        "                       │                   └─ `getbufline()` should return a list with a single item.
        "                       │                      But we use `get()` to give the item a default value,
        "                       │                      in case it doesn't exist.
        "                       │
        "                       └─ There will be a conflict between the old value
        "                          associated to the key `text`, and the new one.
        "
        "                          And in case of conflict, by default `extend()` overwrites
        "                          the old value with the new one.
        "                          So, in effect, `extend()` will replace the old text with the new one.

        let action = a:mod =~# '^keep' ? ' ' : 'r'
        "                                 │     │
        "                                 │     └─ don't create a new list, just replace the current one
        "                                 └─ create a new list
        call call('set'.a:list.'list', a:list ==# 'qf'
        \                              ?    [    list, action ]
        \                              :    [ 0, list, action ])

        " restore title
        call call('set'.a:list.'list', a:list ==# 'qf'
        \                              ?    [    [], 'a', old_title ]
        \                              :    [ 0, [], 'a', old_title ])

    catch
        return my_lib#catch_error()
    endtry
endfu

fu! qf#delete_previous_matches() abort "{{{2
    " Why reset 'cole' and 'cocu'?{{{
    "
    " The  2nd time  we display  a  qf buffer  in  the same  window, there's  no
    " guarantee that we're going to conceal anything.
    "}}}
    setl cocu< cole<
    try
        for match_id in map(getmatches(), {i,v -> v.id})
            call matchdelete(match_id)
        endfor
    catch
        return my_lib#catch_error()
    endtry
endfu

fu! qf#disable_some_keys(keys) abort "{{{2
    for a_key in a:keys
        sil! exe 'nno  <buffer><nowait><silent>  '.a:key.'  <nop>'
    endfor
endfu

fu! s:get_pat(pat) abort "{{{2
    let not_my_plugins = [
    \                      'autoload/plug.vim',
    \                      'plugged/emmet-vim',
    \                      'plugged/fzf.vim',
    \                      'plugged/goyo.vim',
    \                      'plugged/limelight.vim',
    \                      'plugged/potion',
    \                      'plugged/seoul256.vim',
    \                      'plugged/tmux.vim',
    \                      'plugged/ultisnips',
    \                      'plugged/undotree',
    \                      'plugged/unicode.vim',
    \                      'plugged/vim-abolish',
    \                      'plugged/vim-cheat40',
    \                      'plugged/vim-dirvish',
    \                      'plugged/vim-easy-align',
    \                      'plugged/vim-exchange',
    \                      'plugged/vim-fugitive',
    \                      'plugged/vim-gutentags',
    \                      'plugged/vim-rhubarb',
    \                      'plugged/vim-sandwich',
    \                      'plugged/vim-sneak',
    \                      'plugged/vim-snippets',
    \                      'plugged/vim-submode',
    \                      'plugged/vim-tmuxify',
    \                    ]

    " If no pattern was provided, use the search register as a fallback.
    " Remove a possible couple of slashes before and after the pattern.
    " If `:Cfilter` was passed `-not_my_plugins`, build the right pattern.
    " If `:Cfilter` was  passed `-not_relevant`, use a  pattern matching session
    " and temporary files. Otherwise, do nothing.
    return a:pat == ''
    \?         @/
    \:     a:pat =~ '^/.*/$'
    \?        a:pat[1:-2]
    \:     a:pat ==# '-not_my_plugins'
    \?        '^\%('.join(not_my_plugins, '\|').'\)'
    \:     a:pat ==# '-not_relevant'
    \?        '^\%(session\|tmp\)'
    \:        a:pat
endfu

fu! s:get_qf_id() abort "{{{2
    try
        return get(call(b:qf_is_loclist
        \               ?    'getloclist'
        \               :    'getqflist',
        \
        \               b:qf_is_loclist
        \               ?    [0, {'id': 0}]
        \               :    [   {'id': 0}]
        \         ), 'id', 0)

    catch
        return my_lib#catch_error()
    endtry
endfu

fu! qf#open(cmd) abort "{{{2
"           │
"           └─ we need to know which command was executed to decide whether
"              we open the qf window or the ll window

    "                                 ┌─ all the commands populating a ll seem to begin with the letter l
    "                                 │
    let [ prefix, size ] = a:cmd =~# '^l'
    \?                         [ 'l', len(getloclist(0)) ]
    \:                         [ 'c', len(getqflist())   ]

    let mod = window#get_modifier_to_open_window()

    let how_to_open = mod =~# '^vert'
    \?                    mod.' '.prefix.'window '.40
    \:                    mod.' '.prefix.'window '.max([min([10, size]), 1])
    "                                              │    │
    "                                              │    └── at most 10 lines height
    "                                              └── at least 1 line height (if the loclist is empty,
    "                                                                          `lwindow 0` would raise an error)

    exe how_to_open

    if a:cmd ==# 'helpgrep'
        call timer_start(0, { -> execute('helpc')})
        "                                 │
        "                                 └─ close the help window in the current tabpage
        "                                    if there's one (otherwise doesn't do anything)

        " Why do we close the help window?{{{
        "
        "         • The focus switches to the 1st entry in the
        "           it's distracting.
        "
        "           I prefer to first have a look at all the results.
        "
        "         • If it's opened now, it will be from our current window,
        "           and it may be positioned in a weird place.
        "
        "           I prefer to open it later from the qf window
        "           this way, they will be positioned next to each other.
        "}}}
       " Why don't we close it for `:lh`, only `:helpg`?{{{
       " Because, the location list is attached to this help window.
       " If we close it, the ll window will be closed too.
       "}}}
       " Why the delay?{{{
       " If we don't delay, `:helpclose` fails.
       " Probably because the help window hasn't been opened yet.}}}
    endif
endfu

fu! qf#open_maybe(cmd) abort "{{{2
    "             ┌─ `:lh`, like `:helpg`, opens a help window (with 1st match). {{{
    "             │  But, contrary to `:helpg`, the location list is local to a window.
    "             │  Which one?
    "             │  The one where we executed `:lh`? No.
    "             │  The help window opened by `:lh`? Yes.
    "             │
    "             │  So, the ll window will NOT be associated with the window where we executed
    "             │  `:lh`, but to the help window (with 1st match).
    "             │
    "             │  And, `:cwindow` will succeed from any window, but `:lwindow` can only
    "             │  succeed from the help window (with 1st match).
    "             │  But, when `QuickFixCmdPost` is fired, this help window hasn't been created yet.
    "             │
    "             │  We need to delay `:lwindow` with a fire-once autocmd listening to `BufWinEnter`.
    "             │}}}
    if a:cmd ==# 'lhelpgrep'
        augroup lhelpgrep_window
            au!
            "  ┌─ next time a buffer is displayed in a window
            "  │                     ┌─ call this function to open the location window
            "  │                     │
            au BufWinEnter * call qf#open('lhelpgrep')
                         \ | exe 'au! lhelpgrep_window' | aug! lhelpgrep_window
            "                     │
            "                     └─ do it only once

            " Why you shouldn't use the `nested` flag?{{{
            "
            " If you use the `nested` flag and you remove the augroup:
            "
            "         aug! lhelpgrep_window
            "
            " `:lh autocmd` raises the error:
            "
            "     Error detected while processing BufWinEnter Auto commands for "*":
            "     E216: No such group or event: lhelpgrep_window
            "
            " The `nested` flag probably causes the autocmd to be fired 2 times
            " instead of once. The 1st time, when Vim opens the help window,
            " the autocmd opens the location window and removes itself.
            " The opening of the location window re-emits `BufWinEnter`, and
            " since our autocmd has the `nested` flag, it's re-executed.
            " But this time, when it tries to remove the autocmd/augroup, it
            " doesn't exist anymore. Hence the error.
            "
            " Moral of the story: don't use `nested` all the time, especially
            " when you install a fire-once autocmd.
            "}}}
        augroup END
    else
        call qf#open(a:cmd)
    endif
endfu

fu! qf#set_matches(origin, group, pat) abort "{{{2
    try
        let id = s:get_qf_id()
        if !has_key(s:matches_any_qfl, id)
            let s:matches_any_qfl[id] = {}
        endif
        let matches_this_qfl_this_origin = get(s:matches_any_qfl[id], a:origin, [])
        let pat = get(s:known_patterns, a:pat, a:pat)
        call extend(s:matches_any_qfl[id], { a:origin : extend( matches_this_qfl_this_origin,
        \                                                       [{ 'group': a:group, 'pat': pat }]
        \                                                     )})

    catch
        return my_lib#catch_error()
    endtry
endfu
