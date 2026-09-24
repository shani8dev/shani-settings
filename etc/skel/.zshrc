# ~/.zshrc - ShaniOS (zsh is the default login shell)

## History: big, shared live between terminals, no duplicates
HISTFILE=~/.zhistory
HISTSIZE=50000
SAVEHIST=50000
setopt extended_history          # timestamps
setopt inc_append_history        # write as you go, not on exit
setopt share_history             # other terminals see new commands
setopt hist_ignore_all_dups      # drop older duplicates
setopt hist_ignore_space         # " cmd" stays out of history
setopt hist_reduce_blanks
setopt hist_verify               # !! expands for review before running

## Options
setopt correct                   # offer to fix mistyped commands
setopt extendedglob              # ^, ~, # in globs
setopt nocaseglob                # case-insensitive globbing
setopt numericglobsort           # file10 after file9
setopt rcexpandparam             # array expansion with parameters
setopt nocheckjobs               # no warning about running jobs on exit
setopt nobeep
setopt autocd                    # type a directory to cd into it
setopt auto_pushd pushd_ignore_dups pushdminus   # cd -<TAB> = recent dirs
setopt interactive_comments      # allow # comments at the prompt

## Completion (zsh-completions installs into site-functions itself)
[[ -d ~/.cache/zsh ]] || mkdir -p ~/.cache/zsh
autoload -Uz compinit
compinit -d ~/.cache/zsh/zcompdump
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'  # case-insensitive, then partial
zstyle ':completion:*' rehash true                              # see new executables at once
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' completer _expand _complete _ignored _approximate
zstyle ':completion:*' menu select
zstyle ':completion:*' group-name ''
zstyle ':completion:*' select-prompt '%SScrolling active: current selection at %p%s'
zstyle ':completion:*:descriptions' format '%F{1}-- %d --%f'
zstyle ':completion:*:warnings' format '%F{8}-- no matches --%f'
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=31'
zstyle ':completion:*' accept-exact '*(N)'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.cache/zsh/zcache
autoload -U +X bashcompinit && bashcompinit

# Terminal title: user@host:dir
function set_win_title() { print -Pn "\e]0;%n@%m:%~\a" }
precmd_functions+=(set_win_title)

## Keys
# Use emacs key bindings
bindkey -e

# [PageUp] - Up a line of history
if [[ -n "${terminfo[kpp]}" ]]; then
  bindkey -M emacs "${terminfo[kpp]}" up-line-or-history
  bindkey -M viins "${terminfo[kpp]}" up-line-or-history
  bindkey -M vicmd "${terminfo[kpp]}" up-line-or-history
fi
# [PageDown] - Down a line of history
if [[ -n "${terminfo[knp]}" ]]; then
  bindkey -M emacs "${terminfo[knp]}" down-line-or-history
  bindkey -M viins "${terminfo[knp]}" down-line-or-history
  bindkey -M vicmd "${terminfo[knp]}" down-line-or-history
fi

# [Home] - Go to beginning of line
if [[ -n "${terminfo[khome]}" ]]; then
  bindkey -M emacs "${terminfo[khome]}" beginning-of-line
  bindkey -M viins "${terminfo[khome]}" beginning-of-line
  bindkey -M vicmd "${terminfo[khome]}" beginning-of-line
fi
# [End] - Go to end of line
if [[ -n "${terminfo[kend]}" ]]; then
  bindkey -M emacs "${terminfo[kend]}"  end-of-line
  bindkey -M viins "${terminfo[kend]}"  end-of-line
  bindkey -M vicmd "${terminfo[kend]}"  end-of-line
fi

# [Shift-Tab] - move through the completion menu backwards
if [[ -n "${terminfo[kcbt]}" ]]; then
  bindkey -M emacs "${terminfo[kcbt]}" reverse-menu-complete
  bindkey -M viins "${terminfo[kcbt]}" reverse-menu-complete
  bindkey -M vicmd "${terminfo[kcbt]}" reverse-menu-complete
fi

# [Backspace] - delete backward
bindkey -M emacs '^?' backward-delete-char
bindkey -M viins '^?' backward-delete-char
bindkey -M vicmd '^?' backward-delete-char
# [Delete] - delete forward
if [[ -n "${terminfo[kdch1]}" ]]; then
  bindkey -M emacs "${terminfo[kdch1]}" delete-char
  bindkey -M viins "${terminfo[kdch1]}" delete-char
  bindkey -M vicmd "${terminfo[kdch1]}" delete-char
else
  bindkey -M emacs "^[[3~" delete-char
  bindkey -M viins "^[[3~" delete-char
  bindkey -M vicmd "^[[3~" delete-char

  bindkey -M emacs "^[3;5~" delete-char
  bindkey -M viins "^[3;5~" delete-char
  bindkey -M vicmd "^[3;5~" delete-char
