vim9script

import autoload 'qf.vim'
import autoload 'qf/preview.vim'
import autoload 'qf/saveRestore.vim'

# Commands {{{1
# CRemoveInvalid {{{2

command -bar -buffer CRemoveInvalid qf.RemoveInvalidEntries()

# Csave / Crestore / Cremove {{{2

command -bar -buffer -bang -nargs=1 -complete=custom,saveRestore.Complete Csave {
    saveRestore.Save(<q-args>, <bang>0)
}
command -bar -buffer -nargs=? -complete=custom,saveRestore.Complete Crestore {
    saveRestore.Restore(<q-args>)
}
command -bar -buffer -bang -nargs=1 -complete=custom,saveRestore.Complete Cremove {
    saveRestore.Remove(<q-args>, <bang>0)
}

# Cconceal {{{2

command -bar -buffer -range Cconceal {
    qf.ConcealOrDelete()
    execute printf('normal! %dGg@%dG', <line1>, <line2>)
}

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

command -bang -buffer -nargs=? -complete=custom,qf.CfilterComplete Cfilter {
    qf.Cfilter(<bang>0, <q-args>, <q-mods>)
}

# Cupdate {{{2

# `:Cupdate` updates the text of each entry in the current qfl.
# Useful after a refactoring, to have a visual feedback.
# Example:
#
#     :cgetexpr system('grep -IRn pat /tmp/some_dir/')
#     :noautocmd cfdo :% substitute/pat/rep/ge | update
#     :Cupdate

command -bar -buffer Cupdate qf.Cupdate(<q-mods>)
#}}}1
# Mappings {{{1

# disable some keys, to avoid annoying error messages
qf.DisableSomeKeys(['a', 'd', 'gj', 'gqq', 'i', 'o', 'r', 'u', 'x'])

nnoremap <buffer><nowait> <C-Q> <ScriptCmd>Csave default<CR>
nnoremap <buffer><nowait> <C-R> <ScriptCmd>Crestore default<CR>

nnoremap <buffer><nowait> <C-S> <ScriptCmd>qf.OpenManual('split')<CR>
nnoremap <buffer><nowait> <C-V><C-V> <ScriptCmd>qf.OpenManual('vertical split')<CR>
nnoremap <buffer><nowait> <C-T> <ScriptCmd>qf.OpenManual('tabpage')<CR>
# FYI:{{{
#
# By default:
#
#     C-w T  moves the current window to a new tab page
#     C-w t  moves the focus to the top window in the current tab page
#}}}

nnoremap <buffer><nowait> <CR> <ScriptCmd>qf.OpenManual('nosplit')<CR>
nmap <buffer><nowait> <C-W><CR> <C-S>

nnoremap <buffer><expr><nowait> D  qf.ConcealOrDelete()
nnoremap <buffer><expr><nowait> DD qf.ConcealOrDelete() .. '_'
xnoremap <buffer><expr><nowait> D  qf.ConcealOrDelete()

nnoremap <buffer><nowait>cof <ScriptCmd>qf.ToggleFullFilePath()<CR>

nnoremap <buffer><nowait> p <ScriptCmd>preview.Open()<CR>
nnoremap <buffer><nowait> P <ScriptCmd>preview.Open(true)<CR>

nnoremap <buffer><nowait> q <ScriptCmd>qf.Quit()<CR>

# Options {{{1

&l:buflisted = false

&l:cursorline = true
&l:wrap = false

# the 4  spaces before `%l`  make sure that  the line address  is well-separated
# from the title, even when the latter is long and the terminal window is narrow
&l:statusline = '%{qf#statusline#Title()}%=    %l/%L '

# Matches {{{1

# Why reset 'conceallevel' and 'concealcursor'?{{{
#
# The  2nd time  we display  a  qf buffer  in  the same  window, there's  no
# guarantee that we're going to conceal anything.
#}}}
set concealcursor< conceallevel<
autocmd Syntax qf ++once qf.ConcealLtagPatternColumn()

# Teardown {{{1

b:undo_ftplugin = (get(b:, 'undo_ftplugin') ?? 'execute')
    .. '| call qf#UndoFtplugin()'
