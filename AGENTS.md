# Agent instructions — shani-settings

This file applies to any AI coding assistant working in this repository
(Claude Code, opencode, Kilo Code, Cursor, Aider, or similar). Read this
before editing, and follow the verification steps before calling any change
done.

## What this repo is

A filesystem overlay of `/etc` and `/usr` shipped verbatim on every Shanios
image (packaged by `shani-pkgbuilds/shani-settings`). There's no build
step of its own — a path here (`etc/samba/smb.conf`) lands at that exact
path on every real install. A wrong default here isn't a bug in one
place, it's a default for the entire fleet on day one.

## Rule: syntax-check every config with its own real validator, don't eyeball it

A config file that "reads fine" and one that a real daemon will actually
load without error are different claims — this repo ships services
(Samba, polkit rules, udev rules, systemd units) whose config syntax is
easy to get subtly wrong (indentation-sensitive stanzas, deprecated
directives, boolean spelling). Use each service's own validator:

```bash
testparm -s etc/samba/smb.conf                       # Samba
visudo -c -f etc/sudoers.d/<file>                     # sudoers fragments, if any
systemd-analyze verify usr/lib/systemd/**/*.service   # systemd units
udevadm verify usr/lib/udev/rules.d/*.rules           # udev rules (recent udev/systemd)
```

For polkit `.rules` files (JavaScript-based), at minimum run them through
`node --check` or a JS linter for syntax; there's no dry-run apply
available outside a real polkit daemon, so treat these as higher-risk and
review the actual permission grant carefully — what looks like a narrow
rule can resolve much more broadly than intended.

## Rule: think about the default, not just the syntax

This repo's job is choosing *defaults* for every Shanios install. Before
changing a default (a service's guest-access setting, a udev permission
grant, a polkit action), ask: does this widen what an unprivileged local
user or an unauthenticated network peer can do, without the user
explicitly opting in? If yes, that needs to be a deliberate, documented
choice (see the Tier 1/2 risk framing already used in this repo for other
settings), not an incidental side effect of an unrelated change.

## Where a given config file actually belongs — four candidate homes

Before adding a config file anywhere in this ecosystem, decide which of
these four places actually owns it — putting it in the wrong one causes
real drift (a file that looks authoritative but is dead weight on some
profiles, or a fix applied in a place that gets silently overwritten):

1. **This repo (`shani-settings`) — the default, prefer this unless
   something genuinely can't go here.** Every profile that depends on
   `shani-settings` (currently `gnome`/`plasma`/`cosmic`/`kiosk` — check
   each profile's `package-list.txt` before assuming, `server` notably
   does NOT depend on this repo at all) gets this content identically:
   sysctl, audit rules, fail2ban jails, Samba, sudoers, polkit rules not
   tied to a specific DE's session, `/etc/skel`, and — as of this
   session — the firewalld zone (`etc/firewalld/zones/public.xml`). If a
   file would be *correct* content for every profile that installs this
   repo, it belongs here, even if one profile outside that set (`server`)
   needs something different — that's what (2) is for, not a reason to
   move this one out.
