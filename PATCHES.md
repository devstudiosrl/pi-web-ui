# The Printalo patches

**There are none today, and that is the method working.**

This fork exists because pi-web-ui is used as the Chat inside
[Printalo](https://helpdesk.printalo.cloud), a site that releases through one
path only (`sync-from-git.sh`) and that shows this interface to people who are
not developers. Three things in the upstream default did not fit that, and none
of them could be turned off with configuration.

**`main` mirrors upstream and is never touched.** All the work is on
`printalo`, which is upstream's release commit plus the patches below, one
commit each, replayed on every sync by `scripts/sync-upstream.sh`.

**Every patch is written to be useful to somebody who is not us**, and is
proposed upstream. That is the point: if a patch is accepted it disappears from
this table and becomes plain configuration. A patch that could only ever help
Printalo belongs in Printalo, not here.

| # | Patch | Switch | Upstream PR | State |
|---|---|---|---|---|
| — | none | — | — | — |

## Accepted upstream

All three were merged on 8 September 2026 and ship with pi-web-ui since
**0.69.0**; `printalo` stopped carrying them when it moved to 0.97.0. They are
plain configuration now. The sections below say what each one was for, kept
because the reasons are why Printalo sets those switches.

| # | Patch | Switch | Upstream PR | State |
|---|---|---|---|---|
| 1 | Managed instances: no in-app self-update, no installing plugins from the network | `PI_WEB_MANAGED=1` | [#92](https://github.com/xing-shuyin/pi-web-ui/pull/92) | merged, 0.69.0 |
| 2 | Tab allow-list, enforced on the server too | `PI_WEB_TABS=chat,search,settings` | [#93](https://github.com/xing-shuyin/pi-web-ui/pull/93) | merged, 0.69.0 |
| 3 | First-visit language from the browser instead of a hardcoded default | `PI_WEB_LOCALE=en` | [#94](https://github.com/xing-shuyin/pi-web-ui/pull/94) | merged, 0.69.0 |

PR #92 also carried the follow-up fixes found by running a managed instance
(no update checks on connect, the package's own version in the ready message,
no "install pi" offer in the setup dialog) and an upstream bug found on the way:
`APP_VERSION` was always empty because it read a `const` in its temporal dead
zone. Upstream has all of it.

## 1. Managed instances — `PI_WEB_MANAGED=1`

**What upstream did before 0.69.0.** The top bar carries an updates badge and an
UPDATE panel whose buttons run `npm i -g pi-web-ui@latest` in a visible
terminal and restart the server. The plugin catalog can install plugins from
the network.

**Why that is wrong here.** Printalo installs pi-web-ui from its own release
script, which also checks nginx, the systemd unit, the new environment
variables and that the build is fresh. A button that upgrades one piece of the
server outside that path leaves the machine in a state the repository does not
describe — and the next real release may quietly undo it.

**Why anybody else wants it.** This is what every packaged install looks like:
Docker images, Homebrew, Debian packages, anything behind a deploy pipeline.
For those, self-update is not a feature, it is a way to break the package.

**Shape.** With `PI_WEB_MANAGED=1` the server refuses `check_update`,
`check_updates_all`, `install_pi_agent` and `plugin_catalog_add` with an
explicit error, and the client hides the badge, the UPDATE panel and the plugin
market. The server side is the part that matters: hiding a button while the
socket still accepts the message is hiding, not disabling.

## 2. Tab allow-list — `PI_WEB_TABS`

**What upstream did before 0.69.0.** Chat, Terminal, Git, Search, Background tasks,
Settings, plus plugin tabs — all always present. Terminal opens a shell as the
server's user; Git shows the working copy with commit and diff at a click.

**Why that is wrong here.** The Chat is reachable by people who review answers,
not by people who administer the machine. A shell on the server is not a
service we mean to offer from a web page.

**Why anybody else wants it.** Anyone exposing pi-web-ui beyond their own
laptop needs to choose what it offers. There is no switch today, so the answer
is either "expose everything" or "fork it" — which is why this fork exists.

**Shape.** `PI_WEB_TABS=chat,search,settings`: absent means all tabs, exactly
as today, so nothing changes for anybody who does not set it. The client does
not draw the excluded tabs and the server refuses their messages
(`terminal_*`, `run_command`, `scm_*`, the background-server ones).

## 3. First-visit language — `PI_WEB_LOCALE`

**What upstream did before 0.69.0.** `loadLocale()` in `web/src/i18n.tsx` returns
`"zh"` when nothing is stored. A first-time visitor gets Chinese whatever their
browser asks for, and has to find the language chip to change it.

**Why anybody else wants it.** Upstream already ships eight downloadable
language packs (de, es, fr, it, ja, ko, pt, ru) besides core zh and en: the
translations exist, they are just never chosen automatically. Honouring
`navigator.languages` is what every other web application does, and it makes
those packs actually reachable.

**Shape.** First visit picks, in order: a language stored from a previous
visit; `PI_WEB_LOCALE` if the server sets one; the first of
`navigator.languages` for which a locale exists; then `en`. Explicit choice
always wins and is still remembered.

## Not patches: the fork's own machinery

Some commits on `printalo` change nothing in pi-web-ui itself and are never
proposed upstream, because they only make sense in a fork:

- `scripts/sync-upstream.sh` and its test, `PATCHES.md`, the Printalo chapter
  of the README;
- the `release` workflow, which builds a pushed `v*-printalo.*` tag and attaches
  the tarball to the GitHub Release, and the weekly `upstream check`;
- a guard on upstream's own tag workflows (`desktop-release`, `release-notes`,
  `extension-release`): they fire on any `v*` tag, so without it every
  Printalo tag would also try to build and publish upstream's desktop
  installers and browser extension from this repository.
