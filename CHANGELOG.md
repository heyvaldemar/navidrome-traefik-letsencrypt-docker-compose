# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

## [1.0.8] - 2026-09-23

### Fixed

- **CI had never run the restore script.** The test restored with its own
  copy of the commands. The script read `DATA_PATH` and `DATA_BACKUPS_PATH`
  from the shell that ran it rather than from `.env` or the stack, so a path
  set in `.env` was not the one it listed or cleared, and it cleared with
  `rm -rf dir/*`, which leaves every dotfile of the newer state in place. It
  now takes every path and name from the running backups container, accepts
  the backup file name as an argument, starts the application again whatever
  happens, and CI runs it: a file written before a backup and deleted after it
  must be back once that backup is restored.

### Changed

- **The freshness check has its own workflow, Pin Freshness.** It ran inside Deployment Verification, whose badge is the one at the top of this README. Across the fleet, nine red runs in ten were a pin one version behind - which the fleet's triage moves within the day - and a reader cannot tell that from a stack that does not boot. The badge now says whether the stack boots. The job itself is unchanged.

## [1.0.7] - 2026-09-22

### Changed

- **`deluan/navidrome:0.64.0` moved to `deluan/navidrome:0.64.1`.** The freshness check reported the lag; the deploy job booted the stack on the new image before this landed.

## [1.0.6] - 2026-09-21

### Security

- **`traefik:3.7` was rebuilt upstream**; the pin moved from `sha256:1c32e7c36820…` to `sha256:24841fe2de73…`. Same version, same tag, a rebuilt base image — the usual shape of a security fix in a base layer.

## [1.0.5] - 2026-09-19

### Security

- **`alpine:3.22` was rebuilt upstream**; the pin moved from `sha256:365499d9dccb…` to `sha256:5291449c3df7…`. Same version, same tag, a rebuilt base image — the usual shape of a security fix in a base layer.

## [1.0.4] - 2026-09-18

### Security

- **`traefik:3.7` was rebuilt upstream**; the pin moved from `sha256:f86a2cab1b5c…` to `sha256:1c32e7c36820…`. Same version, same tag, a rebuilt base image — the usual shape of a security fix in a base layer.
- **`alpine:3.22` was rebuilt upstream**; the pin moved from `sha256:14358309a308…` to `sha256:365499d9dccb…`. Same version, same tag, a rebuilt base image — the usual shape of a security fix in a base layer.

## [1.0.3] - 2026-09-13

### Fixed

- **The pre-upgrade backup this README recommended was the wrong kind.**
  v1.0.2 told you to tar the data directory before 0.64.0. The loop does the
  same daily, and it is a copy of a live `navidrome.db` with its `-wal` and
  `-shm` beside it, taken by an ordinary archiver. For a daily copy that is
  fine. For the one backup you take before a migration that rewrites every
  table, a snapshot that was not atomic can refuse to open on the day it is the
  only copy that matters. The README now uses `navidrome backup create`, which
  goes through SQLite's online backup API and writes one consistent file.

  It also says to check settings before the upgrade rather than after, because
  0.64.0 validates configuration at startup and rejects negative durations, and
  to prove the migration by comparing counts rather than by the absence of an
  error. Both come from running this exact upgrade on a real library and
  watching what it did.

## [1.0.2] - 2026-09-13

### Changed

- **The 0.64.0 upgrade is documented where somebody deciding to take it will
  read it.** v1.0.1 moved the pin from 0.63.2 and said only that the freshness
  check reported a lag. That is true and it is not enough: 0.64.0 re-encodes
  item ids across every table in a **one-way** migration, and a database it has
  touched cannot be opened by 0.63.2 again.

  A first deploy is unaffected, which is why CI was green and stayed green: it
  boots a fresh stack every run and never sees the migration at all. A
  deployment coming from an earlier pin is the case that matters, and it gets a
  section in the README now: take a backup you can restore from rather than
  trusting the loop's next scheduled run, let the first start finish the
  migration without interrupting it, and expect offline-sync clients to need a
  re-sync.

### Fixed

- `.env.example` still named 0.63.2 in two places after the pin moved. The
  automatic bump rewrites the compose file and the README's version line and
  does not read that file.

## [1.0.1] - 2026-09-13

### Changed

- **`deluan/navidrome:0.63.2` moved to `deluan/navidrome:0.64.0`.** The freshness check reported the lag; the deploy job booted the stack on the new image before this landed.

## [1.0.0] - 2026-09-10