fi

typeset -g -A key
if (( ${+terminfo[smkx]} && ${+terminfo[rmkx]} )); then
	autoload -Uz add-zle-hook-widget
	function zle_application_mode_start { echoti smkx }
	function zle_application_mode_stop { echoti rmkx }
	add-zle-hook-widget -Uz zle-line-init zle_application_mode_start
	add-zle-hook-widget -Uz zle-line-finish zle_application_mode_stop
fi

# Control Left - go back a word
key[Control-Left]="${terminfo[kLFT5]}"
if [[ -n "${key[Control-Left]}"  ]]; then
	bindkey -M emacs "${key[Control-Left]}"  backward-word
	bindkey -M viins "${key[Control-Left]}"  backward-word
	bindkey -M vicmd "${key[Control-Left]}"  backward-word
fi

# Control Left - go forward a word
key[Control-Right]="${terminfo[kRIT5]}"
if [[ -n "${key[Control-Right]}" ]]; then
	bindkey -M emacs "${key[Control-Right]}" forward-word
	bindkey -M viins "${key[Control-Right]}" forward-word
	bindkey -M vicmd "${key[Control-Right]}" forward-word
fi

# Alt Left - go back a word
key[Alt-Left]="${terminfo[kLFT3]}"
if [[ -n "${key[Alt-Left]}"  ]]; then
	bindkey -M emacs "${key[Alt-Left]}"  backward-word
	bindkey -M viins "${key[Alt-Left]}"  backward-word
	bindkey -M vicmd "${key[Alt-Left]}"  backward-word
fi

# Control Right - go forward a word
key[Alt-Right]="${terminfo[kRIT3]}"
if [[ -n "${key[Alt-Right]}" ]]; then
	bindkey -M emacs "${key[Alt-Right]}" forward-word
	bindkey -M viins "${key[Alt-Right]}" forward-word
	bindkey -M vicmd "${key[Alt-Right]}" forward-word
fi

# Ctrl-Backspace / Ctrl-Delete delete a word; Ctrl-Z toggles the job back
bindkey -M emacs '^H' backward-kill-word
bindkey -M emacs '^[[3;5~' kill-word
fancy-ctrl-z() { if [[ $#BUFFER -eq 0 ]]; then BUFFER=fg; zle accept-line; else zle push-input; fi }
zle -N fancy-ctrl-z
bindkey -M emacs '^Z' fancy-ctrl-z
# Alt-S: prefix the line with sudo
sudo-command-line() { [[ -z $BUFFER ]] && zle up-history; [[ $BUFFER == sudo\ * ]] || BUFFER="sudo $BUFFER"; zle end-of-line }
zle -N sudo-command-line
bindkey -M emacs '\es' sudo-command-line

## ShaniOS defaults: aliases, fzf, starship, zoxide, mcfly
# (inside a Distrobox container $HOME is shared but /usr isn't: use the host's)
for _f in /usr/share/shani/shell/common.sh /run/host/usr/share/shani/shell/common.sh; do
  [[ -r $_f ]] && { source $_f; break; }
done
unset _f

## Plugins: fish-like suggestions and highlighting (keep these last)
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=200
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)   # also colour matching brackets
# (plugin files come from the host too when inside Distrobox; any that
# aren't found are skipped rather than erroring)
_zp() { local d; for d in /usr/share/zsh/plugins /run/host/usr/share/zsh/plugins; do
  [[ -r $d/$1/$1.zsh ]] && { source $d/$1/$1.zsh; return 0; }; done; return 1; }
_zp zsh-autosuggestions
_zp zsh-syntax-highlighting
# substring search must load after syntax highlighting
_zp zsh-history-substring-search
HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_FOUND='bg=#ff7f50,fg=#252434,bold'   # accent (DecorationFocus)
HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_NOT_FOUND='bg=#ef4136,fg=#ffffff,bold'
HISTORY_SUBSTRING_SEARCH_ENSURE_UNIQUE=1
# Up/Down: search history for any part of what's typed
(( $+widgets[history-substring-search-up] )) && for _km in emacs viins; do
  bindkey -M $_km '^[[A' history-substring-search-up
  bindkey -M $_km '^[[B' history-substring-search-down
  [[ -n "${terminfo[kcuu1]}" ]] && bindkey -M $_km "${terminfo[kcuu1]}" history-substring-search-up
  [[ -n "${terminfo[kcud1]}" ]] && bindkey -M $_km "${terminfo[kcud1]}" history-substring-search-down
done
unset _km; unfunction _zp

## Your own additions below
