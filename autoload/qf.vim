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
"    ┌ qf id
"    │     ┌ origin
"    │     │
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
" Then, we invoke `qf#create_matches()` to create the matches.
" Finally, we  also invoke  `qf#create_matches()` in  `after/ftplugin/qf.vim` so
" that the matches are re-applied whenever we close/re-open the qf window.
"
" `qf#create_matches()`  checks  whether  the  id  of  the  current  qfl  is  in
" `s:matches_any_qfl`. If it is, it installs all  the matches which are bound to
" `it.
"}}}
" Why call `qf#create_matches()` in every third-party plugin?{{{

" Why not just relying on the autocmd opening the qf window?
"
"         vim-window:
"             autocmd QuickFixCmdPost cwindow
"
"         a plugin:
"             doautocmd <nomodeline> QuickFixCmdPost grep
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
"         • qf#set_matches()
"           s:get_id()
"
"           → they should be passed a numeric flag, to help them determine
"             whether we operate on a loclist or a qfl
"
"         • `s:get_id()` should stop relying on `b:qf_is_loclist`
"            and use the flag we pass instead
"
"            This is because when we would invoke `qf#set_matches()`,
"            the qf window would NOT have been opened, so there would
"            be no `b:qf_is_loclist`.
"
"            It couldn't even rely on the expression populating `b:qf_is_loclist`:
"
"                    get(get(getwininfo(win_getid()), 0, {}), 'loclist', 0)
"
"            … because, again, there would be no qf window yet.
"
" Second:
" Suppose the qf window is already opened, and one of our plugin creates a new qfl,
" with a new custom match. It won't be applied.
"
" Why?
" Because, when `setloclist()` or `setqflist()` is invoked, if the qf window is already
" opened, it triggers `BufReadPost` → `FileType` → `Syntax`.
" So, our filetype plugin would be immediately sourced, and `qf#create_matches()` would
" be executed too early (before `qf#set_matches()` has set the match).
"
" As a result, we would need to also trigger `FileType qf`:
"
"         doautocmd <nomodeline> QuickFixCmdPost grep
"         if &l:buftype !=# 'quickfix'
"             return
"         endif
"         doautocmd <nomodeline> FileType qf
"
" To avoid sourcing the qf filetype plugin when populating the qfl, we could use
" `:noautocmd`:
"
"         noautocmd call setqflist(…)
"
" Conclusion:
" Even with all  that, the qf filetype  plugin would be sourced twice  if the qf
" window is not already opened. Indeed:
"
"         vim-window:
"             autocmd QuickFixCmdPost cwindow
"
"         a plugin:
"             doautocmd <nomodeline> QuickFixCmdPost grep
"
" … will fire `FileType qf` iff the window is not opened.
" I don't like a filetype plugin being sourced several times.
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
\                         'location'  : '^\v.{-}\|\s*%(\d+)?\s*%(col\s+\d+)?\s*\|\s?',
\                         'double_bar': '^|\s*|\s*\|\s*|\s*|\s*$',
\                       }

let s:other_plugins = [
\                       'autoload/plug.vim',
\                       'plugged/emmet-vim',
\                       'plugged/fzf.vim',
\                       'plugged/goyo.vim',
\                       'plugged/limelight.vim',
\                       'plugged/potion',
\                       'plugged/seoul256.vim',
\                       'plugged/tmux.vim',
\                       'plugged/ultisnips',
\                       'plugged/undotree',
\                       'plugged/unicode.vim',
\                       'plugged/vim-abolish',
\                       'plugged/vim-cheat40',
\                       'plugged/vim-dirvish',
\                       'plugged/vim-easy-align',
\                       'plugged/vim-exchange',
\                       'plugged/vim-fugitive',
\                       'plugged/vim-gutentags',
\                       'plugged/vim-rhubarb',
\                       'plugged/vim-sandwich',
\                       'plugged/vim-sneak',
\                       'plugged/vim-snippets',
\                       'plugged/vim-submode',
\                       'plugged/vim-tmuxify',
\                    ]

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

fu! qf#cfilter(bang, pat, mod) abort "{{{2
    try
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

        let pat      = s:get_pat(a:pat)
        let list     = s:get_list()
        let old_size = len(list)
        call filter(list, printf('bufname(v:val.bufnr) %s pat %s v:val.text %s pat',
        \                         op, bool, op))

        " update qfl
        let action    = s:get_action(a:mod)
        let function  = s:get_function()
        let args      = s:get_all_args([list, action])
        let old_title = s:get_title()
        let new_title = {'title': ':filter '.pat.' '.get(old_title, 'title', '')}
        call call(function, args)

        " update title
        call call(function, args + [new_title])

        call s:maybe_resize_height()

        echo printf('(%d) items were removed because they %s match  %s',
        \           old_size - len(list),
        \           a:bang
        \           ?    'did NOT'
        \           :    'DID',
        \           strchars(pat) <= 50
        \           ?    pat
        \           :    'the pattern')
    catch
        return my_lib#catch_error()
    endtry
endfu

fu! qf#cfilter_complete(arglead, _c, _p) abort "{{{2
    let candidates = [ '-commented', '-other_plugins', '-tmp' ]
    return filter(candidates, { i,v -> stridx(v, a:arglead) == 0 })
endfu

