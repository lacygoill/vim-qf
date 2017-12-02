" Commands {{{1
" Cfilter {{{2
" Documentation:{{{
"
"     :Cfilter[!] /{pat}/
"     :Cfilter[!]  {pat}
"
"             Filter the quickfix looking  for pattern, `{pat}`. The pattern can
"             match the filename  or text.  Providing `!` will  invert the match
"             (just like `grep -v`).
"
"     :Lfilter[!] /{pat}/
"     :Lfilter[!]  {pat}
"
"             Same as :Cfilter but use the location list.
"}}}

" Do not give the `-bar` attribute to the commands.
" It would break a pattern containing a bar (for example, for an alternation).

com! -bang -buffer -nargs=? -complete=customlist,qf#cfilter_complete Cfilter
\                                   exe qf#cfilter('qf' , <bang>0, <q-args>, <q-mods>)
com! -bang -buffer -nargs=? -complete=customlist,qf#cfilter_complete Lfilter
\                                   exe qf#cfilter('loc', <bang>0, <q-args>, <q-mods>)

cnorea <expr> <buffer> cfilter  getcmdtype() ==# ':' && getcmdline() ==# 'cfilter'
\                               ?    'Cfilter'
\                               :    'cfilter'

cnorea <expr> <buffer> lfilter  getcmdtype() ==# ':' && getcmdline() ==# 'lfilter'
\                               ?    'Lfilter'
\                               :    'lfilter'

" Cupdate {{{2

" `:Cupdate` updates the text of each entry in the current qfl.
" Useful after a refactoring, to have a visual feedback.
" Example:
"         PQ grep -IRn pat /tmp/some_dir/
"         cfdo %s/pat/rep/g
"         Cupdate

com! -bar -buffer Cupdate exe qf#cupdate('qf', <q-mods>)
com! -bar -buffer Lupdate exe qf#cupdate('loc', <q-mods>)

cnorea <expr> <buffer> cupdate  getcmdtype() ==# ':' && getcmdline() ==# 'cupdate'
\                               ?    'Cupdate'
\                               :    'cupdate'

cnorea <expr> <buffer> lupdate  getcmdtype() ==# ':' && getcmdline() ==# 'lupdate'
\                               ?    'Lupdate'
\                               :    'lupdate'

" Mappings {{{1

" disable some keys, to avoid annoying error messages
for s:char in [ 'a', 'd', 'gj', 'gqq' , 'i', 'o', 'p', 'r', 'u', 'x']
    sil! exe 'nno <buffer> <nowait> <silent> '.s:char.' <nop>'
endfor
unlet! s:char

nno <buffer> <nowait> <silent>  <cr>       <cr>:norm! zv<cr>
nno <buffer> <nowait> <silent>  <c-w><cr>  :<c-u>exe qf#c_w(0)<cr>
" Warning:
" By default, <c-w>T moves the current window to a new tab page.
" Here, we use it slightly differently: it opens the entry under the cursor in a
" new tag page.
" Also, we don't use `<c-w>t` because, by default, the latter moves the focus to
" the top window in the current tab page.
nno <buffer> <nowait> <silent>  <c-w>T     :<c-u>exe qf#c_w(1)<cr>

nno <buffer> <nowait> <silent>  q          :<c-u>let g:my_stl_list_position = 0 <bar> close<cr>

nno <buffer> <nowait> <silent>  [ob        :<c-u>call qf#hide_noise('enable')<cr>
nno <buffer> <nowait> <silent>  ]ob        :<c-u>call qf#hide_noise('disable')<cr>
nno <buffer> <nowait> <silent>  cob        :<c-u>call qf#hide_noise(qf#hide_noise('is_active')
                                        \ ? 'disable' : 'enable')<cr>

" Options {{{1

setl nobuflisted

augroup my_qf
    au! * <buffer>
    au BufWinEnter <buffer> setl cursorline nowrap
augroup END
" When  `:lh` populates  a  loclist  and opens  a  location  window, there's  no
" `BufWinEnter` right after `FileType qf`.
" I don't know why. Imo, there should be. There is one for `:helpg`.
" Anyway, because of this, our window-local settings won't be applied in a window
" opened by `:lh`. We want them, so fire `BufWinEnter`.
doautocmd <nomodeline> my_qf BufWinEnter

