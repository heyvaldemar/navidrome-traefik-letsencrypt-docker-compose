# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

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

[Unreleased]: https://github.com/heyvaldemar/navidrome-traefik-letsencrypt-docker-compose/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/heyvaldemar/navidrome-traefik-letsencrypt-docker-compose/releases/tag/v1.0.0