fu! qf#create_matches() abort "{{{2
    try
        let id = s:get_id()

        let matches_this_qfl = get(s:matches_any_qfl, id, {})
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

fu! qf#cupdate(mod) abort "{{{2
    try
        " save position
        let pos = line('.')

        " update the text of the qfl entries
        let list = s:get_list()
        " Why using `get()`?{{{
        "
        " `getbufline()`  should return  a list  with  a single  item, the  line
        " `lnum` in the buffer `bufnr`.
        " But it will fail if the buffer is unloaded. In this case, it will just
        " return an empty list.
        " It seems that Vim unloads a buffer which was loaded just to look for a pattern,
        " but that the user never actively visited.
        "}}}
        "                                           │
        call map(list, { i,v -> extend(v, { 'text': get(getbufline(v.bufnr, v.lnum), 0, '') }) })
        "                       │
        "                       └─ There will be a conflict between the old value
        "                          associated to the key `text`, and the new one.
        "
        "                          And in case of conflict, by default `extend()` overwrites
        "                          the old value with the new one.
        "                          So, in effect, `extend()` will replace the old text with the new one.

        " update qfl
        let function = s:get_function()
        let action   = s:get_action(a:mod)
        let args     = s:get_all_args([list, action])
        let title    = s:get_title()
        call call(function, args)

        " restore title
        call call(function, args + [ title ])

        call s:maybe_resize_height()

        " restore position
        exe 'norm! '.pos.'G'
    catch
        return my_lib#catch_error()
    endtry
endfu

fu! qf#delete_entries(type, ...) abort "{{{2
    try
        if index(['char', 'line', 'block'], a:type) >= 0
            let range = [line("'["), line("']")]
        elseif a:type ==# 'vis'
            let range = [line("'<"), line("'>")]
        elseif a:type ==# 'Ex'
            let range = [a:1, a:2]
        else
            return
        endif

        let list     = s:get_list()
        call remove(list, range[0]-1, range[1]-1)

        let pos      = min(range)
        let function = s:get_function()
        let args     = s:get_all_args([list, 'r'])
        let title    = s:get_title()

        call call(function, args)
        call call(function, args + [ title ])

        call s:maybe_resize_height()

        exe 'norm! '.pos.'G'
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

fu! s:get_action(mod) abort "{{{2
    return a:mod =~# '^keep' ? ' ' : 'r'
    "                           │     │
    "                           │     └─ don't create a new list, just replace the current one
    "                           └─ create a new list
endfu

fu! s:get_all_args(args) abort "{{{2
    return b:qf_is_loclist
    \?         [0] + a:args
    \:               a:args
endfu

fu! s:get_function() abort "{{{2
    return b:qf_is_loclist ? 'setloclist' : 'setqflist'
endfu

fu! s:get_id() abort "{{{2
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

fu! s:get_list() abort "{{{2
    return b:qf_is_loclist  ? getloclist(0) : getqflist()
endfu

fu! s:get_pat(pat) abort "{{{2
    let pat = a:pat

    let arg2pat = {
    \               '-commented':     '^\s*"',
    \               '-other_plugins': '^\%('.join(s:other_plugins, '\|').'\)',
    \               '-tmp':           '^\%(session\|tmp\)',
    \             }

    " If `:Cfilter` was passed a special argument, interpret it.
    if pat =~# join(keys(arg2pat), '\|')
        let pat = split(pat, '\s\+')
        call map(pat, {i,v -> arg2pat[v]})
        let pat = join(pat, '\|')
        return pat
    else
        " If no pattern was provided, use the search register as a fallback.
        " Remove a possible couple of slashes before and after the pattern.
        " Otherwise, do nothing.
        return pat == ''
        \?         @/
        \:     pat =~ '^/.*/$'
        \?         pat[1:-2]
        \:         pat
    endif
endfu

fu! s:get_title() abort "{{{2
    return b:qf_is_loclist
    \?         getloclist(0, {'title': 1})
    \:         getqflist({'title': 1})
endfu

fu! s:maybe_resize_height() abort "{{{2
    if winwidth(0) == &columns
        exe min([ 10, len(s:get_list()) ]).'wincmd _'
    endif
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

    " In some of our  plugins, we may want to open the qf  window even though it
    " doesn't contain any valid entry (ex: `:Scriptnames`).
    " In that case, we execute sth like:
    "
    "         doautocmd <nomodeline> QuickFixCmdPost copen
    "         doautocmd <nomodeline> QuickFixCmdPost lopen
    "
    " Here,  `:copen` and  `:lopen` are  not valid  commands because  they don't
    " populate a qfl. We could probably  use any invented name. But `:copen` and
    "  `:lopen`  make the  code more  readable. The command  name expresses  our
    " intention:
    "
    "         we want to open the qf window unconditionally
    let cmd = expand('<amatch>') =~# '^[cl]open$' ? 'open' : 'window'
    let how_to_open = mod =~# '^vert'
    \?                    mod.' '.prefix.cmd.40
    \:                    mod.' '.prefix.cmd.max([min([10, size]), 1])
    "                                        │    │
    "                                        │    └── at most 10 lines height
    "                                        └── at least 1 line height (if the loclist is empty,
    "                                                                    `lwindow 0` would raise an error)

    " it will fail if there's no loclist
    try
        exe how_to_open
    catch
        return my_lib#catch_error()
    endtry

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
        let id = s:get_id()
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
