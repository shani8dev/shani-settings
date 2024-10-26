#!/bin/sh
dconf load / < ~/.config/shani-dconf.ini
rm -f ~/.config/shani-dconf.ini ~/.config/autostart-scripts/dconf.sh &
 
notify-send "GNOME settings applied! 🔥"
