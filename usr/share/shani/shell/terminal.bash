# ShaniOS terminal integration for bash, sourced by common.sh (see
# terminal.zsh for what each escape gives you): OSC 7, the current folder;
# OSC 133, where prompts and output start; the folder as the window title.

# OSC 7: the folder as a file:// URL, every byte outside the safe set %-encoded
_shani_osc7() {
    local LC_ALL=C p=$PWD out= c i
    for (( i = 0; i < ${#p}; i++ )); do
        c=${p:i:1}
        case $c in
            [-/:_.~[:alnum:]]) out+=$c ;;
            *) printf -v c '%%%02X' "'$c"; out+=$c ;;
        esac
    done
    printf '\e]7;file://%s%s\e\\' "${HOSTNAME:-localhost}" "$out"
}
# before every prompt: the last command ended (133 D), the folder, the title,
# and a prompt starts (133 A); PS0 marks where the command's output starts
_shani_prompt() {
    printf '\e]133;D\e\\'
    _shani_osc7
    printf '\e]2;%s\a' "${PWD/#$HOME/\~}"
    printf '\e]133;A\e\\'
}
# after starship's own hook (common.sh sources this last), whichever form
# PROMPT_COMMAND has: an array (bash 5.1+) or a string
if [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" == "declare -a"* ]]; then
    PROMPT_COMMAND+=(_shani_prompt)
else
    PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }_shani_prompt"
fi
PS0+=$'\e]133;C\e\\'
