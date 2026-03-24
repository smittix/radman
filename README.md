# RadMan

RadMan is a native macOS radio memory and activity manager focused on the Radtel RT-950 Pro.

The current native direction is:

- first-class support for `Radtel RT-950 Pro`
- native standalone workflows over time, starting with data/schema ownership
- CHIRP kept as an optional compatibility layer rather than a core dependency

The app is designed around your RT-950 PRO sample CSV and keeps the full memory schema available for editing, importing, and exporting:

- `Location`
- `Name`
- `Frequency`
- `Duplex`
- `Offset`
- `Tone`
- `rToneFreq`
- `cToneFreq`
- `DtcsCode`
- `DtcsPolarity`
- `RxDtcsCode`
- `CrossMode`
- `Mode`
- `TStep`
- `Skip`
- `Power`
- `Comment`
- `URCALL`
- `RPT1CALL`
- `RPT2CALL`
- `DVCODE`

## What Is In The Repo Now

- A native SwiftUI macOS app scaffold in [Sources/HorizonRFMac](/Users/jsmith/Documents/Projects/Core/Horizon/Sources/HorizonRFMac)
- Persistent local storage for radios, channels, backups, and device state
- CHIRP-style CSV import/export for channels
- RT-950 Pro support metadata and native-driver scaffolding
- RadMan-owned RT-950 Pro backup import/export
- RT-950 Pro USB serial discovery, native handshake, clone download, clone upload, and managed backup workflows
- RT-950 Pro zone management with local custom names and CPS `.dat` zone-name import
- A sidebar UI with views for Dashboard, Device, Channels, Radios, and Tools
- Build scripts for wrapping the SwiftPM executable into a `.app` and then a `.dmg`

The native app entrypoint is [HorizonRFMacApp.swift](/Users/jsmith/Documents/Projects/Core/Horizon/Sources/HorizonRFMac/HorizonRFMacApp.swift), and the channel schema lives in [AppModels.swift](/Users/jsmith/Documents/Projects/Core/Horizon/Sources/HorizonRFMac/Models/AppModels.swift).

## Project Layout

- [Package.swift](/Users/jsmith/Documents/Projects/Core/Horizon/Package.swift): Swift package manifest for the macOS app target
- [Sources/HorizonRFMac/Services/CHIRPCSVService.swift](/Users/jsmith/Documents/Projects/Core/Horizon/Sources/HorizonRFMac/Services/CHIRPCSVService.swift): imports and exports CHIRP-style CSV files
- [Sources/HorizonRFMac/Services/AppStore.swift](/Users/jsmith/Documents/Projects/Core/Horizon/Sources/HorizonRFMac/Services/AppStore.swift): JSON-backed persistence for app data
- [Sources/HorizonRFMac/Views/ChannelsView.swift](/Users/jsmith/Documents/Projects/Core/Horizon/Sources/HorizonRFMac/Views/ChannelsView.swift): full channel editor UI
- [scripts/build-macos-app.sh](/Users/jsmith/Documents/Projects/Core/Horizon/scripts/build-macos-app.sh): creates a `.app` bundle from the SwiftPM release build
- [scripts/make-dmg.sh](/Users/jsmith/Documents/Projects/Core/Horizon/scripts/make-dmg.sh): creates a `.dmg` containing the app bundle

## Build Notes

With Xcode installed and selected, the intended local build flow is:

```bash
cd /Users/jsmith/Documents/Projects/Core/Horizon
swift build -c release
scripts/build-macos-app.sh
scripts/make-dmg.sh
```

For proper outside-App-Store distribution, the eventual next step is:

1. Sign the `.app` with a Developer ID certificate.
2. Notarize the app or dmg with Apple.
3. Ship the notarized `.dmg`.

## Current Native App Features

- Manage radio profiles with built-in radio model metadata, native workflow preferences, legacy CHIRP IDs, serial ports, and last native clone state
- Edit the full CHIRP-style channel memory schema
- Import channel memories from a sample CSV
- Export channel memories back to CHIRP-style CSV
- Import and export RT-950 Pro backup files without CHIRP
- Import named RT-950 Pro zones from supported CPS `.dat` files
- Read a live RT-950 Pro clone into RadMan over USB
- Decode VFO/function/DTMF/APRS summaries in the Device view
- Edit core radio settings in the Device view with safe full-clone programming
- Save and restore native RT-950 Pro clone images
- Upload current RadMan channel memories back to the RT-950 Pro over USB
- See local and UTC time plus native-support roadmap information in the Tools view

## Standalone Roadmap

The standalone plan for `Radtel RT-950 Pro` is:

1. Keep the full RT-950 Pro memory schema native inside the app.
2. Ship RadMan-owned RT-950 Pro backup files so RadMan can operate without CHIRP today.
3. Add RT-950 Pro CPS/backup compatibility where the vendor format is understood well enough.
4. Expand editable support from channel memories into more device settings blocks.
5. Investigate Bluetooth workflows and any discoverable live-control protocol.
6. Keep CSV export for interop, migration, and sharing.

The current backup file is a RadMan JSON backup for RT-950 Pro data. It is a native standalone workflow, but it is not yet the vendor CPS binary format.
The current USB workflow can now identify a live RT-950 Pro, download its native clone image directly over USB, decode it into channels and device summaries, preserve managed backups, and write updated channel memories back safely without CHIRP.
The current CPS `.dat` support is intentionally conservative: RadMan imports explicit zone-name arrays when they are clearly present, and it detects grouped/zoned CPS files without pretending to write unsupported metadata back into the live radio clone.

## Legacy CLI

The older Python CLI remains in [src/horizon_radio](/Users/jsmith/Documents/Projects/Core/Horizon/src/horizon_radio) for reference and migration support, but the primary direction is now the native macOS app.
