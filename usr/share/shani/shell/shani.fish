# ShaniOS interactive fish defaults (fish twin of common.sh).
# Sourced from ~/.config/fish/config.fish; lives in /usr so fixes reach
# existing users on upgrade. Delete the `source` line there to opt out.
status is-interactive; or return

# Greeting: fastfetch in every new terminal big enough for it, as most
# desktop distros do.
# Off: `touch ~/.config/shani/no-fastfetch` or `set -Ux SHANI_FASTFETCH 0`.
function fish_greeting
    test "$SHANI_FASTFETCH" = 0; and return
    test -e (set -q XDG_CONFIG_HOME; and echo $XDG_CONFIG_HOME; or echo ~/.config)/shani/no-fastfetch; and return
    # too small to hold it (split pane, drop-down): skip, don't clip
    test "$LINES" -ge 20 -a "$COLUMNS" -ge 105 2>/dev/null; or return
    test -t 1; and type -q fastfetch; and fastfetch
end
set -gx VIRTUAL_ENV_DISABLE_PROMPT 1

# Package managers ShaniOS supports beside pacman (docs: software/). fish
# never reads /etc/profile.d, so Nix/Snap/Flatpak/Homebrew paths are set here.
test -r /etc/profile.d/nix-daemon.fish; and source /etc/profile.d/nix-daemon.fish   # guards itself
for d in /var/lib/snapd/snap/bin ~/.local/share/flatpak/exports/bin /var/lib/flatpak/exports/bin
    test -d $d; and fish_add_path --global --append $d
end
if not set -q HOMEBREW_PREFIX; and test -x /home/linuxbrew/.linuxbrew/bin/brew
    /home/linuxbrew/.linuxbrew/bin/brew shellenv fish | source
end
fish_add_path --global --move ~/.local/bin 2>/dev/null
set -gx LESS '-R -F -i -M --mouse --wheel-lines=3'

# Syntax colours as ANSI slots: the shipped Saturn / Saturn Dark Konsole
# schemes define them, so they stay readable in both light and dark.
set -g fish_color_command red
set -g fish_color_keyword yellow
set -g fish_color_quote green
set -g fish_color_param normal
set -g fish_color_option cyan
set -g fish_color_redirection magenta
set -g fish_color_end yellow
set -g fish_color_error brred --underline
set -g fish_color_comment brblack
set -g fish_color_autosuggestion brblack
set -g fish_color_operator magenta
set -g fish_color_escape cyan
set -g fish_color_search_match --background=brblack
set -g fish_pager_color_prefix red --bold
set -g fish_pager_color_progress brblack
set -g fish_pager_color_description brblack

if type -q bat
    set -gx MANPAGER "sh -c 'col -bx | bat -l man -p'"
    set -gx MANROFFOPT -c
    alias cat 'bat --paging=never --style=plain'
end

if type -q eza
    alias ls 'eza --group-directories-first --icons=auto'
    alias ll 'eza -l --group-directories-first --icons=auto --git --time-style=relative'
    alias la 'eza -la --group-directories-first --icons=auto --git --time-style=relative'
    alias lt 'eza --tree --level=2 --icons=auto --git-ignore'
end

alias grep 'grep --color=auto'
alias diff 'diff --color=auto'
alias ip 'ip -color'
alias dir 'dir --color=auto'
alias vdir 'vdir --color=auto'
alias cp 'cp -i'
alias mv 'mv -i'
alias ln 'ln -i'
alias mkdir 'mkdir -p'
alias free 'free -h'
alias df 'df -h'

# abbreviations expand in place, so history shows the real command
abbr -a .. 'cd ..'
abbr -a ... 'cd ../..'
abbr -a .... 'cd ../../..'
abbr -a tarnow 'tar -acf'
abbr -a untar 'tar -xvf'
abbr -a psmem 'ps auxf | sort -nr -k 4'
abbr -a psmem10 'ps auxf | sort -nr -k 4 | head -10'
abbr -a hw 'inxi -Fxz'
abbr -a jctl 'journalctl -p 3 -xb'
abbr -a sctl 'systemctl --failed; systemctl --user --failed'
abbr -a ports 'ss -tulpn'
abbr -a myip 'curl -fsS https://ifconfig.co'
abbr -a !! --position anywhere --function __shani_last_history_item

function __shani_last_history_item
    echo $history[1]
end

function mkcd --description 'mkdir -p and cd into it'
    mkdir -p -- $argv[1]; and cd -- $argv[1]
end

function backup --argument-names filename --description 'timestamped copy'
    cp -a -- $filename $filename.bak.(date +%Y%m%d-%H%M%S)
end

function history --description 'history with timestamps'
    builtin history --show-time='%F %T ' $argv
end

if type -q fzf
    if type -q fd
        set -gx FZF_DEFAULT_COMMAND 'fd --type f --hidden --follow --exclude .git'
        set -gx FZF_CTRL_T_COMMAND $FZF_DEFAULT_COMMAND
        set -gx FZF_ALT_C_COMMAND 'fd --type d --hidden --follow --exclude .git'
    end
    set -gx FZF_DEFAULT_OPTS '--height=40% --layout=reverse --border=rounded --info=inline-right --color=fg:-1,bg:-1,hl:1,fg+:-1,bg+:-1,hl+:1,info:3,prompt:1,pointer:1,marker:2,spinner:3,header:8,border:8'
    type -q bat; and set -gx FZF_CTRL_T_OPTS "--preview 'bat --color=always --style=numbers --line-range=:200 {}'"
    type -q eza; and set -gx FZF_ALT_C_OPTS "--preview 'eza --tree --level=2 --color=always --icons=always {}'"
    fzf --fish | source          # Ctrl-T, Alt-C
end

type -q starship; and starship init fish --print-full-init | source
type -q zoxide; and zoxide init fish | source          # z <dir>, zi
if type -q mcfly
    set -gx MCFLY_FUZZY 2
    set -gx MCFLY_RESULTS 25
    set -gx MCFLY_INTERFACE_VIEW BOTTOM
    set -gx MCFLY_RESULTS_SORT LAST_RUN
    set -gx MCFLY_PROMPT '❯'
    # mcfly's own vendor_conf.d file already initialised it and bound Ctrl-R;
    # `fzf --fish` above re-bound Ctrl-R to fzf, so hand it back to McFly
    functions -q mcfly_key_bindings; and mcfly_key_bindings
end
