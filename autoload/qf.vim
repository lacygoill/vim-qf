if exists('g:autoloaded_qf')
    finish
endif
let g:autoloaded_qf = 1

" TODO:
" We shouldn't  create matches. We  shouldn't use the  complex ad  hoc mechanism
" around `s:matches_any_qfl`. Instead we should create ad hoc syntax file.
" Look at how Neovim has solved the issue in `ftplugin/qf.vim` for TOC menus.

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
"         if &bt isnot# 'quickfix'
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

" What's the use of `KNOWN_PATTERNS`?{{{
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
let s:KNOWN_PATTERNS  = {
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
\                       'plugged/vim-makejob',
\                       'plugged/vim-rhubarb',
\                       'plugged/vim-sandwich',
\                       'plugged/vim-sneak',
\                       'plugged/vim-snippets',
\                       'plugged/vim-speeddating',
\                       'plugged/vim-submode',
\                       'plugged/vim-tmuxify',
\                       'plugged/vimtex',
\                    ]

" Functions {{{1
fu! s:add_filter_indicator_to_title(title_dict, pat, bang) abort "{{{2
    let pat = a:pat
    let bang = a:bang ? '!' : ''
    let title = a:title_dict.title

    " What is this “filter indicator”?{{{
    "
    " If the  qfl has already  been filtered, we  don't want to  add another
    " `[:filter pat]`  in the title. Too  verbose. Instead we want to  add a
    " “branch” or a “concat”:
    "
    "         [:filter! pat1] [:filter! pat2]    ✘
    "         [:filter! pat1 | pat2]             ✔
    "
    "         [:filter pat1] [:filter pat2]      ✘
    "         [:filter pat1 & pat2]              ✔
    "}}}
    let filter_indicator = '\s*\[:filter'.(a:bang ? '!' : '!\@!')
    let has_already_been_filtered = match(title, filter_indicator) >= 0
    let title = has_already_been_filtered
            \ ?     substitute(title, '\ze\]$', (a:bang ? ' | ' : ' \& ').pat, '')
            \ :     title.'   [:filter'.bang.' '.pat.']'

    return {'title': title}
endfu

fu! qf#align() abort "{{{2
    " align the columns (more readable)
    " EXCEPT when the qfl is populated by `:WTF`
    let is_wtf =   !get(b:, 'qf_is_loclist', 0)
    \            && get(getqflist({'title':0}), 'title', '') is# 'WTF'

    if   is_wtf
    \|| !executable('column')
    \|| !executable('sed')
        return
    endif

    " We won't try to undo the edition, so don't save anything in the undotree.
    " Useful to lower memory consumption if qfl is big.
    " For more info, see `:h clear-undo`.
    let ul_save = &l:ul
    setl modifiable ul=-1

    " prepend the first occurrence of a bar with a literal C-a
    sil! exe "%!sed 's/|/\<c-a>|/1'"
    " do the same for the 2nd occurrence
    sil! exe "%!sed 's/|/\<c-a>|/2'"
    " sort the text using the C-a's as delimiters
    sil! exe "%!column -s '\<c-a>' -t"

    let &l:ul = ul_save
    setl nomodifiable nomodified

    " We could also install this autocmd in our vimrc:{{{
    "
    "         au BufReadPost quickfix call s:qf_align()
    "
    " … where `s:qf_align()` would contain commands to align the columns.
    "
    " It would work most of the time, including after `:helpg foo`.
    " But it wouldn't work after `:lh foo`.
    "
    " Because `BufReadPost quickfix` wouldn't be fired, and the function wouldn't be
    " called. However, `FileType  qf` is emitted, so  the `qf` filetype plugin  is a
    " better place to format the contents of a quickfix buffer.
    "}}}
endfu

