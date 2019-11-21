fu qf#statusline#buffer() abort
    return (get(w:, 'quickfix_title', '') =~# '\<TOC$'
    \         ? ''
    \         : (get(b:, 'qf_is_loclist', 0) ? '[LL] ': '[QF] '))
    \ ..(exists('w:quickfix_title')? '  '..w:quickfix_title[:77] : '')
endfu

