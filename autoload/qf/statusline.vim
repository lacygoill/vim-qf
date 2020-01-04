fu qf#statusline#title(is_focused) abort
    " Remember that all the code in this function is evaluated in the context of
    " the window for which the status line is built.
    " So even if the  function is called for a *non-focused*  qf window, you can
    " reliably query a buffer/window variable local to the latter.
    let pfx = get(b:, 'qf_is_loclist', 0) ? '[LL] ': '[QF] '
    if !exists('w:quickfix_title') || w:quickfix_title =~# '\<TOC$'
        return ''
    elseif !a:is_focused
        return pfx
    else
        let len = len(w:quickfix_title)
        " Why not using `.80` in the outer `%{qf#...()}`?{{{
        "
        " When the title is too long, Vim would truncate its start.
        " This would include `[LL]`/`[QF]`.
        " I want to always see the type of  the list (qfl or ll), as well as the
        " start of the command which produced it.
        "}}}
        " And why not using `%<` after the outer `%{qf#...()}`?{{{
        "
        " When the title is too long, Vim would truncate the line address.
        " I want to always see where I am in the list.
        "}}}
        return pfx..(len > 80 ? w:quickfix_title[:79]..'»' : w:quickfix_title)
    endif
endfu