fu! qf#open_elsewhere(where) abort "{{{2
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
        if !get(b:, 'qf_is_loclist', 0) && get(    getqflist({'title': 0}), 'title', '') =~# '^:helpg\%[rep]'
        \|| get(b:, 'qf_is_loclist', 0) && get(getloclist(0, {'title': 0}), 'title', '') =~# '^:lh\%[elpgrep]'
            augroup close_noname_window
                au!
                au BufWinEnter * if empty(expand('<amatch>')) | close | endif
                \|               exe 'au! close_noname_window' | aug! close_noname_window
            augroup END
        endif

        exe "norm! \<c-w>\<cr>"
        if a:where is# 'vert split'
            wincmd H

        elseif a:where is# 'tabpage'
            let orig = win_getid()
            tab sp
            let new = win_getid()
            call win_gotoid(orig)
            close
            call win_gotoid(new)
        endif
    catch
        return lg#catch_error()
    endtry
endfu

fu! qf#cfilter(bang, pat, mod) abort "{{{2
    try
        " get a qfl with(out) the entries we want to filter
        let list          = s:getqflist()
        let pat           = s:get_pat(a:pat)
        let [comp, logic] = s:get_comp_and_logic(a:bang)
        let old_size      = len(list)
        call filter(list, printf('bufname(v:val.bufnr) %s pat %s v:val.text %s pat',
        \                         comp, logic, comp))

        if len(list) ==# old_size
            echo 'No entry was removed'
            return
        endif

        " to update title later
        let title = s:add_filter_indicator_to_title(s:get_title(), a:pat, a:bang)

        " set the new qfl
        let action      = s:get_action(a:mod)
        let l:Setqflist = s:setqflist([list, action])
        call l:Setqflist()

        " update title
        call l:Setqflist(title)

        call s:maybe_resize_height()

        " tell me what you did and why
        echo printf('(%d) items were removed because they %s match  %s',
        \           old_size - len(list),
        \           a:bang
        \           ?    'DID'
        \           :    'did NOT',
        \           strchars(pat) <= 50
        \           ?    pat
        \           :    'the pattern')
    catch
        return lg#catch_error()
    endtry
endfu

fu! qf#cfilter_complete(arglead, _c, _p) abort "{{{2
    " Why not filtering the candidates?{{{
    "
    " We don't need to, because the command invoking this completion function is
    " defined with the attribute `-complete=custom`, not `-complete=customlist`,
    " which means Vim performs a basic filtering automatically:
    "
    "     • each candidate must begin with `a:arglead`
    "     • the comparison respects 'ic' and 'scs'
    " }}}
    return join(['-commented', '-other_plugins', '-tmp'], "\n")
endfu

fu! qf#cfree_stack(loclist) abort "{{{2
    if a:loclist
        call setloclist(0, [], 'f')
        lhi
    else
        call setqflist([], 'f')
        chi
    endif
endfu

fu! qf#cgrep_buffer(lnum1, lnum2, pat, loclist) abort "{{{2
    let pfx1 = a:loclist ? 'l' : 'c'
    let pfx2 = a:loclist ? 'l' : ''
    let range = a:lnum1.','.a:lnum2

    " ┌ we don't want the title of the qfl being separated `:` from `cexpr`
    " │
    exe pfx1.'expr []'
    "                    ┌ if the pattern is absent from a buffer,
    "                    │ it will raise an error
    "                    │
    "                    │   ┌ to prevent a possible autocmd from opening the qf window
    "                    │   │  every time the qfl is expanded; it could make Vim open
    "                    │   │  a new split for every buffer
    "                    │   │
    let cmd = printf('sil! noa %sbufdo %svimgrepadd /%s/gj %%', range, pfx2, a:pat)
    exe cmd

    exe pfx1.'window'

    if a:loclist
        call setloclist(0, [], 'a', {'title': ':'.cmd})
    else
        call setqflist([], 'a', {'title': ':'.cmd})
    endif
endfu

