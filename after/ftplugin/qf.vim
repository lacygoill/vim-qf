" Commands {{{1
" Cdelete {{{2

com -bar -buffer -range Cdelete call qf#delete_or_conceal('Ex', <line1>, <line2>)

" Cfilter {{{2
" Documentation:{{{
"
"     :Cfilter[!] /{pat}/
"     :Cfilter[!]  {pat}
"
"             Filter the quickfix looking  for pattern, `{pat}`. The pattern can
"             match the filename  or text.  Providing `!` will  invert the match
"             (just like `grep -v`).
"}}}

" Do not give the `-bar` attribute to the commands.
" It would break a pattern containing a bar (for example, for an alternation).

com -bang -buffer -nargs=? -complete=custom,qf#cfilter_complete Cfilter
\                           call qf#cfilter(<bang>0, <q-args>, <q-mods>)

" Cupdate {{{2

" `:Cupdate` updates the text of each entry in the current qfl.
" Useful after a refactoring, to have a visual feedback.
" Example:
"         PQ grep -IRn pat /tmp/some_dir/
"         noa cfdo %s/pat/rep/ge | update
"         Cupdate

com -bar -buffer Cupdate call qf#cupdate(<q-mods>)
"}}}1
" Mappings {{{1

" disable some keys, to avoid annoying error messages
call qf#disable_some_keys(['a', 'd', 'gj', 'gqq' , 'i', 'o', 'p', 'r', 'u', 'x'])

nno <buffer><nowait><silent> <cr> <cr>:norm! zv<cr>
nno <buffer><nowait><silent> z<cr> <c-w><cr>zv

nno <buffer><nowait><silent> D  :<c-u>set opfunc=qf#delete_or_conceal<cr>g@
nno <buffer><nowait><silent> DD :<c-u>set opfunc=qf#delete_or_conceal<bar>exe 'norm! '.v:count1.'g@_'<cr>
xno <buffer><nowait><silent> D  :<c-u>call qf#delete_or_conceal('vis')<cr>

nno <buffer><nowait><silent> cof :<c-u>call qf#toggle_full_filepath()<cr>

nno <buffer><nowait><silent> q :<c-u>call qf#quit()<cr>

" Options {{{1

setl nobuflisted

setl cursorline nowrap

augroup my_qf
    au! * <buffer>
    " FIXME:{{{
    "
    " If I press `-c` to open the TOC menu, and if I write in this file:
    "
    "     call qf#setup_toc()
    "
    " The function isn't called. No syntax highlighting. Why?
    " If I install this autocmd:
    "
    "     au FileType qf call qf#setup_toc()
    "
    " Same result.
    " If I install this autocmd
    "
    "     au Syntax qf call qf#setup_toc()
    "
    " It works. Why?
    "
    " Update:
    " It's because of the guard:
    "
    "         if … &syntax isnot# 'qf'
    "             return
    "         endif
    "
    " We need it to prevent the autocmd to nest too deep:
    "
    "     Vim(let):E218: autocommand nesting too deep
    "
    " This error comes from the command (in `qf#setup_toc()`):
    "
    "     let &syntax = getbufvar(bufnr, '&syntax')
    "
    " We could prefix it with `:noa`, but then the new syntax file
    " (help, markdown, man, …) would NOT be sourced.
    "
    " ---
    "
    " If I install this autocmd
    "
    "     au Syntax <buffer> call qf#setup_toc()
    "
    " It works. What does `<buffer>` mean here? What's the difference with `qf`?
    " I think it's expanded into a buffer number. So it limits the scope of
    " the autocmd to the current buffer, when its syntax option is set.
    "}}}
    au Syntax <buffer> call qf#setup_toc()
augroup END

call lg#set_stl(
    \ '%{qf#statusline#buffer()}%=    %-'..winwidth(0)/8..'(%l/%L%) ',
    \ '%{get(b:, "qf_is_loclist", 0) ? "[LL] ": "[QF] "}%=    %-'..winwidth(0)/8..'(%l/%L%) ')

" efm {{{2
" Why do we set 'efm'?{{{
"
" Type:
"       :vim /fu/gj %
"       :setl ma | $d_ | setl noma
"       :cgetb
"
" The new qfl is not interactive.
" This is because  `:cgetb` interprets the contents of the  qfl thanks to 'efm',
" (contrary to `:grep` which uses 'gfm').
"
" The default global value is very long:
"
"        put =&g:efm | s/\\\@1<!,/\r/g
"
" But it seems  it doesn't contain any  value describing the contents  of a qfl.
" IOW, it's designed to interpret the output of some shell commands and populate
" the qfl. It's not designed to parse the qfl itself.
"}}}
" Could we use a simpler value?{{{
"
" Yes, if we didn't align the text in the qfl:
"
"     let &l:efm = '%f\|%l col %c\|%m'
"
" But the  alignment adds extra whitespace,  so our current value  needs to take
" them into account.
"}}}

"                              ┌ all meta symbols (\ . # [), including the backslash,
"                              │ have to be written with a leading '%'
"                              │ (see :h `efm-ignore`)
"                              │
let &l:efm = '%f%*\s\|%l col %c%*\s\|%m'
"│              ├──┘
"│              └ scanf() notation for `%\s%\+`(see :h efm-ignore, “pattern matching“)
"└ using `:let` instead of `setl` makes the value more readable
"  otherwise, we would need to escape any:
"
"    - backslash
"
"    - bar
"
"      here we still escape a bar, but it's only for the regex engine
"      `:set` would need an additional backslash
"
"    - comma
"
"      We need to escape a comma even  with `:let`, because a comma has a
"      special meaning for 'efm': separation between 2 formats.
"
"      But with `:set` we would need a double backslash, because a comma has
"      also a special meaning for `:set`: separation between 2 option values.
"
"    - double quote
"
"    - space
"}}}2

" Variables {{{1

" Are we viewing a location list or a quickfix list?
const b:qf_is_loclist = get(get(getwininfo(win_getid()), 0, {}), 'loclist', 0)

" Alignment {{{1

call qf#align()

" Matches {{{1

" Why reset 'cole' and 'cocu'?{{{
"
" The  2nd time  we display  a  qf buffer  in  the same  window, there's  no
" guarantee that we're going to conceal anything.
"}}}
setl cocu< cole<
call clearmatches()
call qf#create_matches()

" Teardown {{{1

let b:undo_ftplugin = get(b:, 'undo_ftplugin', 'exe')
    \ ..'| call qf#undo_ftplugin()'

