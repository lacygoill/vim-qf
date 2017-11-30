fu! qf#c_w(tabpage) abort "{{{1
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
        return 'echoerr '.string(v:exception)
    endtry
    return ''
endfu

fu! qf#cfilter(list, bang, pat, mod) abort "{{{1
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
        return 'echoerr '.string(v:exception)
    endtry
    return ''
endfu

fu! qf#cfilter_complete(arglead, _c, _p) abort "{{{1
    return [ '-not_my_plugins' ]
endfu

fu! qf#conceal(this) abort "{{{1
    let patterns = { 'location': '^\v.{-}\|\s*\d+%(\s+col\s+\d+\s*)?\s*\|\s?' }
    if !has_key(patterns, a:this)
        return
    endif
    let pat = patterns[a:this]
    setl cocu=nc cole=3
    let w:my_conceal_match = matchadd('Conceal', pat, 0, -1, {'conceal': 'x'})
endfu

fu! qf#cupdate(list, mod) abort "{{{1
    try
        " save title of the qf window
        let old_title = a:list ==# 'qf'
        \                   ?    getqflist({'title': 1})
        \                   :    getloclist(0, {'title': 1})

        " update the text of the qfl entries
        let list = a:list ==# 'qf' ? getqflist() : getloclist(0)
        call map(list, { k,v -> extend(v, { 'text': get(getbufline(v.bufnr, v.lnum), 0, '') }) })
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
        return 'echoerr '.string(v:exception)
    endtry
endfu

fu! s:get_pat(pat) abort "{{{1
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
    \                      'plugged/vim-tmuxify',
    \                    ]

    " If no pattern was provided, use the search register as a fallback.
    " Remove a possible couple of slashes before and after the pattern.
    " If `:Cfilter` was passed `-not_my_plugins`, build the right pattern.
    " Otherwise, do nothing.
    return a:pat == ''
    \?         @/
    \:     a:pat =~ '^/.*/$'
    \?        a:pat[1:-2]
    \:     a:pat ==# '-not_my_plugins'
    \?        '^\%('.join(not_my_plugins, '\|').'\)'
    \:        a:pat
endfu

fu! qf#hide_noise(action) abort "{{{1
    if a:action ==# 'is_active'
        return exists('w:my_conceal_match')
    elseif a:action ==# 'disable' && exists('w:my_conceal_match')
        setl cocu&vim cole&vim
        call matchdelete(w:my_conceal_match)
        unlet! w:my_conceal_match
    elseif a:action ==# 'enable' && !exists('w:my_conceal_match')
        if index(map(getmatches(), { k,v -> v.group }), 'Conceal') >= 0
            setl cocu&vim cole&vim
            let id = getmatches()[index(map(getmatches(), { k,v -> v.group }), 'Conceal')].id
            call matchdelete(id)
        else
            call qf#conceal('location')
        endif
    endif
endfu

fu! qf#open(cmd) abort "{{{1
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
fu! qf#open_maybe(cmd) abort "{{{1
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

