# Broken IPTV

App IPTV in **Flutter** per **Android** (telefono/tablet e TV con telecomando) e **Windows**,
compatibile con pannelli **Xtream Codes** e playlist **M3U + XMLTV**. Un solo codebase,
due deliverable: APK Android e installer Windows.

> È un **player generico**: non include né distribuisce alcun contenuto, canale o playlist.
> Le credenziali del proprio abbonamento si inseriscono a runtime e restano sul dispositivo.

## Caratteristiche
- **Live TV** con categorie, EPG sotto i canali (con offset `+N`) e overlay lista canali nel player.
- **Film e Serie** (VOD) con dettaglio, descrizione, stagioni, "Continua a guardare" e "Ultimi aggiunti".
- **Ricerca** globale cross-catalogo con anteprime.
- **Preferiti** per canali, film e serie.
- Categorie fisse: Continua a guardare · Preferiti · Tutti · Ultimi aggiunti.
- Gruppo **Adulti** collassabile (contenuti per adulti raggruppati e nascosti di default, esclusi dalle viste aggregate).
- **Player** `media_kit`: sottotitoli, selezione **lingua audio** (default italiano), rapporto d'aspetto,
  velocità, salti configurabili, ripresa da dove si era rimasti, auto-riconnessione e fallback `.ts`/`.m3u8`.
- **Pannello account** (scadenza, connessioni, server) e **speed test** (fast.com).
- Tema scuro "liquid glass", schermo intero, multi-playlist.

## Stack
Flutter · Riverpod · go_router · media_kit · hive_ce · dio · flutter_secure_storage · window_manager.

## Build
Prerequisiti e dettagli completi in [`HANDOFF.md`](HANDOFF.md).

```bash
flutter pub get
flutter analyze && flutter test

# Windows
flutter build windows --release

# Android (APK firmata: richiede android/key.properties + keystore, non inclusi nel repo)
flutter build apk --release
```

> **Firma Android:** `android/key.properties` e il keystore `.jks` **non** sono nel repository
> (esclusi da `.gitignore`). Per produrre una release firmata vanno forniti localmente.

## Licenza
Uso personale. Nessuna garanzia.
