## 1.0.8

- If `/ssl/copyparty.pem` exists (key + certificate chain), the worker on port
  3923 serves HTTPS with it, so a certificate signed by a local CA means no
  browser warning on the LAN.

## 1.0.7

- Fix: a missing newline in `run.sh` broke the shell (`syntax error: unexpected
  word`) and the app kept restarting.

## 1.0.6

- New `index` option, **off by default**: `e2dsa` costs a stat per file at every
  start and a full scan the first time, which on `/share` or `/media` is a lot
  of I/O. Browsing, uploads, downloads and thumbnails work without it.

## 1.0.5

- Fix: the sidebar panel is a sandboxed iframe, so the browser sends
  `Origin: null` and copyparty answered *"rejected by cors-check"* on login.
  The worker behind ingress now accepts that origin; the direct worker still
  validates it.
- Fix: `share` and `ssl` had dropped out of the app options.

## 1.0.4

- Fix: after logging in from the sidebar panel copyparty answered
  *"rejected by cors-check"*. It compares the request's `Origin` with the
  protocol it sees, and nginx talks plain HTTP to it while the browser is on
  HTTPS. nginx now sends `X-Forwarded-Proto`, derived from the `Origin` itself.

## 1.0.3

- Fix: the sidebar panel failed with *"cannot load util.js"*. Home Assistant
  strips the ingress prefix before forwarding and only announces it in the
  `X-Ingress-Path` header, which copyparty does not read, so every URL it
  emitted pointed at Home Assistant itself. A small nginx now sits on the
  ingress port and puts the prefix back.

## 1.0.2

- Fix: the log lines from `run.sh` were written to stdout while the generated
  copyparty config was being built, so they ended up inside the config file.
- Fix: Supervisor mounts the renamed app folders at `/local_apps` and
  `/app_configs`; the script now tries the new paths before the legacy
  `/addons` and `/addon_configs`.

## 1.0.1

- Build the image straight from `python:3.13-alpine`: the `build.yaml` base
  image was rejected by Supervisor (`python:3.13-alpine` has no namespace, so it
  fell back to the Home Assistant base image, which has no `pip`).

## 1.0.0

- First release.
- copyparty 1.20.26 with the Home Assistant folders exposed under the Samba
  share names (config, share, media, backup, ssl, addons, addon_configs).
- Sidebar panel through Supervisor ingress.
- Port 3923 for the LAN and for a reverse proxy, with `X-Forwarded-For` handling
  for Cloudflare.
- Per-folder read-only or read-write access, optional raw copyparty config.
