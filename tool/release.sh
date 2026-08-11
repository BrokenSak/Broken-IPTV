#!/usr/bin/env bash
#
# Due canali, un comando.
#
#   tool/release.sh beta ["note"]   costruisce APK+EXE e li carica SOLO sulla
#                                   pre-release `beta`. version.json NON si
#                                   tocca: nessun dispositivo riceve niente.
#   tool/release.sh promuovi "note" prende gli asset GIA' PROVATI dalla beta,
#                                   li copia sulla release stabile e alza
#                                   version.json (poi push).
#   tool/release.sh stato           dice a che punto sono i due canali.
#
# Perche' `promuovi` non ricostruisce: il file che va a tutti dev'essere lo
# STESSO che hai provato, byte per byte. Ricostruire vorrebbe dire pubblicare
# un binario che nessuno ha mai aperto. Per lo stesso motivo versione e build
# di version.json vengono LETTE dall'APK scaricata, non ridigitate: e' l'unico
# modo di non poterle sbagliare.
#
# ⚠️ L'ordine di pubblicazione e' vincolato: prima gli asset, poi version.json.
# Al contrario, un'app che si aggiorna nella finestra intermedia vede il build
# nuovo e scarica ancora i file vecchi.
#
# ⚠️ La pre-release e' privata solo nel senso che nessuno ci viene mandato: il
# repo e' pubblico, quindi chi conosce il link puo' scaricarla. Non e' un
# segreto, e' un canale silenzioso.
set -euo pipefail

cd "$(dirname "$0")/.."

REPO_TAG_STABILE="v1.0.0"
REPO_TAG_BETA="beta"
APK_LOCALE="build/app/outputs/flutter-apk/app-release.apk"
EXE_LOCALE="installer/output/BrokenIPTV.exe"
AAPT="/c/Android/build-tools/35.0.0/aapt2.exe"
ISCC="/c/Users/aless/AppData/Local/Programs/Inno Setup 6/ISCC.exe"

export ANDROID_HOME=/c/Android
export PATH="/c/src/flutter/bin:/c/Android/platform-tools:$PATH"

msg() { printf '\n\033[1m%s\033[0m\n' "$*"; }

versione_apk() { "$AAPT" dump badging "$1" 2>/dev/null | head -1; }

