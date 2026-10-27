#!/usr/bin/env python3
"""Aggiorna il pin di copyparty quando su PyPI esce una release nuova.

Tocca tre file, sempre insieme:
  copyparty/Dockerfile   ARG COPYPARTY_VERSION
  copyparty/config.yaml  version (Home Assistant ricostruisce solo se cambia)
  copyparty/CHANGELOG.md una riga in testa

Nessuna dipendenza oltre la stdlib. Esce 0 anche quando non c'e' niente da fare;
lo script stampa la nuova versione, e la workflow la usa come messaggio di commit.
"""
import datetime
import json
import pathlib
import re
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCKERFILE = ROOT / "copyparty" / "Dockerfile"
CONFIG = ROOT / "copyparty" / "config.yaml"
CHANGELOG = ROOT / "copyparty" / "CHANGELOG.md"


def key(version):
    return tuple(int(x) for x in re.findall(r"\d+", version))


def latest_on_pypi():
    with urllib.request.urlopen("https://pypi.org/pypi/copyparty/json", timeout=30) as fh:
        return json.load(fh)["info"]["version"]


dockerfile = DOCKERFILE.read_text(encoding="utf-8")
match = re.search(r"^ARG COPYPARTY_VERSION=(\S+)$", dockerfile, re.M)
if not match:
    sys.exit("ARG COPYPARTY_VERSION non trovato nel Dockerfile")
current = match.group(1)

latest = latest_on_pypi()
if key(latest) <= key(current):
    print("copyparty %s e' gia' l'ultima (PyPI: %s)" % (current, latest), file=sys.stderr)
    sys.exit(0)

dockerfile = dockerfile.replace(
    "ARG COPYPARTY_VERSION=%s" % current, "ARG COPYPARTY_VERSION=%s" % latest, 1)
DOCKERFILE.write_text(dockerfile, encoding="utf-8", newline="\n")

config = CONFIG.read_text(encoding="utf-8")
addon = re.search(r'^version: "(\d+)\.(\d+)\.(\d+)"$', config, re.M)
if not addon:
    sys.exit('campo version non trovato in config.yaml')
new_addon = "%s.%s.%d" % (addon.group(1), addon.group(2), int(addon.group(3)) + 1)
config = config.replace(addon.group(0), 'version: "%s"' % new_addon, 1)
CONFIG.write_text(config, encoding="utf-8", newline="\n")

changelog = CHANGELOG.read_text(encoding="utf-8")
entry = "## %s\n\n- copyparty %s (upstream release, %s).\n\n" % (
    new_addon, latest, datetime.date.today().isoformat())
CHANGELOG.write_text(entry + changelog, encoding="utf-8", newline="\n")

print("copyparty %s -> %s (app %s)" % (current, latest, new_addon))
