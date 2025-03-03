# If it's a Wayland session, set some environment variables.
if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
    export QT_QPA_PLATFORM=wayland
    export GDK_BACKEND=wayland
    export MOZ_ENABLE_WAYLAND=1
fi

export QT_AUTO_SCREEN_SCALE_FACTOR=1
export QT_STYLE_OVERRIDE=gtk

