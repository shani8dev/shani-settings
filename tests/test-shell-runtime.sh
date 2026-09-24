#!/usr/bin/env bash
#
# test-shell-runtime.sh - load every shipped shell/CLI config in the real
# program and fail on any error it reports. Static syntax checks (zsh -n,
# fish -n) miss the things that actually break a new user's first terminal:
# a plugin sourced in the wrong order, an alias for a tool that isn't
# installed, a tmux option that doesn't exist, a nanorc include that
# matches nothing.
#
# Installs this repo's usr/share/shani,
# etc/tmux.conf, etc/gitconfig, etc/xdg/fastfetch and etc/environment.d into / - so run it ONLY in a disposable
# Arch container that has shani-settings' dependencies (and the
# shani-tools/-tools-extra ones: tmux vim nano
# tealdeer man-db man-pages) installed:
#
#   SHANI_TEST_DISPOSABLE=1 bash tests/test-shell-runtime.sh [repo-root]
set -uo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
[[ "${SHANI_TEST_DISPOSABLE:-}" == 1 ]] || { echo "refusing: writes to /; set SHANI_TEST_DISPOSABLE=1 in a throwaway container" >&2; exit 2; }
[[ $EUID -eq 0 ]] || { echo "must run as root (installs into /)" >&2; exit 2; }

FAILS=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; FAILS=$((FAILS + 1)); }
# error-looking output from a program that should have loaded cleanly
ERR_RE='command not found|not found|[Nn]o such file|[Ee]rror|unknown option|invalid|unrecognized|parse|bad pattern|deprecated|warning|\(eval\)|E[0-9]{2,4}:'

mkdir -p /usr/share/shani /etc/xdg/fastfetch
cp -rT "$REPO_ROOT/usr/share/shani" /usr/share/shani
install -Dm644 "$REPO_ROOT/etc/xdg/fastfetch/config.jsonc" /etc/xdg/fastfetch/config.jsonc
install -Dm644 "$REPO_ROOT/etc/environment.d/90-shani.conf" /etc/environment.d/90-shani.conf
install -Dm644 "$REPO_ROOT/etc/tmux.conf" /etc/tmux.conf
install -Dm644 "$REPO_ROOT/etc/gitconfig" /etc/gitconfig

id shtest >/dev/null 2>&1 || useradd -M -d /tmp/shtest-home -s /bin/zsh shtest
H=/tmp/shtest-home
rm -rf "$H"; cp -a "$REPO_ROOT/etc/skel" "$H"
mv "$H/.bashrc_shani" "$H/.bashrc"        # what bashrc-setup.desktop does
chown -R shtest: "$H"

# run as the test user, interactively, in a real pty
as_user() { runuser -u shtest -- env -i HOME="$H" USER=shtest LOGNAME=shtest \
    PATH=/usr/local/bin:/usr/bin TERM=xterm-256color LANG=C.UTF-8 "$@"; }
in_pty()  { as_user script -qefc "stty rows ${SHANI_PTY_SIZE%% *} cols ${SHANI_PTY_SIZE##* } 2>/dev/null; $1" /dev/null 2>&1 | tr -d '\r'; }
SHANI_PTY_SIZE="40 120"

check_shell() {  # name, command, expected-marker
    local out; out=$(in_pty "$2")
    if ! grep -q "$3" <<<"$out"; then fail "$1: did not finish (no '$3'):"$'\n'"$out"; return; fi
    local bad; bad=$(grep -E "$ERR_RE" <<<"$out" | grep -v "$3")
    if [[ -n "$bad" ]]; then fail "$1 printed errors:"$'\n'"$bad"; else pass "$1 starts clean"; fi
}

## Shells: start interactive, exercise what the config sets up
check_shell zsh  "zsh -i -c 'alias ls cat df du; whence -w z zi mkcd; bindkey \"^[[A\" | grep -q substring-search && bindkey \"^R\" | grep -q mcfly && print ZSH_OK'" ZSH_OK
check_shell bash "bash -i -c 'alias ls cat >/dev/null && type z mkcd >/dev/null && bind -X | grep -q mcfly && echo BASH_OK'" BASH_OK
check_shell fish "fish -i -c 'functions -q z mkcd fish_prompt; and alias | grep -q \"eza\"; and abbr -q jctl; and echo FISH_OK'" FISH_OK
# a second zsh start must also be clean (compinit cache, history file present)
check_shell zsh-warm "zsh -i -c 'print ZSH_WARM'" ZSH_WARM

