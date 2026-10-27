# copyparty for Home Assistant

[copyparty](https://github.com/9001/copyparty) is a portable file server: a web
UI to browse, upload, download, move and delete files, with resumable uploads,
WebDAV, thumbnails and search.

This app (formerly "add-on") runs it on the Home Assistant host and exposes the
same folders you see through the **Samba share** app, so you can reach them from
the Home Assistant sidebar and from any browser.

## Installation

1. Settings → Apps → **App store** (three dots) → **Repositories**
2. Add `https://github.com/cchrkk/ha-copyparty`
3. Install **copyparty**, set a **password**, start it.

The app appears in the sidebar as **copyparty**.

## Folders

Each folder is a top-level entry in the web UI, with the same name as the Samba
share:

| Name | Path inside Home Assistant |
|---|---|
| `config` | `/config` |
| `share` | `/share` |
| `media` | `/media` |
| `backup` | `/backup` |
| `ssl` | `/ssl` |
| `addons` | `/addons` |
| `addon_configs` | `/addon_configs` |

Remove a name from the **Folders** option to stop exposing it.

## Options

| Option | Description |
|---|---|
| `username` | copyparty account (default `chrk`) |
| `password` | password for that account — required, the app refuses to start without it |
| `folders` | which folders to expose |
| `permissions` | `rw` = read/write/move/delete, `r` = read-only |
| `index` | build the file index at startup (off by default) |
| `extra_config` | raw copyparty configuration appended to the generated file |

`permissions` applies to every folder. For a different mix, leave a folder out
here and declare it in `extra_config`, for example:

```
[/backup]
  /backup
  accs:
    r: chrk
```

## Network

Two copyparty workers run on the same folders, with nginx in front of the one
that serves the sidebar:

| Port | Purpose |
|---|---|
| `3923` | plain web UI and WebDAV, for the LAN or a reverse proxy / tunnel |
| `3929` | internal, the port Home Assistant ingress talks to |
| `3930` | internal, copyparty mounted under the ingress path |

They are separate processes on purpose: copyparty scopes its login cookie to
the path it is mounted under, so a single process mounted under the ingress path
could not keep a session on port 3923. Each worker keeps its own state directory
(database, thumbnails, sessions); only the files are shared.

nginx is there because Home Assistant strips the ingress prefix before
forwarding a request and announces it only in the `X-Ingress-Path` header, which
copyparty does not read: without nginx the panel loads HTML whose links point at
Home Assistant itself.

The web UI answers both `http://` and `https://` on port 3923. If you drop a
PEM with the key and the certificate chain in `/ssl/copyparty.pem` (the Home
Assistant `ssl` folder), it is used for HTTPS, so a certificate signed by a CA
your browser trusts gives no warning on the LAN.

### Publishing it

Point a Cloudflare tunnel (or any reverse proxy) at
`http://<home-assistant-ip>:3923`.

The generated configuration already tells copyparty to read the client address
from `X-Forwarded-For`, trusting private networks only, so bans hit the real
client instead of the proxy. If your proxy sets `CF-Connecting-IP` instead and
you remove the header, add to `extra_config`:

```
[global]
  xff-hdr=cf-connecting-ip
  xff-src=any
```

### WebDAV

`http://<home-assistant-ip>:3923/dav/` with the same username and password.
Windows Explorer, macOS Finder, rclone, Joplin and most sync clients work.

## Notes

- The account is the only thing standing between the network and `/config`,
  `/ssl` and `/backup`: use a real password and keep the far side behind
  authentication (Cloudflare Access, a VPN, or nothing public at all).
- `no-robots` is enabled, but crawlers only respect it if they feel like it.
- Leave `index` off unless you want fast listings on very large folders: it
  costs a stat per file at every start.
- Uninstalling the app does **not** touch your files.

## Credits

copyparty is by [9001](https://github.com/9001/copyparty), licensed AFL-3.0.
This packaging is MIT; it installs copyparty from PyPI at build time.
