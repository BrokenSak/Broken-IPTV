<div align="center">

<img src="assets/icon/app_icon.png" width="96" alt="Icona di Broken IPTV">

# Broken IPTV

**Player IPTV per Android e Windows da un unico codebase Flutter.**<br>
Pannelli Xtream Codes e playlist M3U + XMLTV, con EPG, VOD e serie.

[![Release](https://img.shields.io/github/v/release/BrokenSak/Broken-IPTV?label=release&color=2ea44f)](https://github.com/BrokenSak/Broken-IPTV/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Piattaforme](https://img.shields.io/badge/piattaforme-Android%20%C2%B7%20Windows-555555)](#download)

[Download](#download) · [Caratteristiche](#caratteristiche) · [Build dal sorgente](#build-dal-sorgente)

</div>

> [!IMPORTANT]
> Broken IPTV è un **player generico**: non include né distribuisce contenuti, canali o playlist.
> Le credenziali del proprio abbonamento si inseriscono all'avvio e restano solo sul dispositivo.

## Download

Dalla [pagina delle release](https://github.com/BrokenSak/Broken-IPTV/releases/latest):

| Piattaforma | File | Note |
|---|---|---|
| **Android** — telefono, tablet e TV | `BrokenIPTV.apk` | App sideload: Play Protect può chiedere conferma («Più dettagli» → «Installa comunque») |
| **Windows** 10/11 | `BrokenIPTV.exe` | Installer per utente, nessun privilegio di amministratore |

## Caratteristiche

### 📺 Live TV
- Canali per categoria, con **EPG** sotto la lista e offset orario configurabile
- Overlay con l'elenco dei canali direttamente nel player
- Guida completa scaricata in una sola richiesta (`xmltv.php`), con cache locale per profilo

### 🎬 Film e serie
- Cataloghi VOD con dettaglio, descrizione e stagioni
- **Continua a guardare** e **Ultimi aggiunti** sempre a portata di mano
- Ripresa della riproduzione dal punto in cui si era rimasti

### 🔍 Esperienza
- **Ricerca globale** su canali, film e serie, con anteprime
- **Preferiti** per ogni tipo di contenuto
- Gruppo **Adulti** collassabile: nascosto di default ed escluso dalle viste aggregate
- Tema scuro «liquid glass», schermo intero, **multi-playlist**

### ⚙️ Player
- Motore `media_kit` (libmpv): sottotitoli, scelta della lingua audio, rapporto d'aspetto, velocità e salti configurabili
- Auto-riconnessione e fallback automatico `.ts`/`.m3u8`
- Pannello account (scadenza, connessioni, server) e speed test integrato

## Stack

Flutter · Riverpod · go_router · media_kit · Hive CE · dio · flutter_secure_storage · window_manager

## Build dal sorgente

Prerequisiti: [Flutter](https://docs.flutter.dev/get-started/install) 3.x su canale stable. Per Android servono
Android SDK e JDK; per l'installer Windows serve [Inno Setup 6](https://jrsoftware.org/isinfo.php).

```bash
flutter pub get
flutter analyze && flutter test

# Windows — EXE in build/windows/x64/runner/Release/
flutter build windows --release

# Installer Windows (dopo la build release) — output: installer/output/BrokenIPTV.exe
ISCC installer/broken_iptv.iss

# Android — APK in build/app/outputs/flutter-apk/app-release.apk
flutter build apk --release
```

> [!NOTE]
> La release Android è firmata con un keystore locale: `android/key.properties` e il file `.jks`
> **non sono nel repository**. Senza di essi si può comunque buildare e firmare con le proprie chiavi.

## Licenza

Progetto a uso personale, distribuito senza alcuna garanzia.
