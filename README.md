# RadMan

> RadMan is still in active development, so please make a full backup before using it with your radio and use it at your own risk, as unfinished features could still lead to lost data, changed settings, or other unexpected behavior.

### RadMan is a native macOS radio memory and activity manager focused on the Radtel RT-950 Pro.

The current backup file is a RadMan JSON backup for RT-950 Pro data. It is a native standalone workflow, but it is not yet the vendor CPS binary format.
The current USB workflow can now identify a live RT-950 Pro, download its native clone image directly over USB, decode it into channels and device summaries, preserve managed backups, and write updated channel memories back safely without CHIRP.
The current CPS `.dat` support is intentionally conservative: RadMan imports explicit zone-name arrays when they are clearly present, and it detects grouped/zoned CPS files without pretending to write unsupported metadata back into the live radio clone.

### Legacy CLI

The older Python CLI remains in [src/horizon_radio](/Users/jsmith/Documents/Projects/Core/Horizon/src/horizon_radio) for reference and migration support, but the primary direction is now the native macOS app.
