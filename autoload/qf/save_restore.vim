if exists('g:autoloaded_qf#save_restore')
    finish
endif
let g:autoloaded_qf#save_restore = 1

" How to save the current qfl automatically when quitting Vim, and how to restore it automatically on startup?{{{
"
"     augroup save_and_restore_last_qfl
"         au!
"         au VimLeavePre * call s:save_last_qfl()
"         au VimEnter    * call s:restore_last_qfl()
"     augroup END
"
"     fu s:save_last_qfl() abort
"         let curqfnr = getqflist({'nr': 0}).nr
"         let qfls = filter(map(range(1, getqflist({'nr': '$'}).nr),
"             \ {_,v -> getqflist({'nr': v, 'size': 0, 'title': 0})}),
"             \ {_,v -> v.size != 0
"             \      && v.size < 9999
"             \      && v.title !~# '^\s*:hub\s\+push\s*$'
"             \      && v.nr >= curqfnr})
"         if empty(qfls) | unlet! g:MY_LAST_QFL | return | endif
"         let items = getqflist({'nr': qfls[0].nr, 'items': 0}).items
"         call map(items, {_,v -> extend(v, {'filename': fnamemodify(bufname(remove(v, 'bufnr')), ':p')})})
"         let g:MY_LAST_QFL = {'items': items, 'title': getqflist({'title': 0}).title}
"     endfu
"
"     fu s:restore_last_qfl() abort
"         " If there's already a qfl on the stack, or if there's no qfl to restore, don't try to restore anything.
"         " How could there already be a qfl on the stack?{{{
"         "
"         "     $ rg -LS --vimgrep network /etc
"         "     $ vim -q <(!!)
"         "
"         "     $ rg -LS --vimgrep network /etc | vim -q /dev/stdin
"         "
"         "     $ rg -LS --vimgrep network /etc >/tmp/log
"         "     $ vim -q /tmp/log
"         "
"         "     $ vim +'vimgrep /pat/ %' file
"         "
"         "     $ vim -S /tmp/efm.vim
"        "}}}
"         " Why not restoring the qfl if there's already one on the stack?{{{
"         "
"         " Too confusing.
"         " You would expect a certain a qfl, but get a different one.
"         " You may  lose a lot of  time/energy before remembering you  have this code
"         " which restores an old qfl.
"         " This is  especially true if the  two qfl which  end on the stack  are very
"         " similar, which happens when you're refining an 'efm'.
"        "}}}
"         " Why not restoring the qfl if `v:servername` is empty?{{{
"         "
"         " I prefer to restore the last qfl in our main Vim instance; the one where a
"         " sessions is tracked.
"         " For all the other  ones, I think it's unexpected to  get the qfl restored;
"         " in particular,  it's surprising to  get a big  list of buffers  even after
"         " running a simple `$ vim`.
"        "}}}
"         if getqflist({'size':0}).size
"         \ || empty(get(get(g:, 'MY_LAST_QFL', {}), 'items', []))
"         \ || v:servername is# ''
"             return
"         endif
"         call setqflist([], ' ', {'items': g:MY_LAST_QFL.items, 'title': g:MY_LAST_QFL.title})
"     endfu
"}}}
"   Why don't you use this code?{{{
"
" Saving a big qfl in `~/.viminfo` will make it much bigger.
" The bigger `~/.viminfo` is, the slower Vim starts.
" It  may not  be an  issue when  you start  your first  main Vim  instance, but
" there's no  reason for other  Vim instances to start  slowly because of  a qfl
" they don't care about.
"
" Besides, restarting the  main Vim instance would  take more time if  a big qfl
" needs to be restored.
"}}}

" Init {{{1

const s:QFL_DIR = $HOME..'/.vim/tmp/qfl'
if !isdirectory(s:QFL_DIR)
    if mkdir(s:QFL_DIR, 'p', 0700)
        echom '[vim-qf] failed to create directory '..s:QFL_DIR
    endif
endif

" Interface {{{1
fu qf#save_restore#complete(_a, _l, _p) abort "{{{2
    return join(map(glob(s:QFL_DIR..'/*.txt', 0, 1), {_,v -> fnamemodify(v, ':t:r')}), "\n")
endfu

