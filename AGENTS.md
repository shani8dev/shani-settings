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

## Empirical verification (mandatory)

**Reading code is analysis; running code is verification.** A change is not
verified by reading the diff, running `bash -n`, or confirming it "looks
correct." It is verified by observing the actual behavior of the real
thing in the real environment — built, served, deployed, signed, running.
If you haven't seen it work (or fail) for real, it isn't verified.

## Rule: syntax-check every config with its own real validator, don't eyeball it

A config file that "reads fine" and one that a real daemon will actually
load without error are different claims — this repo ships services
(Samba, polkit rules, udev rules, systemd units) whose config syntax is
easy to get subtly wrong (indentation-sensitive stanzas, deprecated
directives, boolean spelling). Use each service's own validator:

```bash
testparm -s etc/samba/smb.conf                        # Samba (needs samba-common-bin)
visudo -c -f etc/sudoers.d/<file>                      # sudoers fragments
udevadm verify usr/lib/udev/rules.d/*.rules            # udev rules (recent udev/systemd)
```

This repo ships no `.service`/`.timer` units (confirmed:
`find usr/lib/systemd -name '*.service' -o -name '*.timer'` is empty —
only manager/journald `*.conf.d/*.conf` drop-ins), so `systemd-analyze
verify` has nothing to check here; `tests/validate-configs.sh` instead does
a `[Section]`/`Key=Value` well-formedness check on those drop-ins.

For polkit `.rules` files (JavaScript-based), `node --check` needs a `.js`
extension to recognize the file as CommonJS — copy to a temp `.js` path
first (`cp usr/share/polkit-1/rules.d/99-shani.rules /tmp/x.js && node
--check /tmp/x.js`); running it directly on the `.rules` path fails with
`ERR_UNKNOWN_FILE_EXTENSION`, not a real syntax error. There's no dry-run
apply available outside a real polkit daemon, so treat these as
higher-risk and review the actual permission grant carefully — what looks
like a narrow rule can resolve much more broadly than intended.

**`tests/validate-configs.sh` already wires all of the above together**
against this repo's real `etc/`/`usr/` files (not a synthetic fixture) —
run it directly rather than reinventing the above by hand:
```bash
bash tests/validate-configs.sh          # validates THIS repo's real files
bash tests/test_validator.sh            # proves the validator catches real breakage (negative controls)
```

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

## Commit discipline

Before composing a commit message, run `git log --oneline -20` (and `git
log -5 -- <touched paths>` for the files you changed) and match the
existing style — subject shape, scope prefixes, body detail level —
rather than writing in a generic format.

## Boundaries

