# copyparty per Home Assistant

App (add-on) di Home Assistant che fa girare
[copyparty](https://github.com/9001/copyparty) sull'host di Home Assistant ed
espone le cartelle di sempre — le stesse che pubblica l'app ufficiale **Samba
share** — con un pannello nella sidebar e una porta HTTP per reverse proxy o
tunnel.

| | |
|---|---|
| Cartelle | `config`, `share`, `media`, `backup`, `ssl`, `addons`, `addon_configs` |
| Sidebar | sì, tramite Supervisor ingress |
| Porta diretta | `3923` (interfaccia web + WebDAV) |
| Accesso | un account copyparty, obbligatorio |
| Architetture | `amd64`, `aarch64` |

## Installazione

1. Impostazioni → App → **App store** → tre puntini → **Repository**
2. Aggiungi `https://github.com/cchrkk/ha-copyparty`
3. Installa **copyparty**, imposta una password, avvia.

## Perché due processi

copyparty lega il cookie di sessione al percorso indicato da `--rp-loc`. Il
pannello della sidebar sta sotto `/api/hassio_ingress/<token>`: un solo processo
montato lì servirebbe bene il pannello ma non terrebbe la sessione sulla porta
3923 (il cookie non verrebbe mai inviato). Due worker, uno per punto d'ingresso e
ognuno con la propria cartella di stato, tengono in piedi entrambi con URL puliti
invece che con un prefisso. Vedi `copyparty/run.sh`.

## Licenza

MIT per il packaging. copyparty è AFL-3.0 e viene installato da PyPI in fase di
build, non è incluso qui.
