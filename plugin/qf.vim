vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# TODO: Implement a mapping/command which would fold all entries belonging to the same file.
# See here for inspiration: https://github.com/fcpg/vim-kickfix

# TODO: Fold invalid entries and/or highlight them in some way.
# Should  we prevent  `qf#align()`  from trying  to aligning  the  fields of  an
# invalid entry (there's nothing to align anyway...)?

# TODO: Add  custom  syntax highlighting  so  that  entries  from one  file  are
# highlighted  in one  way, while  the next  extries from  a different  file are
# highlighted in another way.
# See here for inspiration: https://github.com/fcpg/vim-kickfix

# TODO: Add a command to sort qf entries in some way?
# Inspiration: https://github.com/vim/vim/issues/6412 (look for `qf#sort#qflist()`)

# TODO: Automatically add a sign for each entry in the qfl.
# Inspiration: https://gist.github.com/BoltsJ/5942ecac7f0b0e9811749ef6e19d2176

# Options {{{1

# don't let the default qf filetype plugin set `'statusline'`, we'll do it ourselves
g:qf_disable_statusline = 1

&quickfixtextfunc = 'qf#align'

# Commands {{{1

command -bar CFreeStack qf#cfreeStack()
command -bar LFreeStack qf#cfreeStack(true)

command -nargs=1 -range=% -addr=buffers CGrepBuffer qf#cgrepBuffer(<line1>, <line2>, <q-args>)
command -nargs=1 -range=% -addr=buffers LGrepBuffer qf#cgrepBuffer(<line1>, <line2>, <q-args>, true)

# Autocmds {{{1

# Automatically open the qf/ll window after a quickfix command.
augroup MyQuickfix | autocmd!

    # Do *not* remove the `++nested` flag.{{{
    #
    # Other plugins may need to be informed when the qf window is opened.
    # See: https://github.com/romainl/vim-qf/pull/70
    #}}}
    autocmd QuickFixCmdPost * ++nested expand('<amatch>')->qf#openAuto()
    #       │                                   │
    #       │                                   └ name of the command which was run
    #       └ after a quickfix command is run

    autocmd FileType qf qf#preview#mappings()
augroup END
