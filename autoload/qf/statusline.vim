fu qf#statusline#buffer() abort
    if ! exists('w:quickfix_title') || w:quickfix_title =~# '\<TOC$'| return '' | endif
    let len = len(w:quickfix_title)
    return (get(b:, 'qf_is_loclist', 0) ? '[LL] ': '[QF] ')
        \ ..(len > 80 ? '«'..w:quickfix_title[len-79:] : w:quickfix_title)
endfu