" efm {{{2
" Why do we set 'efm'?{{{
"
" Type:
"       :vim /fu/gj %
"       5G
"       setl ma | exe 'norm! d$' | setl noma
"       :cgetb
"
" The new qfl is not interactive.
" This is because  `:cgetb` interprets the contents of the  qfl thanks to 'efm',
" (contrary to `:grep` which uses 'gfm').
"
" The default global value is very long:
"
"        put =&g:efm | s/\\\@<!,/\r/g
"
" But it seems  it doesn't contain any  value describing the contents  of a qfl.
" IOW, it's designed to interpret the output of some shell commands and populate
" the qfl. It's not designed to parse the qfl itself.
"}}}
" Could we use a simpler value?{{{
"
" Yes, if we didn't align the text in the qfl:
"
"         let &l:efm = '%f\|%l col %c\|%m'
"
" But the  alignment adds extra whitespace,  so our current value  needs to take
" them into account.

" Also, we could rewrite:
"
"         %\s\+   →   %*%\s
"                     └───┤
"                         └ scanf() notation (see :h efm-ignore, “pattern matching“)

"}}}

"                                ┌─ escape backslash to protect it from Vim's errorformat parser,
"                                │  so that the regex engine receives `\s`
"                                │
"                                │  ┌─ same thing for the + quantifier
"                                │  │
let &l:efm = '%f%\s%\+\|%l col %c%\s%\+\|%m'
"└┤             └────┤
" │                  └ after Vim has parsed the format string, it becomes \s\+:
" │                    a sequence of whitespace
" │
" └ using `:let` instead of `setl` makes the value more readable
"   otherwise, we would need to escape any:
"
"           • bar
"
"             here we still escape a bar, but it's only for the regex engine
"             `:set` would need an additional backslash
"
"           • space
"           • backslash
"           • double quote

" Variables {{{1

" are we in a location list or a quickfix list?
let b:qf_is_loclist = get(get(getwininfo(win_getid()), 0, {}), 'loclist', 0)

" Alignment {{{1

" align the columns (more readable)
" EXCEPT when the qfl is populated by `:WTF`
if  b:qf_is_loclist
\|| get(getqflist({'title':1}), 'title', '') !=# 'Stack trace(s)'

    if executable('column') && executable('sed')
        setl modifiable
        " prepend the first occurrence of a bar with a literal C-a
        sil! exe "%!sed 's/|/\<c-a>|/1'"
        " do the same for the 2nd occurrence
        sil! exe "%!sed 's/|/\<c-a>|/2'"
        " sort the text using the C-a's as delimiters
        sil! exe "%!column -s '\<c-a>' -t"
        setl nomodifiable nomodified
    endif
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
endif

" Noise {{{1

" We  check the  existence of  `b:my_conceal_what`, to  NOT call  `qf#conceal()`
" unconditionally  and always  source the  autoload/ directory,  which would  go
" against its purpose.
"
" TODO:
" However, it still feels wrong to  call an autoload function from the interface
" of a plugin. Maybe  we should move `qf#conceal()` inside  `my_lib`, and rename
" it `my_lib#conceal()`.
if get(b:, 'my_conceal_what', '') != ''
    call qf#conceal(get(b:, 'my_conceal_what', ''))
endif

" Teardown {{{1

let b:undo_ftplugin =          get(b:, 'undo_ftplugin', '')
                    \ .(empty(get(b:, 'undo_ftplugin', '')) ? '' : '|')
                    \ ."
                    \   setl bl< cul< efm< wrap<
                    \ | exe 'au! my_qf * <buffer>'
                    \ | exe 'nunmap <buffer> <cr>'
                    \ | exe 'nunmap <buffer> <c-w><cr>'
                    \ | exe 'nunmap <buffer> <c-w>T'
                    \ | exe 'nunmap <buffer> q'
                    \ | exe 'nunmap <buffer> [ob'
                    \ | exe 'nunmap <buffer> ]ob'
                    \ | exe 'nunmap <buffer> cob'
                    \ | exe 'cuna   <buffer> cfilter'
                    \ | exe 'cuna   <buffer> lfilter'
                    \ | exe 'cuna   <buffer> cupdate'
                    \ | exe 'cuna   <buffer> lupdate'
                    \ | delc Cfilter
                    \ | delc Lfilter
                    \ | delc Cupdate
                    \ | delc Lupdate
                    \  "
