# Security Policy

## Trust Model

`shani-settings` is a filesystem overlay of `/etc` and `/usr` shipped verbatim
on every Shanios image (packaged by `shani-pkgbuilds/shani-settings`). There is
no build step — a path here (`etc/samba/smb.conf`) lands at that exact path on
every real install. A wrong default here isn't a bug in one place; it's a
default for the entire fleet on day one.

## Key Security Mechanisms

| Mechanism | Implementation |
|-----------|----------------|
| Config validation | Each service's own validator: `testparm`, `visudo -c`, `systemd-analyze verify`, `udevadm verify` |
| Guest access | `usershare allow guests = no` in `etc/samba/smb.conf` |
| File permissions | Config files shipped with restrictive permissions |

## Known Limitations

- **`map to guest = Bad Password`.** `etc/samba/smb.conf` still maps failed auth to guest access, widening the attack surface on authentication failure.
- **World-writable sysfs.** `usr/lib/udev/rules.d/60-openrgb.rules` uses `chmod a+w` on sysfs files (world-writable kernel interfaces).
- **World-writable USB device.** `usr/lib/udev/rules.d/99-fanatec-wheel-perms.rules` sets `MODE="0666"` on a USB input device.
- **`SigLevel = Never` for non-server profiles.** `shani-install-media`'s
  `image_profiles/{kiosk,gnome,plasma}/pacman.conf` disables pacman package
  signature verification for those profile builds (cosmic and server use
  `SigLevel = Required DatabaseOptional`).
- **No automated drift check.** `shani-pkgbuilds/shani-settings/PKGBUILD` checksums must be manually bumped when this repo's content changes.

## Reporting a Vulnerability

If you discover a security vulnerability in any Shanios project, please report it
responsibly by opening a private security advisory on GitHub.

Please include:
- A description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We will acknowledge receipt within 72 hours and provide a detailed response
within 7 days. Thank you for helping keep Shanios secure.
