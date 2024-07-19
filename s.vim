let SessionLoad = 1
let s:so_save = &g:so | let s:siso_save = &g:siso | setg so=0 siso=0 | setl so=-1 siso=-1
let v:this_session=expand("<sfile>:p")
silent only
silent tabonly
cd ~/projects/zig/config-watcher
if expand('%') == '' && !&modified && line('$') <= 1 && getline(1) == ''
  let s:wipebuf = bufnr('%')
endif
let s:shortmess_save = &shortmess
if &shortmess =~ 'A'
  set shortmess=aoOA
else
  set shortmess=aoO
endif
badd +49 fsmanip.zig
badd +49 main.zig
badd +95 /snap/zig/11982/lib/std/mem/Allocator.zig
badd +4 utils.zig
badd +14 ~/.config/nvim/lua/custom/plugins/zen.lua
badd +6 ~/projects/zig/config-watcher/env-parser.zig
badd +1 ~/projects/zig/config-watcher/errors.zig
badd +5 ~/projects/zig/config-watcher/r_errors.zig
badd +9 ~/projects/zig/config-watcher/build.zig
badd +9 /snap/zig/11982/lib/std/testing.zig
badd +441 /snap/zig/11982/lib/std/hash_map.zig
badd +407 /snap/zig/11982/lib/std/heap/general_purpose_allocator.zig
badd +1 ../various/useful_tests.zig
badd +26 /snap/zig/11982/lib/std/heap/arena_allocator.zig
badd +13 ~/projects/zig/config-watcher/s_config.zig
badd +179 /snap/zig/11982/lib/std/fs.zig
badd +1474 /snap/zig/11982/lib/std/fs/Dir.zig
badd +253 /snap/zig/11982/lib/std/fs/path.zig
badd +2966 /snap/zig/11982/lib/std/posix.zig
badd +1649 /snap/zig/11982/lib/std/c.zig
badd +756 /snap/zig/11982/lib/std/os/linux.zig
argglobal
%argdel
$argadd .
edit fsmanip.zig
wincmd t
let s:save_winminheight = &winminheight
let s:save_winminwidth = &winminwidth
set winminheight=0
set winheight=1
set winminwidth=0
set winwidth=1
argglobal
balt main.zig
setlocal fdm=manual
setlocal fde=0
setlocal fmr={{{,}}}
setlocal fdi=#
setlocal fdl=0
setlocal fml=1
setlocal fdn=20
setlocal fen
silent! normal! zE
let &fdl = &fdl
let s:l = 39 - ((17 * winheight(0) + 17) / 35)
if s:l < 1 | let s:l = 1 | endif
keepjumps exe s:l
normal! zt
keepjumps 39
normal! 0
tabnext 1
if exists('s:wipebuf') && len(win_findbuf(s:wipebuf)) == 0 && getbufvar(s:wipebuf, '&buftype') isnot# 'terminal'
  silent exe 'bwipe ' . s:wipebuf
endif
unlet! s:wipebuf
set winheight=1 winwidth=20
let &shortmess = s:shortmess_save
let &winminheight = s:save_winminheight
let &winminwidth = s:save_winminwidth
let s:sx = expand("<sfile>:p:r")."x.vim"
if filereadable(s:sx)
  exe "source " . fnameescape(s:sx)
endif
let &g:so = s:so_save | let &g:siso = s:siso_save
doautoall SessionLoadPost
unlet SessionLoad
" vim: set ft=vim :
