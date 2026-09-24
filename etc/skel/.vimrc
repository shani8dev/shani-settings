" ~/.vimrc - ShaniOS. Starts from Vim's own defaults.vim (which a ~/.vimrc
" would otherwise switch off), then adds a few comfort settings.
unlet! skip_defaults_vim
source $VIMRUNTIME/defaults.vim

set number relativenumber
set mouse=a
" Arch's vim is built without X/Wayland clipboard; "+y copies to the
" desktop clipboard through the terminal (OSC 52) instead. Not unnamedplus:
" terminals that can't answer an OSC 52 paste would make every `p` hang.
silent! packadd osc52
silent! set clipmethod+=osc52
set expandtab shiftwidth=4 tabstop=4 smartindent
set ignorecase smartcase hlsearch
set splitright splitbelow
set undofile undodir=~/.local/state/vim/undo//
set termguicolors
set signcolumn=auto
set laststatus=2
silent! call mkdir(expand('~/.local/state/vim/undo'), 'p')
silent! colorscheme habamax
nnoremap <silent> <Esc><Esc> :nohlsearch<CR>
