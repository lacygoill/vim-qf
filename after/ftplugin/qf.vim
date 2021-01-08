vim9

# Commands {{{1
# CRemoveInvalid {{{2

com -bar -buffer CRemoveInvalid qf#removeInvalidEntries()

# Csave / Crestore / Cremove {{{2

com -bar -buffer -bang -nargs=1 -complete=custom,qf#save_restore#complete Csave qf#save_restore#save(<q-args>, <bang>0)
com -bar -buffer -nargs=? -complete=custom,qf#save_restore#complete Crestore qf#save_restore#restore(<q-args>)
com -bar -buffer -bang -nargs=1 -complete=custom,qf#save_restore#complete Cremove qf#save_restore#remove(<q-args>, <bang>0)

# Cconceal {{{2

com -bar -buffer -range Cconceal qf#concealOrDelete(<line1>, <line2>)

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

com -bang -buffer -nargs=? -complete=custom,qf#cfilterComplete Cfilter
    \ qf#cfilter(<bang>0, <q-args>, <q-mods>)

# Cupdate {{{2

# `:Cupdate` updates the text of each entry in the current qfl.
# Useful after a refactoring, to have a visual feedback.
# Example:
#
#     :cgete system('grep -IRn pat /tmp/some_dir/')
#     :noa cfdo %s/pat/rep/ge | update
#     :Cupdate

com -bar -buffer Cupdate qf#cupdate(<q-mods>)
#}}}1
# Mappings {{{1

# disable some keys, to avoid annoying error messages
qf#disable_some_keys(['a', 'd', 'gj', 'gqq', 'i', 'o', 'r', 'u', 'x'])

nno <buffer><nowait> <c-q> <cmd>Csave default<cr>
nno <buffer><nowait> <c-r> <cmd>Crestore default<cr>

nno <buffer><nowait> <c-s> <cmd>call qf#openManual('split')<cr>
nno <buffer><nowait> <c-v><c-v> <cmd>call qf#openManual('vert split')<cr>
nno <buffer><nowait> <c-t> <cmd>call qf#openManual('tabpage')<cr>
# FYI:{{{
#
# By default:
#
#     C-w T  moves the current window to a new tab page
#     C-w t  moves the focus to the top window in the current tab page
#}}}

nno <buffer><nowait> <cr> <cmd>call qf#openManual('nosplit')<cr>
nmap <buffer><nowait> <c-w><cr> <c-s>

nno <buffer><expr><nowait> D  qf#concealOrDelete()
nno <buffer><expr><nowait> DD qf#concealOrDelete() .. '_'
xno <buffer><expr><nowait> D  qf#concealOrDelete()

nno <buffer><nowait>cof <cmd>call qf#toggleFullFilePath()<cr>

nno <buffer><nowait> p <cmd>call qf#preview#open()<cr>
nno <buffer><nowait> P <cmd>call qf#preview#open(v:true)<cr>

nno <buffer><nowait> q <cmd>call qf#quit()<cr>

# Options {{{1

setl nobuflisted

setl cursorline nowrap

# the 4  spaces before `%l`  make sure that  the line address  is well-separated
# from the title, even when the latter is long and the terminal window is narrow
&l:stl = '%{qf#statusline#title()}%=    %l/%L '

# efm {{{2
# Why do you set `'efm'`?{{{
#
#     :vim /fu/gj %
#     :setl ma | keepj $d_ | setl noma
#     :cgetb
#
# The new qfl is not interactive.
# This is because `:cgetb` interprets the contents of the qfl thanks to `'efm'`,
# (contrary to `:grep` which uses `'gfm'`).
#
# The default global value is very long:
#
#     put =&g:efm | s/\\\@1<!,/\r/g
#
# But it seems  it doesn't contain any  value describing the contents  of a qfl.
# IOW, it's designed to interpret the output of some shell commands and populate
# the qfl.  It's not designed to parse the qfl itself.
#}}}
# Could I use a simpler value?{{{
#
# Yes, if you didn't align the text in the qfl:
#
#     &l:efm = '%f\|%l col %c\|%m'
#
# But the  alignment adds extra whitespace,  so our current value  needs to take
# them into account.
#}}}

#                          ┌ all meta symbols (\ . # [), including the backslash,
#                          │ have to be written with a leading '%'
#                          │ (see :h `efm-ignore`)
#                          │
&l:efm = '%f%*\s\|%l col %c%*\s\|%m'
#│              ├──┘
#│              └ scanf() notation for `%\s%\+`(see `:h efm-ignore /pattern matching`)
#└ using `setl` would make the value less readable;
#  we would need to escape any:
#
#    - backslash
#
#    - bar
#
#      here we still escape a bar, but it's only for the regex engine
#      `:set` would need an additional backslash
#
#    - comma
#
#      We need to escape a comma even  without `:setl`, because a comma has a
#      special meaning for `'efm'`: separation between 2 formats.
#
#      But with `:set` we would need a double backslash, because a comma has
#      also a special meaning for `:set`: separation between 2 option values.
#
#    - double quote
#
#    - space
#}}}2

# Variables {{{1

# Are we viewing a location list or a quickfix list?
const b:qf_is_loclist = win_getid()->getwininfo()[0].loclist

# Matches {{{1

# Why reset 'cole' and 'cocu'?{{{
#
# The  2nd time  we display  a  qf buffer  in  the same  window, there's  no
# guarantee that we're going to conceal anything.
#}}}
set cocu< cole<
au Syntax qf ++once qf#concealLtagPatternColumn()

# Teardown {{{1

b:undo_ftplugin = get(b:, 'undo_ftplugin', 'exe')
    .. '| call qf#undoFtplugin()'

