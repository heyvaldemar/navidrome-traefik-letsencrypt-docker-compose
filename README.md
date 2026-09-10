# Navidrome + Traefik + Let's Encrypt on Docker Compose

[![Deployment Verification](https://github.com/heyvaldemar/navidrome-traefik-letsencrypt-docker-compose/actions/workflows/deployment-verification.yml/badge.svg?branch=main)](https://github.com/heyvaldemar/navidrome-traefik-letsencrypt-docker-compose/actions/workflows/deployment-verification.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

This repository deploys Navidrome (a self-hosted music server that speaks the Subsonic API, so every Subsonic client on every platform works with it) behind Traefik with automatic Let's Encrypt TLS, with scheduled backups of everything it knows and a companion restore script.

## Getting started

```bash
# 1. Clone
git clone https://github.com/heyvaldemar/navidrome-traefik-letsencrypt-docker-compose
cd navidrome-traefik-letsencrypt-docker-compose

# 2. Create the two Docker networks the stack expects
docker network create traefik-network
docker network create navidrome-network

# 3. Copy the environment template and fill in required values
cp .env.example .env
$EDITOR .env
# ^ Required: NAVIDROME_HOSTNAME, TRAEFIK_HOSTNAME,
#   TRAEFIK_ACME_EMAIL, TRAEFIK_BASIC_AUTH.
#   Point NAVIDROME_MUSIC_PATH at your collection, or leave it and use ./music.

# 4. Deploy
docker compose -f navidrome-traefik-letsencrypt-docker-compose.yml -p navidrome up -d
```

**Open the site and create your account immediately.** The first account created becomes the administrator, and until that happens the sign-up form is open to whoever reaches it.

### What success looks like

```bash
docker compose -f navidrome-traefik-letsencrypt-docker-compose.yml -p navidrome ps
curl -s "https://${NAVIDROME_HOSTNAME}/rest/ping.view?c=probe&v=1.16.1&f=json"
# {"subsonic-response":{"status":"failed","version":"1.16.1","type":"navidrome",…}}
```

`ps` shows `navidrome` and `traefik` healthy, and `backups` running with no health check of its own. That `"status":"failed"` is correct: the call carried no credentials, and the server answering it in Subsonic's own error format is exactly the proof that the API is routed and speaking the protocol.

### Common first-deploy issues

- **Traefik answers `404 page not found` and its log says nothing.** That is almost never the router. Traefik does not route to a container whose health check is failing, so a broken probe looks exactly like a missing route. `docker compose -p navidrome ps` shows the health column; fix the probe and the route reappears in the same second.
- **The library is empty after a deploy.** The music mount is read-only and points where `NAVIDROME_MUSIC_PATH` says. Check it resolves to what you meant: `docker compose -p navidrome exec navidrome ls /music`.
- **New albums do not show up.** The default scan schedule is nightly, not continuous. Trigger one from Settings, or set `NAVIDROME_SCAN_SCHEDULE`.
- **Cert issuance fails.** DNS has not propagated, or port 80 is not reachable from the internet.
- **Networks not found.** Step 2 was skipped.

## Every Subsonic client works

Navidrome's web player is not the point; the Subsonic API is. Point any Subsonic client at `https://your.hostname` with your Navidrome username and password and it works — no separate app, no vendor account. CI asserts that the API is routed on every run, because a deployment where only the web UI answers has lost half the reason to run this.

## The music mount is read-only

Upstream's own documentation asks for this, and it is worth saying why. Navidrome never needs to write to your collection, and a scanner with write access to it is one bad release away from a very long restore. It is mounted `:ro` here, the archive does not include it, and CI proves the mount by trying to write to it and requiring the write to fail.

What the archive does hold is the part that is expensive to lose and impossible to rebuild: users and their passwords, playlists, play counts, ratings, starred items, and the API tokens every client holds. Ten years of listening history is not something a rescan brings back.

## Compression, but only where compression helps

An mp3 or a flac is already compressed. Running one through gzip spends CPU on both ends to make the file marginally larger, which is why a blanket `compress` middleware is the wrong default for a music server. The middleware here is an allow-list — `includedContentTypes` names html, css, javascript, json, xml and svg — so the web UI and the Subsonic API get compressed and the audio never does.

## No buffering middleware, deliberately

Traefik streams request and response bodies. It only buffers if you attach a `buffering` middleware, and setting that middleware's limits to `0` means *no size ceiling*, not *off* — so the label people add to "turn buffering off" is the label that turns it on. Measured on this stack against a response that takes four seconds to produce: 0.03s to the first byte without the middleware, 4.15s with it, the whole track assembled in the proxy before playback could start.

What actually limits a long request is the entry point's `readTimeout`, which is 60 seconds by default and is set to zero here; `idleTimeout` is raised from the 180-second default to ten minutes.

## Updating

`./update.sh` moves this checkout to the latest release tag — a combination this repository's CI has booted, upgraded from the previous release on the same volumes, and smoke-tested — and then runs `docker compose up -d`. It refuses to cross a major version unattended, refuses to run over local changes, and names any variable that became required since your version before anything has moved. `./update.sh --dry-run` says what would happen.

## Supply chain trust

Three images pinned to `tag@sha256:<digest>` as interpolation defaults in the compose `x-images` block:

- [`deluan/navidrome`](https://hub.docker.com/r/deluan/navidrome): the server
- [`traefik`](https://hub.docker.com/_/traefik): reverse proxy
- [`alpine`](https://hub.docker.com/_/alpine): the backups sidecar, which needs tar and nothing else

`git pull` alone delivers the tested combination; an `*_IMAGE_TAG` variable in `.env` overrides deliberately.

Two override levels exist per image. `<PREFIX>_IMAGE_VERSION` in `.env` swaps only the version of that image (Compose then pulls the tag, without a digest) and leaves every other pin as tested; `<PREFIX>_IMAGE_TAG` replaces the whole reference, digest included. Nested defaults need Docker Compose v2.5 or newer (2022).

The daily `check-pin-freshness` CI job re-resolves each pin against its registry and compares the pinned Navidrome and Traefik versions against the latest upstream releases. GitHub Actions are pinned by commit SHA; Dependabot keeps those fresh.

## Running as a non-root uid

Upstream recommends running as the owner of the music library. This template does not do that by default, and the reason is worth stating rather than hiding: the image's `/data` is owned by root, so a `user:` override on a fresh **named volume** produces a container that cannot write its own database. Shipping that as a default would mean shipping a stack that does not start.

It is the right thing to do when you bind-mount `/data` on a host directory you own — `.env.example` carries the override file to add and the `chown` that has to come first. In the meantime the container runs with `cap_drop: ALL`, which on a service that is one Go binary serving HTTP is worth more than the uid change would be.

## Production checklist

- [ ] **Create your account immediately after deploy**, before anyone else can.
- [ ] **Point `NAVIDROME_MUSIC_PATH` at the real collection** and confirm it is mounted read-only.
- [ ] **Regenerate the Traefik dashboard hash.** The one in `.env.example` is a placeholder.
- [ ] **Host-mount the backup volume.** By default the archives land in a named volume: if the host dies, they die with it.
- [ ] **Back up the music separately.** It is not in these archives and cannot sensibly be.
- [ ] **Decide about external services.** Artwork and metadata lookups are on by default; `NAVIDROME_ENABLE_EXTERNAL_SERVICES=false` stops the container making any outbound request at all.

## Backups and restore

The `backups` container archives `/data` on a loop — a 30-minute warm-up, a 24-hour interval, 7-day retention, all overridable in `.env`.

Each archive is written to a `.partial` name, **read back with `tar -tzf`**, and only then renamed. The read-back is not decoration: BusyBox tar, which is what an alpine image ships, returns exit code 1 both for "a file changed while I was reading it" and for "I could not write the output at all". Trusting the exit code alone renames an empty file into place and calls it a backup. This loop refuses to.

Restore with the interactive script:

```bash
chmod +x ./*.sh
./navidrome-restore-data.sh
```

It stops the server first: the database is SQLite and is written on every scrobble and every scan. Play counts and playlists are back immediately afterwards; if tracks are missing, the archive predates them and a scan brings them in.

Navidrome also has a backup command of its own, which writes into the data directory rather than out of it: `docker compose -p navidrome exec navidrome navidrome backup create`. That is a database snapshot, and this loop archives it along with everything else.

## Resource limits

Every service carries memory and CPU limits plus reservations as compose-level defaults: the same values CI boots the stack under. What moves these numbers is the first full scan of a large library and on-the-fly transcoding, not steady playback — a server streaming an already-encoded file to a phone is doing almost nothing. Override any of them in `.env` and the override survives every `git pull`. If a service is OOM-killed, `docker inspect <container> --format '{{.State.OOMKilled}}'` says so.

## Container hardening

Every service runs with `security_opt: no-new-privileges:true` and `cap_drop: [ALL]`; Traefik adds back `NET_BIND_SERVICE` and the backups sidecar the three it needs to write archives it owns. Navidrome adds back nothing at all: it is one Go binary that serves HTTP and reads files, and it needs no Linux capability.

## Testing

The [Deployment Verification](https://github.com/heyvaldemar/navidrome-traefik-letsencrypt-docker-compose/actions/workflows/deployment-verification.yml?query=branch%3Amain) workflow runs on every push, pull request, and every day at 06:00 UTC: shellcheck and actionlint, Trivy scans of all three pinned images, the daily freshness check, and a deploy job that boots the stack with ephemeral credentials and then requires the server to answer through Traefik, the Subsonic API to answer in its own protocol, the music mount to refuse a write, an archive to be produced and to carry the database by name, eight backup and restore scenarios to pass, and Navidrome to come back up on the data directory the restore test replaced underneath it.

### Backup and restore, proven

`tests/e2e-backup-restore.sh` runs against the live stack and is what CI executes after the smoke test. Three scenarios carry the weight. The archive must contain `data/navidrome.db` by name, not merely a directory — everything else under `/data` is a cache that rebuilds itself, so an archive missing that one file restores into a server that starts cleanly and has forgotten every listener. The restore roundtrip writes a file, waits for the archive that contains it, deletes it, restores, and asserts it came back. The failure test blocks the destination the loop is about to write to and asserts the loop says FAILED and leaves nothing behind that is named like a backup and does not open.

```bash
chmod +x tests/e2e-backup-restore.sh
./tests/e2e-backup-restore.sh
```

Run it on a staging copy, not on production: it stops the server and empties the data directory.

## Security notes

- Credentials are read from `.env` at deploy time; `.env` is gitignored and compose fails fast on missing required variables.
- The music collection is mounted read-only, and CI proves it by failing to write to it.
- The first account created through the web interface becomes the administrator, and there is no gate in front of that form.

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** · Docker Captain · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
