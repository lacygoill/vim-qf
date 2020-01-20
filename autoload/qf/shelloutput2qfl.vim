fu qf#shelloutput2qfl#main() abort
    let [curlnum, lastline] = [line('.'), line('$')]
    let loclist = getloclist(0)
    let lnum1= loclist[curlnum-1].lnum
    let winid = getloclist(0, {'filewinid': 0}).filewinid
    let bufnr = winbufnr(winid)
    if curlnum != lastline
        let lnum2 = loclist[curlnum].lnum - 1
    else
        let lnum2 = getbufinfo(bufnr)[0].linecount
    endif
    let lines = getbufline(bufnr, lnum1, lnum2)
    let qfl = getqflist({'lines': lines}).items
    call filter(qfl, {_,v -> v.valid})
    if !empty(qfl)
        let title = substitute(loclist[curlnum-1].text, '^٪', '$', '')
        call setqflist(qfl)
        call setqflist([], 'a', {'title': title})
        lclose | copen
    else
        echo 'the shell output of this command cannot populate a qfl'
    endif
endfu

