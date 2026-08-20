# shani-settings

Default system configuration for Shani OS — a filesystem overlay of `/etc` and `/usr` files that ship on every image. This repo has no build step of its own: its `etc/` and `usr/` trees are packaged verbatim by [`shani-pkgbuilds/shani-settings`](https://github.com/shani8dev/shani-pkgbuilds/tree/main/shani-settings), whose `PKGBUILD` copies them straight onto the package root, so a path here (e.g. `etc/samba/smb.conf`) lands at that same path on the live system (`/etc/samba/smb.conf`) when the package installs or upgrades.

## What's in here

| Path | Purpose |
|---|---|
| `usr/share/polkit-1/rules.d/99-shani.rules` | Desktop authorization policy — see [Polkit trust model](#polkit-trust-model) below |
| `etc/sudoers.d/` | `wheel` group sudo access, plus editor/insults/pwfeedback sudo behavior tweaks |
| `usr/lib/sysctl.d/` | Kernel hardening (`90-security-hardening.conf`, Lynis-driven), plus network and scheduler tuning |
| `etc/audit/rules.d/` | `auditd` watch rules for privilege escalation, auth files, and module loading |
| `usr/lib/modprobe.d/` | Module blacklists (firewire, unused protocols) and minor device tweaks (nobeep, noime) |
| `usr/lib/udev/rules.d/` | Device permission rules — game controllers/wheels, HPET/RTC access |
| `etc/samba/smb.conf`, `usr/lib/tmpfiles.d/sambashare.conf` | Local file sharing (home dirs, printers, ad-hoc usershares) |
| `etc/fail2ban/jail.local` | Local login/service brute-force protection |
| `usr/lib/systemd/*.conf.d/`, `usr/lib/systemd/zram-generator.conf` | systemd resource limits, timeouts, and zram config |
| `etc/skel/` | Default files copied into every new user's home directory |

## Deployment

Nothing in this repo runs on its own — it's data, applied through the package system:

1. `shani-pkgbuilds/shani-settings/PKGBUILD` tars this repo's `etc/` and `usr/` directories and packages them as `shani-settings`.
2. Install/upgrade of that package overlays the files onto the live root (Pacman handles conflicts with `backup=()`-listed files the usual way).
3. `shani-settings.install`'s `post_install`/`post_upgrade` hooks enable the services these files assume exist (`systemd-oomd`, `irqbalance`, `ananicy-cpp`, the `btrfs-*` maintenance timers, …) and provision the `sambashare` group.

Permissions that git can't preserve (sudoers.d at `0440`, polkit rules.d at `0750`/`root:polkitd`, `~/.ssh` and `~/.gnupg` under `skel/` at `0700`) are fixed up explicitly in that `PKGBUILD`, not stored as file mode in this repo.

## Polkit trust model

`99-shani.rules` implements a deliberate two-tier authorization policy, documented in full in the file's own header comment:

- **Tier 1 — any active local session, no group required.** Covers full desktop functionality (package management, firmware updates, Flatpak, Snap, OS updates) so a system with no `wheel` group provisioned still gives every local user a complete desktop. Most actions require the user's own password (`AUTH_SELF`); routine actions (power, mount, network) are passwordless.
- **Tier 2 — `wheel` group + active local session.** Destructive or system-structural operations only, gated by `AUTH_SELF` (disk formatting, hostname changes) or `AUTH_ADMIN` for anything irreversible.

The tradeoff behind Tier 1 is explicit in the rules themselves: it weighs the convenience of a group-optional desktop against the risk that a compromised (but non-wheel) local account can still reach real system actions, and accepts that risk deliberately rather than by omission. If you're changing what a given action requires, read the relevant rule's inline comment first — the tiering is intentional, not uniform by accident.