fu qf#save_restore#save(fname, bang) abort "{{{2
    if b:qf_is_loclist
        return s:error('[Csave] sorry, only a quickfix list can be saved, not a location list')
    endif
    let fname = s:expand(a:fname)
    if filereadable(fname) && !a:bang
        return s:error('[Csave] '..fname..' is an existing file; add ! to overwrite')
    endif
    let g:LAST_QFL = fname
    let items = getqflist({'items': 0}).items
    if empty(items) | echo '[Csave] no quickfix list to save' | return | endif
    " Explanation:{{{
    "
    " `remove(v, 'bufnr')` does 2 things:
    "
    "    - it removes the `bufnr` key from every entry in the qfl
    "    - it evaluates to the value which was bound to that key (i.e. the buffer number of the qfl entry)
    "
    " `bufname(...)` converts the buffer number into a buffer name.
    " `fnamemodify(...)` makes sure that the  name is absolute, and not relative
    " to the current working directory.
    "}}}
    call map(items, {_,v -> extend(v, {'filename': fnamemodify(bufname(remove(v, 'bufnr')), ':p')})})
    let qfl = {'items': items, 'title': getqflist({'title': 0}).title}
    let lines =<< trim END
        let s:qfl = %s
        let s:items = s:qfl.items
        let s:title = s:qfl.title
        call setqflist([], ' ', {'items': s:items, 'title': s:title})
        unlet! s:qfl s:items s:title
    END
    " Why `escape()`?{{{
    "
    " Without, there  would be a  risk of  getting null characters,  which would
    " later break the sourcing of the file.
    " This is because a backslash has a special meaning, even in the replacement
    " part of a substitution.
    "
    " From `:h :s%`
    "
    " >    The special meaning is also used inside the third argument {sub} of
    " >    the |substitute()| function with the following exceptions:
    " >    ...
    "
    " MWE:
    "
    "     let dict = {'a': 'b\nc'}
    "     echo substitute('%s', '%s', string(dict), '') =~# '\%x00'
    "     1~
    "
    " We need to make sure it's parsed literally.
    "
    " ---
    "
    " You would still need `escape()` if you replaced `string()` with `json_encode()`.
    " Indeed, the latter may add backslashes to escape literal double quotes:
    "
    "     let dict = {'a': 'b"c'}
    "     echo json_encode(dict)
    "     {"a":"b\"c"}~
    "            ^
    "
    " And again, those backslashes must be parsed literally by `substitute()`.
    "
    " ---
    "
    " Similar issue with `&` which has a special meaning.
    "}}}
    let lines[0] = substitute(lines[0], '%s', escape(string(qfl), '&\'), '')
    call writefile(lines, fname)
    echo '[Csave] quickfix list saved in '..fname
endfu

fu qf#save_restore#restore(fname) abort "{{{2
    if a:fname is# ''
        let fname = get(g:, 'LAST_QFL', '')
    else
        let fname = s:expand(a:fname)
    endif

    if !filereadable(fname)
        echo '[Crestore] '..fname..' is not readable'
        return
    endif
    exe 'so '..fnameescape(fname)
    cw
    echo '[Crestore] quickfix list restored from '..fname
endfu

fu qf#save_restore#remove(fname, bang) abort "{{{2
    " Rationale:{{{
    "
    " `:Cremove` and `:Crestore` begins with the same 3 characters.
    " We  could  insert `:Cre`  then  tab  complete,  and choose  `:Cremove`  by
    " accident while we want `:Crestore`.
    " Asking for a bang reduces the risk of such accidents.
    "}}}
    if !a:bang | return s:error('[Cremove] add a bang') | endif
    let fname = s:expand(a:fname)
    if !filereadable(fname)
        echo '[Cremove] cannot remove '..fname..' ; file not readable' | return
    endif
    if delete(fname)
        echo '[Cremove] failed to remove '..fname
    else
        echo '[Cremove] removed '..fname
    endif
endfu
"}}}1
" Util {{{1
fu s:error(msg) abort "{{{2
    echohl ErrorMsg
    echo a:msg
    echohl NONE
endfu

fu s:expand(fname) abort "{{{2
    " Do *not* use the `.vim` extension?{{{
    "
    " It  would lead  to too  many spurious  matches when  we use  this kind  of
    " `:vimgrep` command:
    "
    "     :vim /pat/gj $MYVIMRC ~/.vim/**/*.vim ~/.vim/**/*.snippets ~/.vim/template/**
    "}}}
    return s:QFL_DIR..'/'..a:fname..'.txt'
endfu

