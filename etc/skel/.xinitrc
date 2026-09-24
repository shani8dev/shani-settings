#!/bin/sh
#
# ~/.xinitrc - run by `startx`. ShaniOS normally starts the desktop from
# its login manager; this is the fallback for an X session from a tty.

if [ -d /etc/X11/xinit/xinitrc.d ]; then
    for f in /etc/X11/xinit/xinitrc.d/?*.sh; do
        [ -x "$f" ] && . "$f"
    done
    unset f
fi
[ -f "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"

export XDG_SESSION_TYPE=x11
# Start whichever desktop this ShaniOS edition ships
if command -v startplasma-x11 >/dev/null; then
    exec startplasma-x11
elif command -v gnome-session >/dev/null; then
    export GDK_BACKEND=x11
    exec gnome-session
elif command -v start-cosmic >/dev/null; then
    exec start-cosmic
else
    echo "xinitrc: no known desktop session found" >&2
    exit 1
fi