comando_beta() {
  msg "1/5  Controlli (analyze + test): niente build su codice rotto."
  flutter analyze
  rm -rf build/unit_test_assets 2>/dev/null || true
  flutter test

  msg "2/5  APK"
  # Il lock su build\app torna a ogni tanto: cancellare l'albero e' il rimedio
  # documentato (§4), `flutter clean` da solo non basta.
  powershell -Command "Remove-Item -Recurse -Force build\\app -ErrorAction SilentlyContinue" 2>/dev/null || true
  flutter build apk --release

  msg "3/5  Windows + installer"
  powershell -Command "Get-Process | Where-Object {\$_.Name -match 'broken_iptv|BrokenIPTV'} | Stop-Process -Force -ErrorAction SilentlyContinue" 2>/dev/null || true
  flutter build windows --release
  "$ISCC" installer/broken_iptv.iss >/dev/null

  msg "4/5  Copia in 'app pronte/'"
  mkdir -p "app pronte"
  cp "$APK_LOCALE" "app pronte/BrokenIPTV.apk"
  cp "$EXE_LOCALE" "app pronte/BrokenIPTV.exe"
  versione_apk "app pronte/BrokenIPTV.apk"

  msg "5/5  Carico sulla PRE-RELEASE (nessuno la riceve automaticamente)"
  gh release upload "$REPO_TAG_BETA" \
    "app pronte/BrokenIPTV.apk" "app pronte/BrokenIPTV.exe" --clobber
  if [ $# -gt 0 ]; then
    gh release edit "$REPO_TAG_BETA" --notes "$1"
  fi

  cat <<FINE

Fatto. Da provare a mano:
  Firestick   adb install -r "app pronte/BrokenIPTV.apk"
  Windows     lancia "app pronte/BrokenIPTV.exe"
  Telefono    https://github.com/BrokenSak/Broken-IPTV/releases/download/$REPO_TAG_BETA/BrokenIPTV.apk

version.json NON e' stato toccato: gli altri dispositivi non vedono niente.
Quando sei convinto:  tool/release.sh promuovi "cosa cambia, in italiano"
FINE
}

comando_promuovi() {
  if [ $# -lt 1 ]; then
    echo "Servono le note per gli utenti: tool/release.sh promuovi \"testo\"" >&2
    exit 1
  fi
  local note="$1"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  msg "1/4  Scarico dalla beta gli asset gia' provati (non ricostruisco)"
  gh release download "$REPO_TAG_BETA" --dir "$tmp" \
    --pattern 'BrokenIPTV.apk' --pattern 'BrokenIPTV.exe' --clobber

  local badging build versione
  badging="$(versione_apk "$tmp/BrokenIPTV.apk")"
  build="$(sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p" <<<"$badging")"
  versione="$(sed -n "s/.*versionName='\([^']*\)'.*/\1/p" <<<"$badging")"
  [ -n "$build" ] && [ -n "$versione" ] || { echo "APK illeggibile: $badging" >&2; exit 1; }
  echo "  in promozione: $versione (build $build)"

  local build_online
  build_online="$(python -c "import json,urllib.request;print(json.load(urllib.request.urlopen('https://raw.githubusercontent.com/BrokenSak/Broken-IPTV/main/version.json'))['build'])")"
  if [ "$build" -le "$build_online" ]; then
    echo "Il build online e' gia' $build_online: questa beta non e' piu' recente." >&2
    exit 1
  fi

  msg "2/4  Asset sulla release stabile (PRIMA di version.json)"
  gh release upload "$REPO_TAG_STABILE" \
    "$tmp/BrokenIPTV.apk" "$tmp/BrokenIPTV.exe" --clobber

  msg "3/4  version.json"
  python - "$build" "$versione" "$note" <<'PY'
import json, sys
build, versione, note = int(sys.argv[1]), sys.argv[2], sys.argv[3]
with open('version.json', encoding='utf-8') as f:
    d = json.load(f)
d['build'], d['version'], d['notes'] = build, versione, note
with open('version.json', 'w', encoding='utf-8', newline='\n') as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY

  msg "4/4  Commit e push"
  git add version.json
  git commit -m "chore(release): $versione+$build in stabile

Promossa dalla beta senza ricostruire: il binario e' lo stesso provato."
  git push

  echo
  echo "Pubblicata. Gli altri dispositivi la vedranno al prossimo avvio."
}

comando_stato() {
  local online
  online="$(curl -s https://raw.githubusercontent.com/BrokenSak/Broken-IPTV/main/version.json)"
  echo "STABILE (quella che ricevono tutti)"
  python -c "import json,sys;d=json.loads(sys.stdin.read());print('  '+d['version']+'  build '+str(d['build']))" <<<"$online"
  echo "BETA (solo installazione a mano)"
  local tmp; tmp="$(mktemp -d)"
  if gh release download "$REPO_TAG_BETA" --dir "$tmp" --pattern 'BrokenIPTV.apk' --clobber >/dev/null 2>&1; then
    echo "  $(versione_apk "$tmp/BrokenIPTV.apk" | sed "s/.*versionName='\([^']*\)'.*/\1/") (dall'APK caricata)"
  else
    echo "  nessuna"
  fi
  rm -rf "$tmp"
  echo "In lavorazione qui:"
  echo "  $(grep '^version:' pubspec.yaml)"
}

case "${1:-}" in
  beta)     shift; comando_beta "$@" ;;
  promuovi) shift; comando_promuovi "$@" ;;
  stato)    comando_stato ;;
  *)
    sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
