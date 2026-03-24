from __future__ import annotations

import csv
import unittest
from pathlib import Path


ROOT = Path("/Users/jsmith/Documents/Projects/Core/Horizon")
SAMPLE_CSV = Path("/Users/jsmith/Documents/Hobbies/RF/Handheld/Freq_Files/RT-950PRO_JS.csv")

EXPECTED_HEADERS = [
    "Location",
    "Name",
    "Frequency",
    "Duplex",
    "Offset",
    "Tone",
    "rToneFreq",
    "cToneFreq",
    "DtcsCode",
    "DtcsPolarity",
    "RxDtcsCode",
    "CrossMode",
    "Mode",
    "TStep",
    "Skip",
    "Power",
    "Comment",
    "URCALL",
    "RPT1CALL",
    "RPT2CALL",
    "DVCODE",
]


class MacPivotTests(unittest.TestCase):
    def test_sample_csv_matches_expected_chirp_schema(self) -> None:
        self.assertTrue(SAMPLE_CSV.exists(), f"Sample CSV not found: {SAMPLE_CSV}")
        with SAMPLE_CSV.open(newline="", encoding="utf-8-sig") as handle:
            reader = csv.reader(handle)
            header = next(reader)
        self.assertEqual(header, EXPECTED_HEADERS)

    def test_native_macos_scaffold_files_exist(self) -> None:
        expected_files = [
            ROOT / "Package.swift",
            ROOT / "Sources/HorizonRFMac/HorizonRFMacApp.swift",
            ROOT / "Sources/HorizonRFMac/Models/AppModels.swift",
            ROOT / "Sources/HorizonRFMac/Services/CSVCodec.swift",
            ROOT / "Sources/HorizonRFMac/Services/CHIRPCSVService.swift",
            ROOT / "Sources/HorizonRFMac/Services/AppStore.swift",
            ROOT / "Sources/HorizonRFMac/Views/ContentView.swift",
            ROOT / "Sources/HorizonRFMac/Views/ChannelsView.swift",
            ROOT / "Sources/HorizonRFMac/Views/ContactsView.swift",
            ROOT / "Sources/HorizonRFMac/Views/HeardView.swift",
            ROOT / "Sources/HorizonRFMac/Views/RadiosView.swift",
            ROOT / "Sources/HorizonRFMac/Views/ToolsView.swift",
            ROOT / "scripts/build-macos-app.sh",
            ROOT / "scripts/make-dmg.sh",
        ]
        for file_path in expected_files:
            self.assertTrue(file_path.exists(), f"Missing expected macOS app file: {file_path}")

    def test_build_scripts_reference_app_and_dmg_outputs(self) -> None:
        build_script = (ROOT / "scripts/build-macos-app.sh").read_text(encoding="utf-8")
        dmg_script = (ROOT / "scripts/make-dmg.sh").read_text(encoding="utf-8")

        self.assertIn(".app", build_script)
        self.assertIn("swift build", build_script)
        self.assertIn("--disable-sandbox", build_script)
        self.assertIn(".dmg", dmg_script)
        self.assertIn("hdiutil create", dmg_script)


if __name__ == "__main__":
    unittest.main()