fu! qf#create_matches() abort "{{{2
    try
        let id = s:get_id()

        let matches_this_qfl = get(s:matches_any_qfl, id, {})
        if !empty(matches_this_qfl)
            for matches_from_all_origins in values(matches_this_qfl)
                for a_match in matches_from_all_origins
                    let [ group, pat ] = [ a_match.group, a_match.pat ]
                    if group is? 'conceal'
                        setl cocu=nc cole=3
                    endif
                    let match_id = call('matchadd',   [ group, pat, 0, -1]
                    \                               + (group is? 'conceal'
                    \                                  ?    [{ 'conceal': 'x' }]
                    \                                  :    []
                    \                                 ))
                endfor
            endfor
        endif

    catch
        return lg#catch_error()
    endtry
endfu

fu! qf#cupdate(mod) abort "{{{2
    try
        " to restore later
        let pos   = line('.')
        let title = s:get_title()

        " get a qfl where the text is updated
        let list = s:getqflist()
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

        " set this new qfl
        let action      = s:get_action(a:mod)
        let l:Setqflist = s:setqflist([list, action])
        call l:Setqflist()

        " restore title
        let l:Set_title = function(l:Setqflist, [title])
        call l:Set_title()

        call s:maybe_resize_height()

        " restore position
        exe 'norm! '.pos.'G'
    catch
        return lg#catch_error()
    endtry
endfu

fu! qf#delete_or_conceal(type, ...) abort "{{{2
    " Purpose:
    "     • conceal visual block
    "     • delete anything else (and update the qfl)
    try
        if index(['char', 'line', 'block'], a:type) >= 0
            let range = [line("'["), line("']")]
        elseif a:type is# 'vis'
            if visualmode() isnot# 'V'
                " We could also use:
                "
                "     let pat = '\%V.*\%V'
                "
                " … but the match would disappear when we change the focused window,
                " probably because the visual marks would be set in another buffer.
                let [vcol1, vcol2] = [virtcol("'<"), virtcol("'>")]
                let pat = '\v%'.vcol1.'v.*%'.vcol2.'v.'
                call matchadd('Conceal', pat, 0, -1, {'Conceal' : 'x'})
                setl cocu=nc cole=3
                return
            else
                let range = [line("'<"), line("'>")]
            endif
        elseif a:type is# 'Ex'
            let range = [a:1, a:2]
        else
            return
        endif
        " for future restoration
        let pos   = min(range)
        let title = s:get_title()

        " get a qfl without the entries we want to delete
        let list = s:getqflist()
        call remove(list, range[0]-1, range[1]-1)

        " set this new qfl
        let l:Setqflist = s:setqflist([list, 'r'])
        call l:Setqflist()

        " restore title
        let l:Set_title = function(l:Setqflist, [title])
        call l:Set_title()

        call s:maybe_resize_height()

        " restore position
        exe 'norm! '.pos.'G'
    catch
        return lg#catch_error()
    endtry
endfu

fu! qf#disable_some_keys(keys) abort "{{{2
    for a_key in a:keys
        sil! exe 'nno  <buffer><nowait><silent>  '.a_key.'  <nop>'
    endfor
endfu

fu! s:get_action(mod) abort "{{{2
    return a:mod =~# '^keep' ? ' ' : 'r'
    "                           │     │
    "                           │     └─ don't create a new list, just replace the current one
    "                           └─ create a new list
endfu

fu! s:get_comp_and_logic(bang) abort "{{{2
    "                                ┌─ the pattern MUST match the path of the buffer
    "                                │  do not make the comparison strict no matter what (`=~#`)
    "                                │  `:ilist` respects 'ignorecase'
    "                                │  `:Cfilter` should do the same
    "                                │
    "                                │     ┌─ OR the text must match
    "                                │     │
    return a:bang ? ['!~', '&&'] : ['=~', '||']
    "                 │     │
    "                 │     └─ AND the text must not match the pattern
    "                 └─ the pattern must NOT MATCH the path of the buffer
endfu

fu! s:get_id() abort "{{{2
    try
        let l:Getqflist_id = get(b:, 'qf_is_loclist', 0)
                         \ ?    function('getloclist', [0] + [{'id': 0}])
                         \ :    function('getqflist',        [{'id': 0}])
        return get(l:Getqflist_id(), 'id', 0)
    catch
        return lg#catch_error()
    endtry