## man through the bat MANPAGER (the old fish config pointed at a missing bat)
# (minimal Arch containers NoExtract usr/share/man; skip rather than lie)
if [[ -e /usr/share/man/man1/ls.1.gz ]]; then
    out=$(in_pty "zsh -i -c 'man ls | head -3; print MAN_OK'")
    if grep -q MAN_OK <<<"$out" && grep -q "LS" <<<"$out" && ! grep -Eq "$ERR_RE" <<<"$out"; then pass "man ls via bat MANPAGER"; else fail "man via MANPAGER: $out"; fi
else
    echo "SKIP: man pages not extracted in this container"
fi

## tmux: every option/binding in /etc/tmux.conf must be accepted
sock="shtest$$"
as_user tmux -L "$sock" -f /dev/null new-session -d -s t
out=$(as_user tmux -L "$sock" source-file /etc/tmux.conf 2>&1); rc=$?
as_user tmux -L "$sock" kill-server 2>/dev/null
if [[ $rc -eq 0 && -z "$out" ]]; then pass "tmux accepts /etc/tmux.conf"; else fail "tmux: rc=$rc $out"; fi

## nano: rc errors are printed at startup, before the editor draws
out=$(in_pty "timeout 3 nano /tmp/shtest-nano.txt")
if grep -Eq "Error in|No such|not found|Unknown" <<<"$out"; then fail "nanorc: $(grep -E 'Error in|No such|not found|Unknown' <<<"$out" | head -5)"; else pass "nano loads ~/.config/nano/nanorc"; fi

## vim: :messages after loading ~/.vimrc must hold no E-numbers
as_user vim -N -es -u "$H/.vimrc" '+redir! > /tmp/shtest-vim.txt' '+silent messages' '+redir END' '+qa!' </dev/null
if grep -Eq 'E[0-9]+:' /tmp/shtest-vim.txt; then fail "vimrc: $(cat /tmp/shtest-vim.txt)"; else pass "vim loads ~/.vimrc"; fi

## git: system config parses, delta is a working pager
repo=$(as_user mktemp -d)
as_user git -C "$repo" init -q && printf 'a\n' | as_user tee "$repo/f" >/dev/null && as_user git -C "$repo" add f \
  && as_user git -C "$repo" -c user.name=t -c user.email=t@t commit -qm init && printf 'b\n' | as_user tee "$repo/f" >/dev/null
out=$(in_pty "git -C $repo --paginate diff"); rc=$?
if [[ $rc -eq 0 ]] && grep -q "f" <<<"$out" && ! grep -Eq "$ERR_RE" <<<"$out"; then pass "git diff through delta"; else fail "git/delta rc=$rc: $out"; fi
[[ "$(git config --system core.pager)" == delta ]] || fail "git --system core.pager is not delta"

## starship: config loads with no warnings
out=$(as_user env STARSHIP_LOG=warn starship prompt 2>&1 >/dev/null)
if [[ -z "$out" ]]; then pass "starship.toml loads without warnings"; else fail "starship: $out"; fi

## bat / tealdeer: invalid config options make them exit non-zero
if as_user bat -pp "$H/.zshrc" >/dev/null 2>&1; then pass "bat config"; else fail "bat config: $(as_user bat -pp "$H/.zshrc" 2>&1 | head -3)"; fi
if as_user tldr --show-paths >/dev/null 2>&1; then pass "tealdeer config"; else fail "tealdeer config: $(as_user tldr --show-paths 2>&1 | head -3)"; fi


## fastfetch greeting: shown in a new terminal, gone after the opt-out file
for sh in zsh bash fish; do
    rm -f "$H/.config/shani/no-fastfetch"
    # fish greets only a real interactive session (not -c): type into it
    start() { if [[ $sh == fish ]]; then printf 'echo GREET_DONE\nexit\n' | as_user script -qefc "stty rows ${SHANI_PTY_SIZE%% *} cols ${SHANI_PTY_SIZE##* }; fish -i" /dev/null 2>&1 | tr -d '\r'; else in_pty "$sh -i -c 'echo GREET_DONE'"; fi; }
    on=$(start)
    as_user mkdir -p "$H/.config/shani"; as_user touch "$H/.config/shani/no-fastfetch"
    off=$(start)
    piped=$(as_user script -qefc "$sh -i -c 'echo GREET_DONE' | cat" /dev/null 2>&1)
    rm -f "$H/.config/shani/no-fastfetch"
    small=$(SHANI_PTY_SIZE="12 60" start)
    if grep -q 'hani' <<<"$on" && ! grep -q 'hani' <<<"$off" && grep -q GREET_DONE <<<"$off" \
       && ! grep -q 'hani' <<<"$small" && grep -q GREET_DONE <<<"$small"; then
        pass "$sh: fastfetch greeting shown; skipped when opted out or too small"
    else fail "$sh greeting: on=$(grep -c hani <<<"$on") off=$(grep -c hani <<<"$off") small=$(grep -c hani <<<"$small")"; fi