First release. A production deployment of Navidrome behind Traefik, built to
the fleet standard established in
[keycloak-traefik-letsencrypt-docker-compose](https://github.com/heyvaldemar/keycloak-traefik-letsencrypt-docker-compose).

### Added

- **Navidrome behind Traefik with Let's Encrypt TLS.** Three images pinned by
  `tag@sha256:<digest>` in the compose `x-images` block: the server, Traefik,
  and a plain alpine for the backups sidecar.
- **The Subsonic API asserted on every CI run**, not just the web player. The
  API is most of the reason to run Navidrome — every Subsonic client on every
  platform speaks it — and a deployment where only the web UI answers has lost
  half of that. An unauthenticated call must come back as a Subsonic error
  document rather than a 404: that is the proof the endpoint is routed and the
  server is speaking the protocol.
- **A read-only music mount, proven by failing to write to it.** Upstream asks
  for `:ro` and this template does it, but CI goes further and tries the write,
  requiring it to fail. A scanner with write access to the collection is one
  bad release away from a very long restore.
- **Compression as an allow-list rather than a blanket.** An mp3 or a flac is
  already compressed; gzipping one spends CPU on both ends to make the file
  marginally larger. `includedContentTypes` names html, css, javascript, json,
  xml and svg, so the web UI and the API are compressed and the audio never is.
- **A backup loop that reads its own archive back before naming it a backup.**
  Each cycle writes `.partial`, verifies it with `tar -tzf`, and only then
  renames. BusyBox tar returns exit code 1 both for "a file changed while I
  read it" and for "I could not write the output at all", so the exit code
  alone would rename an empty file into place and log it as OK.
- **An archive that is checked for the database by name.** Everything else
  under `/data` is a cache that rebuilds itself; `navidrome.db` is the users,
  playlists, play counts and ratings. An archive missing that one file restores
  into a server that starts cleanly and has forgotten every listener, so the
  test asks for it specifically.
- **A restore script that stops the server first**, because the database is
  SQLite and is written on every scrobble and every scan.
- **Deployment Verification workflow.** shellcheck and actionlint, Trivy scans
  of all three images, a daily freshness check, and a deploy job requiring the
  server to answer through Traefik, the Subsonic API to answer in its own
  protocol, the music mount to refuse a write, an archive to be produced and to
  carry the database, eight backup and restore scenarios to pass, and Navidrome
  to come back on the data directory the restore replaced.
- **`update.sh`**, container hardening with `cap_drop: ALL` on every service,
  resource limits and reservations on all three, and a sixty-second
  `stop_grace_period` on the server.

### Notes

- **`/ping` answers with a single `.`**, not JSON and not a word. Both the
  health check and the CI wait loop match that exactly (`grep -qx`), because a
  bare `grep -q .` would match any byte the server happened to return,
  including an error page. The first draft looked for the word `true` in both
  places; correcting only one of them left CI waiting eight minutes for a
  string that was never going to arrive.
- **A failing health check looks exactly like a missing route.** Traefik does
  not route to a container whose health check is red, and it logs nothing when
  it declines to. The first draft of this file probed `/ping` for the word
  `true`; every request through Traefik answered `404 page not found`, which
  reads as a routing problem and is not. Correcting the probe made the route
  appear in the same second.
- **There is no Buffering middleware, and that is deliberate.** Traefik streams
  request and response bodies unless one is attached; attaching it is what
  turns buffering on, and `0` on its limits means *no size ceiling*, not *off*.
  Measured against a response that takes four seconds to produce: 0.03s to the
  first byte without it, 4.15s with it — a whole track assembled in the proxy
  before playback could start. What limits a long request is the entry point's
  `readTimeout`, 60 seconds by default and set to zero here.
- **The container runs as root inside, and `cap_drop: ALL` is why that is
  acceptable.** Upstream recommends running as the owner of the music library,
  but the image's `/data` is owned by root, so a `user:` override on a fresh
  named volume produces a container that cannot write its own database.
  Shipping that as a default would mean shipping a stack that does not start.
  `.env.example` carries the override file and the `chown` for people who
  bind-mount `/data` on a directory they own.

[Unreleased]: https://github.com/heyvaldemar/navidrome-traefik-letsencrypt-docker-compose/compare/v1.0.7...HEAD
[1.0.7]: https://github.com/heyvaldemar/navidrome-traefik-letsencrypt-docker-compose/compare/v1.0.6...v1.0.7
[1.0.6]: https://github.com/heyvaldemar/navidrome-traefik-letsencrypt-docker-compose/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/heyvaldemar/navidrome-traefik-letsencrypt-docker-compose/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/heyvaldemar/navidrome-traefik-letsencrypt-docker-compose/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/heyvaldemar/navidrome-traefik-letsencrypt-docker-compose/releases/tag/v1.0.3
[1.0.2]: https://github.com/heyvaldemar/navidrome-traefik-letsencrypt-docker-compose/releases/tag/v1.0.2
[1.0.1]: https://github.com/heyvaldemar/navidrome-traefik-letsencrypt-docker-compose/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/heyvaldemar/navidrome-traefik-letsencrypt-docker-compose/releases/tag/v1.0.0