endfu

fu! s:get_pat(pat) abort "{{{2
    let pat = a:pat

    let arg2pat = {
    \               '-commented':     '^\s*"',
    \               '-other_plugins': '\%(^\|/\)\%('.join(s:other_plugins, '\|').'\)',
    \               '-tmp':           '\%(^\|/\)\%(session\|tmp\)/',
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
        return pat is# ''
           \ ?     @/
           \ : pat =~ '^/.*/$'
           \ ?     pat[1:-2]
           \ :     pat
    endif
endfu

fu! s:get_title() abort "{{{2
    return get(b:, 'qf_is_loclist', 0)
       \ ?     getloclist(0, {'title': 0})
       \ :     getqflist({'title': 0})
endfu

fu! s:getqflist() abort "{{{2
    return get(b:, 'qf_is_loclist', 0)  ? getloclist(0) : getqflist()
endfu

fu! s:maybe_resize_height() abort "{{{2
    if winwidth(0) ==# &columns
        exe min([ 10, len(s:getqflist()) ]).'wincmd _'
    endif
endfu

fu! qf#open(cmd) abort "{{{2
"           │
"           └─ we need to know which command was executed to decide whether
"              we open the qf window or the ll window

    "                                 ┌─ all the commands populating a ll seem to begin with the letter l
    "                                 │
    let [ prefix, size ] = a:cmd =~# '^l'
                       \ ?     [ 'l', len(getloclist(0)) ]
                       \ :     [ 'c', len(getqflist())   ]

    let mod = call('lg#window#get_modifier', a:cmd =~# '^l' ? [1] : [])
    "                                                          │
    "            flag meaning we're going to open a loc window ┘

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
                  \ ?     mod.' '.prefix.cmd.40
                  \ :     mod.' '.prefix.cmd.max([min([10, size]), 1])
    "                                        │    │
    "                                        │    └── at most 10 lines height
    "                                        └── at least 1 line height (if the loclist is empty,
    "                                                                    `lwindow 0` would raise an error)

    " it will fail if there's no loclist
    try
        exe how_to_open
    catch
        return lg#catch_error()
    endtry

    if a:cmd is# 'helpgrep'
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
        "
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
    if a:cmd is# 'lhelpgrep'
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
        let pat = get(s:KNOWN_PATTERNS, a:pat, a:pat)
        call extend(s:matches_any_qfl[id], { a:origin : extend( matches_this_qfl_this_origin,
        \                                                       [{ 'group': a:group, 'pat': pat }]
        \                                                     )})

    catch
        return lg#catch_error()
    endtry
endfu

fu! s:setqflist(args) abort "{{{2
    return get(b:, 'qf_is_loclist', 0)
       \ ?     function('setloclist', [0] + a:args)
       \ :     function('setqflist',        a:args)
endfu

fu! qf#setup_toc() abort "{{{2
    if get(w:, 'quickfix_title') !~# '\<TOC$' || &syntax isnot# 'qf'
        return
    endif

    let llist = getloclist(0)
    if empty(llist)
        return
    endif

    let bufnr = llist[0].bufnr
    " we only want the texts, not their location
    setl modifiable
    sil %d_
    call setline(1, map(llist, {i,v -> v.text}))
    setl nomodifiable nomodified
    let &syntax = getbufvar(bufnr, '&syntax')
endfu

fu! qf#stl_position() abort "{{{2
    if getqflist() !=# []
        let g:my_stl_list_position = 1
        " Why?{{{
        "
        " We need to  redraw the statusline to see the  indicator after a vimtex
        " compilation. From `:h :redraws`:
        "
        "     Useful to update the status  line(s) when 'statusline' includes an
        "     item that doesn't cause automatic updating.
        "}}}
        redraws
    else
        " don't display '[]' in the statusline if the qfl is empty
        let g:my_stl_list_position = 0
    endif
endfu

