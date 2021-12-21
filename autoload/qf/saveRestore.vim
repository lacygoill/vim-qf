vim9script noclear

# How to save the current qfl automatically when quitting Vim, and how to restore it automatically on startup?{{{
#
#     augroup SaveAndRestoreLastQfl | autocmd!
#         autocmd VimLeavePre * SaveLastQfl()
#         autocmd VimEnter * RestoreLastQfl()
#     augroup END
#
#     def SaveLastQfl()
#         var curqfnr: number = getqflist({nr: 0}).nr
#         var qfls: list<dict<any>> = range(1, getqflist({nr: '$'}).nr)
#             ->mapnew((_, v: number): dict<any> => getqflist({nr: v, size: 0, title: 0}))
#             ->filter((_, v: dict<any>): bool =>
#                          v.size != 0
#                       && v.size < 9999
#                       && v.title !~ '^\s*:hub\s\+push\s*$'
#                       && v.nr >= curqfnr
#             )
#         if empty(qfls)
#             unlet! g:MY_LAST_QFL
#             return
#         endif
#         var items: list<dict<any>> = getqflist({nr: qfls[0]['nr'], items: 0}).items
#             ->map((_, v: dict<any>) => extend(v, {
#                 filename: remove(v, 'bufnr')
#                         ->bufname()
#                         ->fnamemodify(':p')
#                 }))
#         g:MY_LAST_QFL = {items: items, title: getqflist({title: 0}).title}
#     enddef
#
#     def RestoreLastQfl()
#         # If there's already a qfl on the stack, or if there's no qfl to restore, don't try to restore anything.
#         # How could there already be a qfl on the stack?{{{
#         #
#         #     $ rg -LS --vimgrep network /etc
#         #     $ vim -q <(!!)
#         #
#         #     $ rg -LS --vimgrep network /etc | vim -q /dev/stdin
#         #
#         #     $ rg -LS --vimgrep network /etc >/tmp/log
#         #     $ vim -q /tmp/log
#         #
#         #     $ vim +'vimgrep /pat/ %' file
#         #
#         #     $ vim -S /tmp/efm.vim
#         #}}}
#         # Why not restoring the qfl if there's already one on the stack?{{{
#         #
#         # Too confusing.
#         # You would expect a certain a qfl, but get a different one.
#         # You may  lose a lot of  time/energy before remembering you  have this code
#         # which restores an old qfl.
#         # This is  especially true if the  two qfl which  end on the stack  are very
#         # similar, which happens when you're refining an 'errorformat'.
#         #}}}
#         # Why not restoring the qfl if `v:servername` is empty?{{{
#         #
#         # I prefer to restore the last qfl in our main Vim instance; the one where a
#         # sessions is tracked.
#         # For all the other  ones, I think it's unexpected to  get the qfl restored;
#         # in particular,  it's surprising to  get a big  list of buffers  even after
#         # running a simple `$ vim`.
#         #}}}
#         if getqflist({size: 0}).size > 0
#         || get(g:, 'MY_LAST_QFL', {})->get('items', [])->empty()
#         || v:servername == ''
#             return
#         endif
#         setqflist([], ' ', {items: g:MY_LAST_QFL.items, title: g:MY_LAST_QFL.title})
#     enddef
#}}}
#   Why don't you use this code?{{{
#
# Saving a big qfl in `~/.viminfo` will make it much bigger.
# The bigger `~/.viminfo` is, the slower Vim starts.
# It  may not  be an  issue when  you start  your first  main Vim  instance, but
# there's no  reason for other  Vim instances to start  slowly because of  a qfl
# they don't care about.
#
# Besides, restarting the  main Vim instance would  take more time if  a big qfl
# needs to be restored.
#}}}

# Init {{{1

const QFL_DIR: string = $HOME .. '/.vim/tmp/qfl'
if !isdirectory(QFL_DIR)
    if !mkdir(QFL_DIR, 'p', 0o700)
        echomsg '[vim-qf] failed to create directory ' .. QFL_DIR
    endif
endif

# Interface {{{1
def qf#saveRestore#complete(_, _, _): string #{{{2
    return QFL_DIR
        ->readdir((n: string): bool => n =~ '\.txt$')
        ->map((_, v: string) => v->fnamemodify(':t:r'))
        ->join("\n")
enddef