done

## Ctrl-R is McFly in every shell (fish: fzf used to take it over)
out=$(printf 'bind ctrl-r\nexit\n' | as_user script -qefc "fish -i" /dev/null 2>&1 | tr -d '\r' | sed 's/\x1b\[[0-9;]*m//g')
grep -q '__mcfly-history-widget' <<<"$out" && ! grep -q 'bind ctrl-r fzf-history' <<<"$out" \
    && pass "fish: Ctrl-R is McFly" || fail "fish Ctrl-R: $(grep 'ctrl-r' <<<"$out")"

## Nix (pre-installed) on PATH in NON-login shells - Konsole starts fish
## non-login, and fish never reads /etc/profile.d
if [[ -r /etc/profile.d/nix-daemon.sh ]]; then
    # a user who has installed something with nix-env (fish_add_path, used by
    # nix-daemon.fish, skips directories that don't exist yet)
    as_user mkdir -p "$H/.nix-profile/bin"
    for sh in zsh bash; do
        out=$(in_pty "$sh -i -c 'echo \"P=\$PATH\"'")
        grep -q '\.nix-profile/bin' <<<"$out" && pass "$sh: nix profile on PATH" || fail "$sh: no nix on PATH: $(grep P= <<<"$out")"
    done
    out=$(printf 'echo "P=$PATH"\nexit\n' | as_user script -qefc "fish -i" /dev/null 2>&1 | tr -d '\r')
    grep -q '\.nix-profile/bin' <<<"$out" && pass "fish: nix profile on PATH" || fail "fish: no nix on PATH"
    rm -rf "$H/.nix-profile"
else
    echo "SKIP: nix not installed here"
fi

## readline: ~/.inputrc is read (bash shows the variable it sets)
out=$(in_pty "bash -i -c 'bind -v | grep -q \"completion-ignore-case on\" && echo RL_OK'")
grep -q RL_OK <<<"$out" && pass "~/.inputrc applied" || fail "inputrc not applied: $out"

## eza: a bad theme.yml is ignored silently, so check the colour itself
# (directories are Purple = SGR 35 in theme.yml; eza's own default is blue 34)
out=$(as_user eza -ld --color=always /etc)
grep -q '1;35m' <<<"$out" && pass "eza uses the ShaniOS theme" || fail "eza theme not applied: $(cat -v <<<"$out")"

## fastfetch: the /etc/xdg config and the ShaniOS logo file both load
out=$(in_pty "fastfetch --pipe false")
if grep -q 'hani' <<<"$out" && grep -q 'Packages' <<<"$out" && ! grep -Eqi 'error|failed|invalid' <<<"$out"; then
    pass "fastfetch: ShaniOS logo + config"
else fail "fastfetch: $(sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' <<<"$out" | head -20)"; fi

## micro: an unknown colorscheme/option is reported on the status line
out=$(in_pty "timeout 3 micro /tmp/shtest-micro.txt")
bad=$(sed 's/ft:unknown//g' <<<"$out" | grep -Eio '.{0,40}(not found|error|invalid|unknown).{0,40}' | head -3)
if [[ -n "$bad" ]]; then fail "micro: $bad"
elif ! grep -q $'\e\\[7m' <<<"$out"; then fail "micro: saturn colorscheme not applied (no reverse-video status line)"
else pass "micro loads settings + saturn colorscheme"; fi

## environment.d: what systemd would put in the session
gen=/usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator
if [[ -x $gen ]]; then
    out=$(as_user "$gen" 2>&1)
    grep -qx 'EDITOR=micro' <<<"$out" && grep -qx 'VISUAL=micro' <<<"$out" && pass "environment.d exports EDITOR/VISUAL" || fail "environment.d: $out"
fi

echo
if [[ $FAILS -eq 0 ]]; then echo "All shell runtime checks passed"; exit 0; fi
echo "$FAILS shell runtime check(s) failed"; exit 1
