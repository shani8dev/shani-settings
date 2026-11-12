# ShaniOS terminal integration for zsh, sourced by common.sh.
#
# Modern terminals (foot, kitty, ghostty, WezTerm, Konsole, GNOME Console)
# understand three things a shell can tell them, and none happens on its own:
#   - OSC 7, the current folder: a new window or tab opens where you are
#     (foot: Ctrl+Shift+N)
#   - OSC 133, where each prompt and each command's output starts and ends:
#     jump between prompts (foot: Ctrl+Shift+Z / Ctrl+Shift+X) and select or
#     pipe the last command's output
#   - the title: the folder while idle, the command while one runs - what
#     the bar, the dock and Alt+Tab show for the window
# Escapes go straight to the terminal; one that does not know them ignores them.

autoload -Uz add-zsh-hook

# OSC 7: the folder as a file:// URL, every byte outside the safe set %-encoded
_shani_osc7() {
    emulate -L zsh
    setopt extendedglob
    local LC_ALL=C
    (( ZSH_SUBSHELL )) || printf '\e]7;file://%s%s\e\\' "$HOST" "${PWD//(#m)([^@-Za-z&-;_~])/%${(l:2::0:)$(([##16]#MATCH))}}"
}
add-zsh-hook chpwd _shani_osc7
_shani_osc7

# the title: "~/Projects/site" while idle, "nvim index.html" while it runs
_shani_title_idle() { print -Pn '\e]2;%~\a' }
_shani_title_cmd()  { emulate -L zsh; local c=${1//[[:cntrl:]]/ }; print -rn -- $'\e]2;'"${c[1,80]}"$'\a' }
add-zsh-hook precmd _shani_title_idle
add-zsh-hook preexec _shani_title_cmd

# OSC 133: D (the last command ended) then A (a prompt starts) before every
# prompt; C (output starts) when a command runs. Starship marks prompts itself
# in some versions - then it is left to it, and these only mark the output.
_shani_133_precmd()  { print -n '\e]133;D\e\\'; [[ -n ${_shani_133_prompt-} ]] && print -n '\e]133;A\e\\' }
_shani_133_preexec() { print -n '\e]133;C\e\\' }
(( $+functions[starship_precmd] )) && [[ "$(typeset -f starship_precmd prompt_starship_precmd 2>/dev/null)" == *133\;* ]] || _shani_133_prompt=1
add-zsh-hook precmd _shani_133_precmd
add-zsh-hook preexec _shani_133_preexec
