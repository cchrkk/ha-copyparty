<p align="center">
  <img src="copyparty/icon.png" width="128" height="128" alt="copyparty">
</p>

# copyparty for Home Assistant

A Home Assistant app (add-on) that runs [copyparty](https://github.com/9001/copyparty)
on the Home Assistant host and exposes the usual folders — the same ones the
official **Samba share** app publishes — with a sidebar panel and a plain HTTP
port for a reverse proxy or tunnel.

| | |
|---|---|
| Folders | `config`, `share`, `media`, `backup`, `ssl`, `addons`, `addon_configs` |
| Sidebar | yes, through Supervisor ingress |
| Direct port | `3923` (web UI + WebDAV) |
| Login | one copyparty account, required |
| Architectures | `amd64`, `aarch64` |

## Install

1. Settings → Apps → **App store** → three dots → **Repositories**
2. Add `https://github.com/cchrkk/ha-copyparty`
3. Install **copyparty**, set a password, start it.

Italian version of this page: [README.it.md](README.it.md).

## This repository

```
repository.yaml          # makes the repo a Home Assistant app store
copyparty/
  config.yaml            # app metadata, options, ingress, port, folder mounts
  Dockerfile             # python:3.13-alpine + copyparty pin + ffmpeg
  run.sh                 # generates the copyparty config and supervises the workers
  DOCS.md                # the app's "Documentation" tab
  CHANGELOG.md
  translations/          # option labels in English and Italian
  icon.png logo.png
make-icons.ps1           # regenerates icon.png and logo.png from the upstream logo
scripts/                 # bump-copyparty.py, used by the release workflow
.github/workflows/       # daily check of PyPI: new copyparty release -> new app version
```

Releases are mostly automatic: `.github/workflows/bump-copyparty.yml` asks PyPI
once a day, and when a newer copyparty exists it moves the pin in the
`Dockerfile`, bumps `version:` in `copyparty/config.yaml` (the field Home
Assistant watches to rebuild the image) and adds a `CHANGELOG.md` line, then
commits. PyPI has no webhook, so it is polling; `workflow_dispatch` runs it by
hand.

To bump by hand: raise `version:` in `copyparty/config.yaml` (and the
`COPYPARTY_VERSION` arg if needed) and push.

## Why two processes

copyparty scopes its login cookie to the path given by `--rp-loc`. The sidebar
panel is mounted under `/api/hassio_ingress/<token>`, so a single process
mounted there would serve the panel fine but could not keep a session on port
3923 (the cookie would never be sent there). Two workers — one per entry point,
each with its own state directory — keeps both working with clean URLs instead
of ugly prefixed ones. See `copyparty/run.sh`.

## Licence

MIT for the packaging. copyparty itself is AFL-3.0 and is installed from PyPI at
build time, not bundled here.