def qf#saveRestore#save(arg_fname: string, bang: bool) #{{{2
    if win_gettype() == 'loclist'
        Error('[Csave] sorry, only a quickfix list can be saved, not a location list')
        return
    endif
    var fname: string = Expand(arg_fname)
    if filereadable(fname) && !bang
        Error('[Csave] ' .. fname .. ' is an existing file; add ! to overwrite')
        return
    endif
    g:LAST_QFL = fname
    var items: list<dict<any>> = getqflist({items: 0}).items
    if empty(items)
        echo '[Csave] no quickfix list to save'
        return
    endif
    # Explanation:{{{
    #
    # `remove(v, 'bufnr')` does 2 things:
    #
    #    - it removes the `bufnr` key from every entry in the qfl
    #    - it evaluates to the value which was bound to that key (i.e. the buffer number of the qfl entry)
    #
    # `bufname(...)` converts the buffer number into a buffer name.
    # `fnamemodify(...)` makes sure that the  name is absolute, and not relative
    # to the current working directory.
    #}}}
    items
        ->map((_, v: dict<any>) => extend(v, {
                filename: remove(v, 'bufnr')
                        ->bufname()
                        ->fnamemodify(':p')
        }))
    var qfl: dict<any> = {items: items, title: getqflist({title: 0}).title}
    var lines: list<string> =<< trim END
        vim9script
        var qfl: dict<any> = %s
        var items: list<dict<any>> = qfl.items
        var title: string = qfl.title
        setqflist([], ' ', {items: items, title: title})
    END
    # Why `escape()`?{{{
    #
    # Without, there  would be a  risk of  getting null characters,  which would
    # later break the sourcing of the file.
    # This is because a backslash has a special meaning, even in the replacement
    # part of a substitution.
    #
    # From `:help :s%`
    #
    #    > The special meaning is also used inside the third argument {sub} of
    #    > the |substitute()| function with the following exceptions:
    #    > ...
    #
    # MWE:
    #
    #     let dict = {'a': 'b\nc'}
    #     echo '%s'->substitute('%s', string(dict), '') =~ '\%x00'
    #     1˜
    #
    # We need to make sure it's parsed literally.
    #
    # ---
    #
    # You would still need `escape()` if you replaced `string()` with `json_encode()`.
    # Indeed, the latter may add backslashes to escape literal double quotes:
    #
    #     let dict = {'a': 'b"c'}
    #     echo json_encode(dict)
    #     {"a":"b\"c"}˜
    #            ^
    #
    # And again, those backslashes must be parsed literally by `substitute()`.
    #
    # ---
    #
    # Similar issue with `&` which has a special meaning.
    #}}}
    lines[1] = lines[1]
        ->substitute('%s', string(qfl)->escape('&\'), '')
    writefile(lines, fname)
    echo '[Csave] quickfix list saved in ' .. fname
enddef

def qf#saveRestore#restore(arg_fname: string) #{{{2
    var fname: string
    if arg_fname == ''
        fname = get(g:, 'LAST_QFL', '')
    else
        fname = Expand(arg_fname)
    endif

    if fname == ''
        echo '[Crestore] do not know which quickfix list to restore'
        return
    elseif !filereadable(fname)
        echo '[Crestore] ' .. fname .. ' is not readable'
        return
    endif
    execute 'source ' .. fnameescape(fname)
    cwindow
    echo '[Crestore] quickfix list restored from ' .. fname
enddef

def qf#saveRestore#remove(arg_fname: string, bang: bool) #{{{2
    # Rationale:{{{
    #
    # `:Cremove` and `:Crestore` begins with the same 3 characters.
    # We  could  insert `:Cre`  then  tab  complete,  and choose  `:Cremove`  by
    # accident while we want `:Crestore`.
    # Asking for a bang reduces the risk of such accidents.
    #}}}
    if !bang
        Error('[Cremove] add a bang')
        return
    endif
    var fname: string = Expand(arg_fname)
    if !filereadable(fname)
        echo printf('[Cremove] cannot remove %s ; file not readable', fname)
        return
    endif
    if delete(fname)
        echo '[Cremove] failed to remove ' .. fname
    else
        echo '[Cremove] removed ' .. fname
    endif
enddef
#}}}1
# Util {{{1
def Error(msg: string) #{{{2
    echohl ErrorMsg
    echomsg msg
    echohl NONE
enddef

def Expand(fname: string): string #{{{2
    # Do *not* use the `.vim` extension?{{{
    #
    # It  would lead  to too  many spurious  matches when  we use  this kind  of
    # `:vimgrep` command:
    #
    #     :vim /pat/gj $MYVIMRC ~/.vim/**/*.vim ~/.vim/**/*.snippets ~/.vim/template/**
    #}}}
    return QFL_DIR .. '/' .. fname .. '.txt'
enddef
