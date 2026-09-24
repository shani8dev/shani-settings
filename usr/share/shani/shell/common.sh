# ShaniOS interactive shell defaults, shared by bash and zsh.
#
# Sourced from ~/.bashrc and ~/.zshrc (both come from /etc/skel). It lives
# in /usr so fixes reach existing users on package upgrade; to opt out,
# delete the `source` line from your rc file. Everything is guarded with
# `command -v`, so a profile without a given tool (or a Distrobox container,
# which shares $HOME and loads this from /run/host) just skips it.

case $- in *i*) ;; *) return 0 2>/dev/null || exit 0 ;; esac

if [ -n "${ZSH_VERSION-}" ]; then _shani_sh=zsh; else _shani_sh=bash; fi

## Package managers ShaniOS supports beside pacman (docs: software/).
## Login shells get these from /etc/profile.d, but terminals usually start
## non-login shells, so make sure they're set up here too.
[ -r /etc/profile.d/nix-daemon.sh ] && . /etc/profile.d/nix-daemon.sh      # guards itself
for _shani_d in /var/lib/snapd/snap/bin "$HOME/.local/share/flatpak/exports/bin" /var/lib/flatpak/exports/bin; do
    [ -d "$_shani_d" ] && case ":$PATH:" in *":$_shani_d:"*) ;; *) PATH="$PATH:$_shani_d" ;; esac
done
unset _shani_d
# Homebrew is optional (not pre-installed); pick it up once it's installed
if [ -z "${HOMEBREW_PREFIX-}" ] && [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

## Environment (~/.local/bin first: distrobox-export --bin and user tools)
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) [ -d "$HOME/.local/bin" ] && PATH="$HOME/.local/bin:$PATH" ;; esac
export PATH
export LESS='-R -F -i -M --mouse --wheel-lines=3'
export LESSHISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/lesshst"

if command -v bat >/dev/null; then
    # man pages with syntax colours; -p = no line numbers/grid
    export MANPAGER="sh -c 'col -bx | bat -l man -p'"
    export MANROFFOPT='-c'
    alias cat='bat --paging=never --style=plain'
fi

## Listing (eza: git status, icons via the Nerd symbols font)
if command -v eza >/dev/null; then
    alias ls='eza --group-directories-first --icons=auto'
    alias ll='eza -l --group-directories-first --icons=auto --git --time-style=relative'
    alias la='eza -la --group-directories-first --icons=auto --git --time-style=relative'
    alias lt='eza --tree --level=2 --icons=auto --git-ignore'
    alias l.='eza -d .* --icons=auto'
else
    alias ls='ls --color=auto'
    alias ll='ls -lh'
    alias la='ls -lAh'
fi

## Colour and safety
alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias ip='ip -color'
alias dir='dir --color=auto'
alias vdir='vdir --color=auto'
alias cp='cp -i'
alias mv='mv -i'
alias ln='ln -i'
alias mkdir='mkdir -p'
alias df='df -h'
alias free='free -h'

## Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ......='cd ../../../../..'

## Everyday helpers
alias tarnow='tar -acf '
alias untar='tar -xvf '        # tar auto-detects gz/xz/zst/bz2
alias wget='wget -c '
alias psmem='ps auxf | sort -nr -k 4'
alias psmem10='ps auxf | sort -nr -k 4 | head -10'
alias hw='inxi -Fxz'                        # hardware summary, serials masked
alias jctl='journalctl -p 3 -xb'            # this boot's errors
alias sctl='systemctl --failed; systemctl --user --failed'
alias ports='ss -tulpn'
alias myip='curl -fsS https://ifconfig.co'

mkcd() { mkdir -p -- "$1" && cd -- "$1"; }
backup() { cp -a -- "$1" "$1.bak.$(date +%Y%m%d-%H%M%S)"; }

## fzf: fd for file lists, bat/eza previews, theme colours
if command -v fzf >/dev/null; then
    if command -v fd >/dev/null; then
        export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
        export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
    fi
    # ANSI slots (hl:1 = red ...): the shipped Konsole schemes define them
    export FZF_DEFAULT_OPTS='--height=40% --layout=reverse --border=rounded --info=inline-right
 --color=fg:-1,bg:-1,hl:1,fg+:-1,bg+:-1,hl+:1,info:3
 --color=prompt:1,pointer:1,marker:2,spinner:3,header:8,border:8'
    command -v bat >/dev/null && export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:200 {}'"
    command -v eza >/dev/null && export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --color=always --icons=always {}'"
    # Ctrl-T files, Alt-C cd, ** completion. Ctrl-R is left to mcfly below.
    eval "$(fzf --"$_shani_sh")"
fi

## Greeting: fastfetch in every new terminal, as most desktop distros do.
## Skipped in terminals too small to hold it (split panes, drop-downs),
## where it would only print a clipped fragment. Turn it off with
## `touch ~/.config/shani/no-fastfetch`, or `export SHANI_FASTFETCH=0`
## above the source line in your rc file.
if [ "${SHANI_FASTFETCH:-1}" != 0 ] && [ -t 1 ] && [ "${TERM:-dumb}" != dumb ] \
   && [ ! -e "${XDG_CONFIG_HOME:-$HOME/.config}/shani/no-fastfetch" ] \
   && command -v fastfetch >/dev/null; then
    _shani_size=$(stty size 2>/dev/null)
    if [ "${_shani_size% *}" -ge 20 ] 2>/dev/null && [ "${_shani_size#* }" -ge 105 ] 2>/dev/null; then
        fastfetch
    fi
    unset _shani_size
fi

## Prompt, smarter cd, history search
command -v starship >/dev/null && eval "$(starship init "$_shani_sh" --print-full-init)"
if command -v zoxide >/dev/null; then
    eval "$(zoxide init "$_shani_sh")"          # z <dir>, zi = interactive
fi
if command -v mcfly >/dev/null; then
    export MCFLY_FUZZY=2
    export MCFLY_RESULTS=25
    export MCFLY_INTERFACE_VIEW=BOTTOM
    export MCFLY_RESULTS_SORT=LAST_RUN
    export MCFLY_PROMPT='❯'
    eval "$(mcfly init "$_shani_sh")"             # Ctrl-R
fi

unset _shani_sh
