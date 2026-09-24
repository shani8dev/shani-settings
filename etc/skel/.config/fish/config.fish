# ~/.config/fish/config.fish - ShaniOS

# fish-compatible bits of ~/.profile can go in ~/.fish_profile
test -f ~/.fish_profile; and source ~/.fish_profile

# ShaniOS defaults: colours, aliases, fzf, starship, zoxide, mcfly
# (inside a Distrobox container $HOME is shared but /usr isn't: use the host's)
for f in /usr/share/shani/shell/shani.fish /run/host/usr/share/shani/shell/shani.fish
    if test -r $f
        source $f
        break
    end
end

# Your own additions below
