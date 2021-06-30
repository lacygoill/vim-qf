vim9script

# Commands {{{1
# CRemoveInvalid {{{2

command -bar -buffer CRemoveInvalid qf#removeInvalidEntries()

# Csave / Crestore / Cremove {{{2

command -bar -buffer -bang -nargs=1 -complete=custom,qf#saveRestore#complete
    \ Csave qf#saveRestore#save(<q-args>, <bang>0)
command -bar -buffer -nargs=? -complete=custom,qf#saveRestore#complete
    \ Crestore qf#saveRestore#restore(<q-args>)
command -bar -buffer -bang -nargs=1 -complete=custom,qf#saveRestore#complete
    \ Cremove qf#saveRestore#remove(<q-args>, <bang>0)

# Cconceal {{{2

command -bar -buffer -range Cconceal qf#concealOrDelete(<line1>, <line2>)

# Cfilter {{{2
# Documentation:{{{
#
#     :Cfilter[!] /{pat}/
#     :Cfilter[!]  {pat}
#
#             Filter the quickfix looking  for pattern, `{pat}`.  The pattern can
#             match the filename  or text.  Providing `!` will  invert the match
#             (just like `grep -v`).
#}}}

# Do not give the `-bar` attribute to the commands.
# It would break a pattern containing a bar (for example, for an alternation).

command -bang -buffer -nargs=? -complete=custom,qf#cfilterComplete
    \ Cfilter qf#cfilter(<bang>0, <q-args>, <q-mods>)

# Cupdate {{{2

# `:Cupdate` updates the text of each entry in the current qfl.
# Useful after a refactoring, to have a visual feedback.
# Example:
#
#     :cgetexpr system('grep -IRn pat /tmp/some_dir/')
#     :noautocmd cfdo :% substitute/pat/rep/ge | update
#     :Cupdate

command -bar -buffer Cupdate qf#cupdate(<q-mods>)
#}}}1
# Mappings {{{1

# disable some keys, to avoid annoying error messages
qf#disableSomeKeys(['a', 'd', 'gj', 'gqq', 'i', 'o', 'r', 'u', 'x'])

nnoremap <buffer><nowait> <C-Q> <Cmd>Csave default<CR>
nnoremap <buffer><nowait> <C-R> <Cmd>Crestore default<CR>

nnoremap <buffer><nowait> <C-S> <Cmd>call qf#openManual('split')<CR>
nnoremap <buffer><nowait> <C-V><C-V> <Cmd>call qf#openManual('vertical split')<CR>
nnoremap <buffer><nowait> <C-T> <Cmd>call qf#openManual('tabpage')<CR>
# FYI:{{{
#
# By default:
#
#     C-w T  moves the current window to a new tab page
#     C-w t  moves the focus to the top window in the current tab page
#}}}

nnoremap <buffer><nowait> <CR> <Cmd>call qf#openManual('nosplit')<CR>
nmap <buffer><nowait> <C-W><CR> <C-S>

nnoremap <buffer><expr><nowait> D  qf#concealOrDelete()
nnoremap <buffer><expr><nowait> DD qf#concealOrDelete() .. '_'
xnoremap <buffer><expr><nowait> D  qf#concealOrDelete()

nnoremap <buffer><nowait>cof <Cmd>call qf#toggleFullFilePath()<CR>

nnoremap <buffer><nowait> p <Cmd>call qf#preview#open()<CR>
nnoremap <buffer><nowait> P <Cmd>call qf#preview#open(v:true)<CR>

nnoremap <buffer><nowait> q <Cmd>call qf#quit()<CR>

# Options {{{1

&l:buflisted = false

&l:cursorline = true
&l:wrap = false

# the 4  spaces before `%l`  make sure that  the line address  is well-separated
# from the title, even when the latter is long and the terminal window is narrow
&l:statusline = '%{qf#statusline#title()}%=    %l/%L '

# Variables {{{1

# Are we viewing a location list or a quickfix list?
const b:qf_is_loclist = win_getid()->getwininfo()[0]['loclist']

# Matches {{{1

# Why reset 'conceallevel' and 'concealcursor'?{{{
#
# The  2nd time  we display  a  qf buffer  in  the same  window, there's  no
# guarantee that we're going to conceal anything.
#}}}
set concealcursor< conceallevel<
autocmd Syntax qf ++once qf#concealLtagPatternColumn()

# Teardown {{{1

b:undo_ftplugin = get(b:, 'undo_ftplugin', 'execute')
    .. '| call qf#undoFtplugin()'