- ✅ **Always**: run the config's own real validator (`testparm`, `visudo
  -c`, `udevadm verify`, `node --check` via a temp `.js` copy) before
  calling a change done — `tests/validate-configs.sh` already wires all of
  these together, use it rather than reinventing.
- ⚠️ **Ask first**: widening what an unprivileged local user or
  unauthenticated network peer can do (a guest-access setting, a udev
  permission grant, a polkit action) — this repo sets the default for the
  entire fleet on day one, so that's a deliberate, documented choice, not
  an incidental side effect.
- 🚫 **Never**: "fix" `60-openrgb.rules`'s world-writable sysfs pattern to
  look more locked-down — it's a verbatim, commit-tagged copy of upstream
  OpenRGB's own rules, shipped identically by every major distro; diverging
  creates drift with no real benefit, not a real hardening win.
- 🚫 **Never**: delete or skip a failing test to make a build/CI pass — fix the underlying code, not the test. A red test is signal; silencing it destroys the signal, not the bug.

## Audit-verified known issues (confirmed present)

- **Validator broke on current systemd; tmpfiles errored at every install;
  shipped modes wrong — FIXED (2026-09-23).** (1) `tests/validate-configs.sh`
  exempted the known `40-hpet-permissions.rules` warning by its old wording
  only; systemd >= 256 (Arch 261, what ShaniOS ships) says "Failed to resolve
  group 'realtime', ignoring: Unknown group", so the real tree FAILED there
  (CI stayed green only on ubuntu-latest's older udev). Both wordings now
  exempt; `test_validator.sh` 8/8 on systemd 261. (2) The 9 sysfs/procfs
  `w` lines in `usr/lib/tmpfiles.d/` errored ("Read-only file system", rc=73)
  on the pacman hook's `systemd-tmpfiles --create` in the image-build chroot
  (seen in the plasma CI build log). Now `w!` (boot-only): verified silent on
  `--create`, still applied by `systemd-tmpfiles-setup.service` (`--boot`).
  (3) Packaging, in `shani-pkgbuilds/shani-settings/PKGBUILD`: a recursive
  `chmod 750 -R` ran after the per-file modes, so every shipped sudoers
  drop-in was 0750 (`visudo -c`: "bad permissions, should be mode 0440") and
  the polkit rules dir conflicted with Arch polkit's own 755 (pacman "directory
  permissions differ" on every install). Fixed there (dir left 755 root:root);
  verified by `pacman -U` of a package built from this working tree onto
  Arch (polkit 127): no permission warning, sudoers 0440 + `visudo -c` OK,
  the tmpfiles hook no longer fails. Note the PKGBUILD builds from the
  GitHub tarball at `_commit`, so none of this ships until committed,
  pushed and `_commit` bumped.

- **sysctl.d: 9 keys that could not apply at boot — FIXED (2026-09-23).**
  Checked every one of the 129 keys against `/proc/sys` on a real 7.0
  kernel (ShaniOS ships 7.1.8), then ran real `systemd-sysctl` (Arch,
  systemd 261.3) over `HEAD` vs the working tree in an unprivileged
  container, where nothing gets written and a missing key still shows as
  "No such file or directory". (1) `20-sched.conf`'s
  `kernel.sched_child_runs_first` no longer exists on these kernels (same
  fate as the EEVDF-era knobs `e4a6007` already removed): removed. (2)
  `80-gamecompatibility.conf`'s 8 per-bridge `net.ipv4.conf.<br>.rp_filter`
  keys (waydroid0, podman0/1, cni-podman0, lxdbr0, lxcbr0, virbr0,
  docker0) logged "Couldn't write ... No such file or directory" on every
  boot, contrary to the old "harmless" comment. They DO take effect: in a
  container netns, creating `virbr0` and running what systemd's
  `99-systemd.rules` runs on a net "add" event
  (`systemd-sysctl --prefix=/net/ipv4/conf/virbr0`) moved it 2 → 0. Now
  prefixed with `-` (skip if missing): boot is silent and hotplug still
  applies 0. Result: 14 → 5 "missing" lines in the container. The 5 left
  (`net.ipv4.neigh.default.gc_thresh1-3`, `net.core.bpf_jit_harden`,
  `net.core.netdev_max_backlog`) exist only in the initial netns and are
  present on the real host kernel, so they are not bugs.
  `tests/validate-configs.sh` + `tests/test_validator.sh` (8/8) still
  pass. Ships only after `shani-pkgbuilds/shani-settings/PKGBUILD`'s
  `_commit` is bumped.

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
  enable linger for user systemd units (like `shani-cassini-agent.timer`)
  to survive logout).
  Removed the redundant, less-scoped copy from the generic block; the
  properly-scoped dedicated rule still grants it. Functionality unchanged,
  verified by reading both rules — the dedicated one fires on the exact
  same action id/subject conditions, just with an added (already-satisfied
  for a normal self-service call) uid check.
- **No PAM stack is shipped here at all (verified 2026-09-26; the recipe below
  is tested, but deliberately NOT shipped — it is a policy decision).** This
  repo is the `/etc` + `/usr` overlay, and it does ship real `/etc` content —
  `firewalld`, `fail2ban`, `sudoers.d`, `samba`, `environment.d`, `skel` —
  but **no `pam.d` directory and no PAM file of any kind** (filesystem sweep).
  Every install therefore runs on stock pambase configuration, and stock Arch
  never references `pam_pwquality` anywhere. So `shani-core`'s
  `libpwquality` is installed and **inert**: no password strength policy is
  enforced (recorded against the dependency in `shani-pkgbuilds`, `611e164`).
  **Where it would go, and why it is not trivial:** there is no
  `/etc/pam.d/password` on Arch at all — the real stack is
  `/etc/pam.d/system-auth`, and `passwd`, `su`, `login` and `chpasswd` each
  do `password include system-auth`. That one file is pambase-owned and
  contains **all four stacks** (auth, account, password, session) with **no
  `@include` hook**, so enforcing strength means replacing it wholesale and
  owning `auth` too. Verified end-to-end in an Arch container: inserting
  `password requisite pam_pwquality.so retry=3 minlen=12` above
  `pam_unix.so` **rejects** a 5-char password (`BAD PASSWORD: ... shorter
  than 12 characters`), still **accepts** a valid one, and leaves `su` auth
  and the `chpasswd` installer path working (both re-tested unmodified and
  modified). Not shipped because it sets password policy for every user, and
  because owning `auth` in the same file means a mistake locks people out of
  an immutable OS. If you want it, that is a one-line insert into
  `etc/pam.d/system-auth` — but it must be a deliberate maintainer choice, and
  the file will need re-syncing whenever pambase changes.
  **Enterprise directory login is also not a drop-the-package-in job.** KDE's
  2026-2028 goal list asks for Web/Kerberos SSO and better LDAP integration;
  the only Kerberos in the tree is incidental (`splix` has a build-time
  `krb5` makedepend for a printer driver, `shani-peripherals` pulls
  `pam-krb5` for authenticated printing), and `shani-network` depends on
  `openldap` for client libraries only — no
  `slapd` server, no `sssd_ldap`, no PAM identity wiring. Real SSO would
  mean authoring the PAM layer in this repo first, then adding directory
  integration on top. Do not assume a PAM file exists to extend.
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
- **CI status — corrected, contradicted this file's own roadmap section
  below.** `.github/workflows/ci.yml` has two jobs: `validator-tests`
  (installs `samba-common-bin`, runs `tests/test_validator.sh` against
  this repo's real payload) and `checksum-sync` (runs
  `tests/check-checksums.sh` against the sibling `shani-pkgbuilds`
  checkout) — see roadmap items 1-3 below for the full detail. No
  pre-commit hooks yet.
- **40-hpet-permissions.rules references a group that isn't always installed (Low, documented not fixed).** `usr/lib/udev/rules.d/40-hpet-permissions.rules` sets `GROUP="realtime"`, only created by `shani-pkgbuilds/shani-multimedia`'s `.install` — on `kiosk` (the one profile using `shani-settings` without `shani-multimedia`, confirmed via `package-list.txt`) this silently no-ops (rtc0/hpet stay root-owned), which is harmless since a locked-down kiosk terminal has no pro-audio use case. Added an explanatory comment in the rule file itself rather than changing behavior — see the file for the full reasoning on why this is left alone.
- **udev rule syntax: missing comma before GOTO — FIXED.** `usr/lib/udev/rules.d/99-logitech-wheel-perms.rules` and `99-thrustmaster-wheel-perms.rules` — added the missing commas; re-ran `udevadm verify` and both now pass clean ("Success: 2, Fail: 0").
- **`tests/validate-configs.sh` validated a fictional config format, not this repo's real files — FIXED (2026-09-18).** The version shipped by the earlier "Per-Config Validator Integration" pass (roadmap #24) parsed an invented `/etc/shani/shani.conf` with `[network]`/`[security]`/`[services]` INI sections — this repo ships **no such file** (confirmed: `find etc usr -iname '*shani.conf*'` matches only `etc/environment.d/90-shani.conf` and `usr/lib/sysctl.d/99-sysctl-shani.conf`, neither INI-sectioned). `tests/test_validator.sh` tested that same fictional format against synthetic fixtures, so CI's `validator-tests` job was green while validating nothing this repo actually ships — dead code presented as done, same pattern as other repos audited this session. Rewrote both: `validate-configs.sh` now runs `visudo -c -f` on every real `etc/sudoers.d/*` fragment, `testparm -s` on the real `etc/samba/smb.conf` (skips with a warning if `testparm` isn't installed, rather than silently "passing"), `udevadm verify` on every real `usr/lib/udev/rules.d/*.rules` file (with a narrow, explicitly-checked exemption for the known-accepted `40-hpet-permissions.rules` "Unknown group 'realtime'" warning above — any *other* failure in that same file still fails the check), `node --check` (via a temp `.js` copy) on the real polkit rules file, and a `[Section]`/`Key=Value` well-formedness check on the real `usr/lib/systemd/*.conf.d/*.conf` drop-ins (no `.service`/`.timer` units ship here, so `systemd-analyze verify` has nothing to check). `test_validator.sh` now runs the validator against this repo's real tree (must pass) plus 6 deliberately-corrupted copies — one real corruption per validated class, including the exact "missing comma before GOTO" bug class already fixed once in this repo — each proven to be caught (8/8 tests pass, live-verified). CI (`.github/workflows/ci.yml`) now installs `samba-common-bin` so `testparm` actually runs instead of perpetually skipping.

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

## Garuda Cross-Reference Findings (added 2026-09-17)

Based on a full scan of 29 garuda-linux repos mapped against shani (see `../garuda-catalog.md` — 29 repos, not 34; several user-listed names don't exist). See `../garuda-mapping-analysis.md` and `../deep-analysis.md` for full details. garuda-settings-manager is the most directly comparable repo — both manage system settings (note: garuda-settings-manager is a Qt5/KF5 KCM GUI app, not a config-file overlay like this repo).

### 🟡 HIGH: CI/CD gap (shared across ALL repos)

1. **Shared CI templates** (estimated 2-3 days, affects ALL repos).
   - Garuda's `gitlab-ci-commons` provides reusable templates (commitizen, flake-check, pre-commit, tag-to-release). Each repo `include:`s from it.
   - Shani repos run on GitHub Actions (no `.gitlab-ci.yml` anywhere) — 8 repos (blog, builder, docs, fleet, insights, install-media, pkgbuilds, platform) carry hand-written `.github/workflows/*.yml` with duplicated patterns.
   - **Action**: Create `shani-ci-commons` (GitHub Actions reusable workflows / composite actions) with templates for lint, test, build, security scan. Each repo references them via `uses: shani8dev/shani-ci-commons/...` instead of copy-pasting.
   - **Affects**: All 15 shani repos.

### 🟡 HIGH: Dependency management gap

2. **Add automated dependency updates** (estimated 4 hours, affects ALL repos).
   - Garuda uses `renovate-runner` running hourly against all repos with `renovate.json` files.
   - Shani repos have no automated dependency updating.
   - **Action**: Set up Renovate (self-hosted or gitlab.com) with a fleet-wide config. Each repo adds a minimal `renovate.json`.

### 🟢 MEDIUM: Code quality

3. **Conventional commit enforcement** (estimated 2 hours, affects ALL repos).
   - Every garuda repo has a `[commitizen]` badge; `cz commit` is enforced.
   - Shani repos have no commit message standardization.

### 🟡 Cross-repo: Centralized config

4. **Centralized config for deploy/build tools** (estimated 1-2 days).
   - Garuda uses a layered config system: `/etc/garuda-tools/garuda-tools.conf` (system-wide) + `~/.config/garuda-tools/garuda-tools.conf` (user override). Config defines build targets, chroot dirs, cache dirs, mirrors.
   - Shani scripts hardcode paths or use env vars — no equivalent centralized config.
   - **Action**: Create `/etc/shani/shani.conf` (or similar) with DEPLOY_CHANNEL, BUILD_MIRROR, ISO_CACHE_DIR, BUILD_DIR. Follow the user-override pattern. See `shani-deploy/AGENTS.md` for the same finding.

### 🔍 Re-Scan Findings (2026-09-17)

Re-scan against `../garuda-catalog.md` (29 repos, not 34). **Confirmed mapping: garuda-settings-manager** ✅ (exists) — but it is a **Qt5/KF5 KCM-module GUI app** (KDE settings manager using KF5::Auth for privilege escalation), not a config-file overlay like this repo. The closer structural counterpart for a static `/etc`+`/usr` overlay is **garuda-setup-assistant** ✅ (installs to `etc/`/`usr/` layout, i18n translations, Qt wizard pages).

**New gaps** (garuda has, shani-settings lacks):

1. **First-run setup wizard** — garuda-setup-assistant is a first-run wizard (Calamares post-install) with Qt pages + Transifex i18n; shani has no first-run wizard (os-installer-config's `configure.sh` is CLI-only).
2. **Translation infrastructure** — garuda-setup-assistant/garuda-system-maintenance use Transifex (`transifex.yml`) + i18n dirs; shani-settings has no i18n.
3. **Maintenance notifications** — garuda-system-maintenance ships `.notifyrc` desktop notifications + systemd rules; shani has no maintenance-notification mechanism.
4. **Layered config** — garuda-tools' `/etc/garuda-tools/garuda-tools.conf` + `~/.config/` user-override pattern; shani-settings has no layered config (already noted above).

**Shani advantages** (shani-settings has, garuda lacks):

- Per-service validators (`testparm`, `visudo -c`, `systemd-analyze verify`, `udevadm verify`) — garuda has no config-validation tooling
- Tier 1/2 risk framing for privilege-granting defaults (documented security posture)
- Profile-aware defaults (server override pattern; garuda-setup-assistant is per-flavor but not security-framed)

**Qt GUI gap note**: the comparable garuda repos are GUI apps (garuda-settings-manager Qt5/KF5, garuda-setup-assistant Qt) while shani-settings is a static overlay — garuda's 12 Qt GUI apps have no shani counterpart beyond shani-cassini.

### 📋 Implementation Roadmap (2026-09-17)

Implementation priorities are per `../IMPLEMENTATION-ROADMAP.md` (master roadmap for the whole shani ecosystem).

shani-settings already has what garuda's comparable repos lack: per-service validators (`testparm`, `visudo -c`, `systemd-analyze verify`, `udevadm verify`), a documented Tier 1/2 risk framing for privilege-granting defaults, and profile-aware defaults. The items below wire those strengths into automation rather than porting garuda's Qt GUI apps (garuda-settings-manager is Qt5/KF5 KCM modules — not relevant to a static `/etc`+`/usr` overlay).

1. **Per-Config Validator Integration** ✅ DONE (2026-09-18, corrected) — `tests/validate-configs.sh` runs `visudo -c -f`, `testparm -s`, `udevadm verify`, and a `node --check`-based JS syntax check against this repo's *real* `etc/`/`usr/` files (an earlier version validated an invented config format nobody ships — see "Audit-verified known issues" above). Wired into CI via the `validator-tests` job. Not yet wired into a local pre-commit hook.

2. **Automated checksum-sync check with shani-pkgbuilds** ✅ DONE (2026-09-18) — `tests/check-checksums.sh` parses the sibling `shani-pkgbuilds/shani-settings/PKGBUILD`'s `source=()`/`sha256sums=()` (handling single- and double-quoted entries and the `name::url` tarball form) and compares each non-SKIP entry against the repo file, failing on mismatch. The PKGBUILD currently packages the repo as a release tarball with `sha256sums=('SKIP')` (authenticity delegated to the pinned `_commit`), so the script prints a SKIP notice and exits 0, with a NOTE about commit-drift staleness; if the PKGBUILD is ever converted to per-file sources with real hashes, the comparison path activates automatically (verified: match→0, mismatch→1). Wired into CI (`.github/workflows/ci.yml`, `checksum-sync` job, sibling repo checked out).

3. **CI workflows** ✅ DONE (2026-09-18, corrected) — `.github/workflows/ci.yml`: `validator-tests` job installs `samba-common-bin` (for real `testparm`) and runs `bash tests/test_validator.sh`, which now exercises `validate-configs.sh` against this repo's *real* `etc/`/`usr/` payload plus deliberately-corrupted copies (not synthetic INI fixtures, see item 1 above); `checksum-sync` job runs `tests/check-checksums.sh` against the sibling `shani-pkgbuilds` checkout. A shared `shani-ci-commons` template (roadmap #7) could still replace this hand-written workflow later, but the validation coverage itself is real and complete now.

4. **LICENSE file** — ✅ DONE (2026-09-17, audit-verified): the repo now tracks a GPL-3.0 LICENSE at repo root (matching the ecosystem standard); the original master-roadmap #31 gap is closed.

5. **Conventional commits + renovate.json** (P1, ~1 hour) — Add commitizen config and a minimal `renovate.json` (roadmap #8-9). Note: this is a config-only repo with no dependency tree, so Renovate's value here is minimal — the commitizen half is the useful part.
