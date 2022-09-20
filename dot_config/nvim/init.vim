call plug#begin('~/.config/nvim/plugged')
" Tools
    Plug 'junegunn/goyo.vim'
    Plug 'neoclide/coc.nvim', {'branch': 'release'}
    Plug 'mhinz/vim-startify'   "thef
    Plug 'jiangmiao/auto-pairs' "insert or delete brackets, parens, quotes in pair
    Plug 'psliwka/vim-smoothie' "Smooth scrolling for vim done right
    Plug 'tpope/vim-surround'
    Plug 'tpope/vim-markdown'
    Plug 'ctrlpvim/ctrlp.vim'

" Color-schemes
    Plug 'morhetz/gruvbox'
    Plug 'EdenEast/nightfox.nvim'

" git
    Plug 'airblade/vim-gitgutter'
    Plug 'tpope/vim-fugitive'

" kotlin-vim
    Plug 'udalov/kotlin-vim'
call plug#end()

set encoding=UTF-8
filetype plugin indent on
syntax on
set autoread wildmode=longest,list,full
set spell spelllang=en_us
set backspace=indent,eol,start confirm
set shiftwidth=4 autoindent smartindent tabstop=4 softtabstop=4 expandtab  
autocmd FileType * setlocal formatoptions-=c formatoptions-=r formatoptions-=o
set hlsearch incsearch ignorecase
set laststatus=2 cmdheight=1
au BufRead,BufNewFile *.fountain set filetype=fountain
set splitbelow splitright 
set nobackup nowritebackup

"Status-line
set statusline=
set statusline+=%#IncSearch#
set statusline+=\ %y
set statusline+=\ %r
set statusline+=%#CursorLineNr#
set statusline+=\ %F
set statusline+=%= "Right side settings
set statusline+=%#Search#
set statusline+=\ %l/%L
set statusline+=\ [%c]

"Key-bindings
let mapleader=","
nnoremap <leader>n :Explore<CR>
nnoremap <leader><Space> :CtrlP<CR>
nnoremap <leader><ENTER> :Goyo<CR>
nnoremap <leader>, :vsplit ~/.config/nvim/init.vim<CR>
nnoremap <leader>g :GitGutterDisable <BAR> :set laststatus=0 <CR>
nnoremap <C-g> :set spelllang=de_de<CR>
nnoremap <C-l> :set background=light<CR>
nnoremap <C-s> :source ~/.config/nvim/init.vim<CR>

"nnoremap <Up> :resize +2<CR> 
"nnoremap <Down> :resize -2<CR>
"nnoremap <Left> :vertical resize +2<CR>
"nnoremap <Right> :vertical resize -2<CR>

xnoremap K :move '<-2<CR>gv-gv
xnoremap J :move '>+1<CR>gv-gv

nnoremap Q <nop>

nnoremap <leader>h <C-W>h
nnoremap <leader>j <C-W>j
nnoremap <leader>k <C-W>k
nnoremap <leader>l <C-W>l

set clipboard+=unnamedplus

" Copy to osx clipboard
vnoremap <C-c> "*y<CR>
vnoremap y "*y<CR>
noremap Y y$
vnoremap y myy`y
vnoremap Y myY`y
let g:multi_cursor_next_key='<C-n>'
let g:multi_cursor_prev_key='<C-p>'
let g:multi_cursor_skip_key='<C-x>'
" let g:multi_cursor_quit_key='<Esc>'

colorscheme nightfox

set background=dark cursorline termguicolors

hi! Normal ctermbg=NONE guibg=NONE 
hi! NonText ctermbg=NONE guibg=NONE guifg=NONE ctermfg=NONE