2. **`shani-install-media/image_profiles/<profile>/overlay/rootfs/`
   (`server`'s own, or `shared/overlay/` for `gnome`/`plasma`/`cosmic`) —
   ONLY for a profile that needs different content than this repo's
   default, or for image-assembly mechanics this repo can't express at
   all** (`/etc/fstab`, dracut config, anything about how the image is
   physically built rather than how the OS behaves at runtime). `server`'s
   own firewalld zone (ssh-focused, no mdns) is the correct example of
   "needs an override" — it lives in its own profile overlay precisely
   because `server` doesn't use `shani-settings` and needs genuinely
   different content, not because firewalld zones as a category belong in
   overlay. Don't default to overlay for something that could just be a
   `shani-settings` file with no per-profile variation — that's
   duplicated maintenance for no reason. `kiosk` has its own independent
   overlay too (not shared with gnome/plasma/cosmic) — if it ever needs a
   firewalld zone stricter than the shani-settings default, that override
   belongs in `image_profiles/kiosk/overlay/rootfs/`, not here.
3. **`shani-pkgbuilds/shani-desktop-{gnome,plasma,cosmic}/PKGBUILD` and
   its `.install`** — anything that only makes sense when that specific
   DE is installed: the DE's own packages, its greeter/session service
   enablement (`gdm.service`, `plasmalogin.service`,
   `cosmic-greeter.service`), DE-specific branding/theming, font/icon
   cache regeneration. If it's conditional on "which desktop is this,"
   it belongs in that DE's own package, not in the profile-agnostic
   `shani-settings`.
4. **`shani-install-media/image_profiles/<profile>/<profile>-customization.sh`** —
   reserved for what (1)-(3) genuinely cannot express as a static file or
   a package's own `.install`: conditional logic, `chsh`, editing a file
   that's already been installed by something else, or removing a
   shared-overlay artifact that doesn't apply to this one profile.
   **This is the least common correct answer** — see the "Before claiming
   a package/service is missing" section in `shani-install-media/AGENTS.md`
   for the full chain and why a customization script re-enabling a
   service its own package's `.install` already enables is redundant, not
   defense-in-depth.

## If you have Superpowers / oh-my-opencode / ultrawork / similar available

If your environment provides Claude Code's **Superpowers** plugin, OpenCode's
**oh-my-opencode**, an **ultrawork**-style parallel execution mode, or an
equivalent skill/subagent framework — use it here: this repo is a pile of
independent config files (Samba, udev rules, polkit, sudoers, systemd units)
each with its own real validator (`testparm`, `udevadm verify`, `visudo -c`,
etc.), so a multi-file change is exactly the case for running every file's
validator concurrently rather than one at a time. Don't let a skill
framework's plan-and-report output substitute for actually running each
validator against the real config.

## Audit-verified known issues (confirmed present)

- **`map to guest = Bad Password` — FIXED.** Was: `etc/samba/smb.conf` —
  a real username with a *wrong* password silently mapped to guest access
  on any share opting into guests, instead of a hard auth failure —
  contradicting this same file's own "guest is opt-in, off by default"
  design (`usershare allow guests = no`, every share explicitly
  `guest ok = no`). Changed to `map to guest = Never`; explicit anonymous/
  guest connections to a `guest ok = yes` share are unaffected — this only
  changes how a failed real-user login is handled. **Verified with the
  repo's own documented validator**: `testparm -s` loaded the file clean
  ("Loaded services file OK"), and `testparm -v -s` (which also prints
  default-valued parameters, since `Never` is Samba's own default and
  wouldn't otherwise show) confirmed `map to guest = Never` is the
  parameter Samba actually resolves.
- **`usershare allow guests = yes` (Low) — FIXED.** `etc/samba/smb.conf` let
  any local user's Nautilus/Dolphin "Share this folder" usershare be reached
  by unauthenticated guest clients by default. Flipped to `no` — a
  deliberately public share can still opt back in per-share; this was a
  global default doing it silently.
- **`EDITOR="micro"` literal quotes never stripped (Low) — FIXED.**
  `etc/environment.d/90-shani.conf` — confirmed via `man 5 environment.d`
  ("No other elements of shell syntax are supported"): unlike a shell,
  `environment.d` does not strip quote characters, so this set `$EDITOR` to
  the literal 7-byte string `"micro"` (quotes included) for every service
  reading it from the systemd user environment, not the 5-byte `micro`.
  Changed to unquoted `EDITOR=micro`.
- **Duplicate passwordless `set-user-linger` grant — FIXED.**
  `usr/share/polkit-1/rules.d/99-shani.rules` listed
  `org.freedesktop.login1.set-user-linger` in the generic Tier 1 block
  (`subject.active && subject.local`, no uid scoping) *and* had its own
  dedicated rule further down (`action.lookup("uid") == subject.user.uid`)
  — the dedicated rule is strictly more scoped (self only, not any uid) and
  already covers the same functionality (see its own comment: lets a user
  enable linger for `shani-update.timer`/similar to survive logout).
  Removed the redundant, less-scoped copy from the generic block; the
  properly-scoped dedicated rule still grants it. Functionality unchanged,
  verified by reading both rules — the dedicated one fires on the exact
  same action id/subject conditions, just with an added (already-satisfied
  for a normal self-service call) uid check.
- **World-writable sysfs (Med) — investigated, left as-is.**
  `usr/lib/udev/rules.d/60-openrgb.rules:18-30` uses `chmod a+w` on ~9
  specific ASUS TUF sysfs attributes (`kbbl_*`, `kbd_rgb_mode`,
  `brightness`). Confirmed this whole file is a **verbatim vendored copy of
  upstream OpenRGB's own udev rules** (git-commit-tagged at line 2: "Git
  Commit: b5f46e3f") — every major distro (Fedora, Ubuntu, Arch) ships this
  identical file with this identical pattern, because these specific
  ASUS-WMI sysfs attributes have no group-based access alternative
  upstream provides. Diverging from a verbatim upstream file to "fix" a
  pattern upstream itself ships everywhere would just create drift from
  OpenRGB with no real distro-specific benefit — left unchanged.
- **World-writable USB device — FIXED.**
  `usr/lib/udev/rules.d/99-fanatec-wheel-perms.rules:7` set
  `MODE="0666"` on the raw USB device node for any Fanatec-vendor-ID device
  (a fallback for wheels/pedals with no in-kernel `hid-fanatecff` driver
  bound) — broader than the sibling `99-logitech-wheel-perms.rules`/
  `99-thrustmaster-wheel-perms.rules` in this same repo, which both scope
  their `chmod 666` to specific named sysfs attributes (`range`, `gain`,
  `leds/*/brightness`, etc.), not the whole device node. Changed to
  `TAG+="uaccess"` — systemd-udev/logind's standard ACL mechanism (already
  used elsewhere in this same repo, e.g. `60-openrgb.rules:8`) that grants
  access to whichever user is actually logged in at the seat rather than
  every local user/process, while still giving that user the same raw USB
  access the fallback needs. Verified with `udevadm verify` ("Success: 1,
  Fail: 0").
- **`SigLevel = Never` reference — RESOLVED, not this repo's file anyway.** These files are in `shani-install-media/image_profiles/{kiosk,gnome,plasma}/pacman.conf`, not in this repo — and per that repo's own `AGENTS.md`, all three now read `SigLevel = Required DatabaseOptional` (verified directly: `grep -n SigLevel` on all three shows `Required DatabaseOptional`, no `Never` anywhere). This bullet was pointing at an already-fixed issue in a sibling repo; kept only as a "not our file" cross-repo note, not an open item.
- **CI status.** No CI workflows, no pre-commit hooks.
- **40-hpet-permissions.rules references a group that isn't always installed (Low, documented not fixed).** `usr/lib/udev/rules.d/40-hpet-permissions.rules` sets `GROUP="realtime"`, only created by `shani-pkgbuilds/shani-multimedia`'s `.install` — on `kiosk` (the one profile using `shani-settings` without `shani-multimedia`, confirmed via `package-list.txt`) this silently no-ops (rtc0/hpet stay root-owned), which is harmless since a locked-down kiosk terminal has no pro-audio use case. Added an explanatory comment in the rule file itself rather than changing behavior — see the file for the full reasoning on why this is left alone.
- **udev rule syntax: missing comma before GOTO — FIXED.** `usr/lib/udev/rules.d/99-logitech-wheel-perms.rules` and `99-thrustmaster-wheel-perms.rules` — added the missing commas; re-ran `udevadm verify` and both now pass clean ("Success: 2, Fail: 0").

## Cross-repo impact — check before calling a fix complete

`shani-pkgbuilds/shani-settings/PKGBUILD` packages this repo's `etc/`/`usr/`
trees verbatim, checksummed. Any change here needs that PKGBUILD's
checksums bumped to match, or the packaged artifact silently ships stale
content.

If a config file here assumes a package/service is actually installed and
enabled on a given profile, **don't just check that profile's
`package-list.txt`** — the real dependency and its `systemctl enable` are
very likely one layer down, in `shani-pkgbuilds`. See
`shani-install-media/AGENTS.md`'s "Before claiming a package/service is
missing" section for the full five-layer chain and the incident that
established this rule.

## Where things are documented

`README.md` explains the `etc/`/`usr/` → live-filesystem mapping and how
`shani-pkgbuilds/shani-settings`'s PKGBUILD packages this repo verbatim.
