from __future__ import annotations

import contextlib
import csv
import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from horizon_radio.cli import main


class HorizonCliTests(unittest.TestCase):
    def run_cli(self, *args: str) -> tuple[int, str, str]:
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            exit_code = main(list(args))
        return exit_code, stdout.getvalue(), stderr.getvalue()

    def install_fake_chirpc(self, tmpdir: str) -> tuple[Path, Path]:
        script_path = Path(tmpdir) / "chirpc"
        log_path = Path(tmpdir) / "chirpc.log"
        script_path.write_text(
            """#!/usr/bin/env python3
import os
import sys
from pathlib import Path

args = sys.argv[1:]
log_path = Path(os.environ["CHIRPC_LOG"])
with log_path.open("a", encoding="utf-8") as handle:
    handle.write(" ".join(args) + "\\n")

if "--version" in args:
    print("chirpc test 1.0")
    raise SystemExit(0)

if "--list-radios" in args:
    print("test-radio")
    raise SystemExit(0)

if "--download-mmap" in args:
    image_path = Path(args[args.index("--mmap") + 1])
    image_path.parent.mkdir(parents=True, exist_ok=True)
    image_path.write_text("dummy image", encoding="utf-8")
    raise SystemExit(0)

value_options = {
    "--set-mem-name",
    "--set-mem-freq",
    "--set-mem-mode",
    "--set-mem-dup",
    "--set-mem-offset",
    "--set-mem-tenc",
    "--set-mem-tsql",
    "--set-mem-dtcs",
    "--set-mem-dtcspol",
}

if args and args[-1].isdigit():
    for index, token in enumerate(args[:-1]):
        if token in value_options and index + 1 < len(args) and ":" not in args[index + 1]:
            print("legacy positional syntax rejected", file=sys.stderr)
            raise SystemExit(2)

raise SystemExit(0)
""",
            encoding="utf-8",
        )
        script_path.chmod(0o755)
        return script_path, log_path

    def test_contact_heard_and_stats_flow(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = str(Path(tmpdir) / "radio.db")

            code, _, err = self.run_cli("--db", db_path, "radio", "add", "--name", "ht1", "--model", "FT-60")
            self.assertEqual(code, 0, err)

            code, _, err = self.run_cli(
                "--db",
                db_path,
                "contact",
                "add",
                "--callsign",
                "M7ABC",
                "--freq",
                "145.5",
                "--mode",
                "FM",
                "--radio",
                "ht1",
                "--sent",
                "59",
                "--received",
                "57",
            )
            self.assertEqual(code, 0, err)

            code, _, err = self.run_cli(
                "--db",
                db_path,
                "heard",
                "add",
                "--freq",
                "433.5",
                "--mode",
                "FM",
                "--radio",
                "ht1",
                "--signal",
                "59",
            )
            self.assertEqual(code, 0, err)

            code, output, err = self.run_cli("--db", db_path, "stats")
            self.assertEqual(code, 0, err)
            self.assertIn("Contacts:  1", output)
            self.assertIn("Heard:     1", output)

    def test_chirp_export_uses_expected_headers(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = str(Path(tmpdir) / "radio.db")
            csv_path = Path(tmpdir) / "channels.csv"

            code, _, err = self.run_cli("--db", db_path, "radio", "add", "--name", "ht1")
            self.assertEqual(code, 0, err)

            code, _, err = self.run_cli(
                "--db",
                db_path,
                "channel",
                "add",
                "--radio",
                "ht1",
                "--memory",
                "1",
                "--name",
                "S20",
                "--rx",
                "145.5",
                "--mode",
                "FM",
            )
            self.assertEqual(code, 0, err)

            code, _, err = self.run_cli("--db", db_path, "export", "chirp-csv", str(csv_path), "--radio", "ht1")
            self.assertEqual(code, 0, err)

            with csv_path.open(newline="", encoding="utf-8") as handle:
                reader = csv.DictReader(handle)
                rows = list(reader)

            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["Location"], "1")
            self.assertEqual(rows[0]["Name"], "S20")
            self.assertEqual(rows[0]["Frequency"], "145.500000")
            self.assertIn("Comment", reader.fieldnames or [])

    def test_time_command_supports_multiple_zones(self) -> None:
        code, output, err = self.run_cli(
            "time",
            "convert",
            "2026-03-23T12:00:00+00:00",
            "--tz",
            "UTC",
            "--tz",
            "Europe/London",
        )
        self.assertEqual(code, 0, err)
        self.assertIn("UTC", output)
        self.assertIn("Europe/London", output)

    def test_menu_auto_launches_when_no_command_is_given(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = str(Path(tmpdir) / "radio.db")
            with mock.patch("horizon_radio.cli.is_interactive_terminal", return_value=True), mock.patch(
                "horizon_radio.cli.pause", return_value=None
            ), mock.patch("builtins.input", side_effect=["0"]):
                code, output, err = self.run_cli("--db", db_path)

        self.assertEqual(code, 0, err)
        self.assertIn("Main Menu", output)
        self.assertIn("Exiting Horizon RF.", output)

    def test_menu_can_add_and_list_a_radio_profile(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = str(Path(tmpdir) / "radio.db")
            with mock.patch("horizon_radio.cli.pause", return_value=None), mock.patch(
                "builtins.input",
                side_effect=[
                    "2",
                    "2",
                    "ht1",
                    "FT-60",
                    "",
                    "",
                    "",
                    "1",
                    "0",
                    "0",
                ],
            ):
                code, output, err = self.run_cli("--db", db_path, "menu")

        self.assertEqual(code, 0, err)
        self.assertIn("Saved radio profile `ht1`.", output)
        self.assertIn("FT-60", output)

    def test_chirp_apply_image_falls_back_to_inline_syntax(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = str(Path(tmpdir) / "radio.db")
            image_path = Path(tmpdir) / "radio.img"
            image_path.write_text("baseline", encoding="utf-8")
            _, log_path = self.install_fake_chirpc(tmpdir)

            with mock.patch.dict(
                os.environ,
                {"PATH": f"{tmpdir}{os.pathsep}{os.environ.get('PATH', '')}", "CHIRPC_LOG": str(log_path)},
                clear=False,
            ):
                code, _, err = self.run_cli("--db", db_path, "radio", "add", "--name", "ht1")
                self.assertEqual(code, 0, err)

                code, _, err = self.run_cli(
                    "--db",
                    db_path,
                    "channel",
                    "add",
                    "--radio",
                    "ht1",
                    "--memory",
                    "1",
                    "--name",
                    "S20",
                    "--rx",
                    "145.5",
                    "--mode",
                    "FM",
                )
                self.assertEqual(code, 0, err)

                code, _, err = self.run_cli(
                    "--db",
                    db_path,
                    "channel",
                    "add",
                    "--radio",
                    "ht1",
                    "--memory",
                    "2",
                    "--name",
                    "RPT",
                    "--rx",
                    "145.6",
                    "--duplex",
                    "+",
                    "--offset",
                    "0.6",
                    "--tone-mode",
                    "Tone",
                    "--rtone",
                    "88.5",
                )
                self.assertEqual(code, 0, err)

                code, output, err = self.run_cli(
                    "--db",
                    db_path,
                    "chirp",
                    "apply-image",
                    "--channels-from",
                    "ht1",
                    "--image",
                    str(image_path),
                    "--backup",
                )
                self.assertEqual(code, 0, err)
                self.assertIn("Applied 2 channel(s)", output)
                self.assertTrue(image_path.with_suffix(".img.bak").exists())

            log_lines = log_path.read_text(encoding="utf-8").splitlines()
            self.assertTrue(any("--clear-mem 1" in line for line in log_lines))
            self.assertTrue(any("--set-mem-name 1:S20" in line for line in log_lines))
            self.assertTrue(any("--set-mem-dup 2:+" in line for line in log_lines))
            self.assertTrue(any("--set-mem-tencon 2" in line for line in log_lines))

    def test_chirp_program_radio_downloads_applies_and_uploads(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = str(Path(tmpdir) / "radio.db")
            image_path = Path(tmpdir) / "radio.img"
            _, log_path = self.install_fake_chirpc(tmpdir)

            with mock.patch.dict(
                os.environ,
                {"PATH": f"{tmpdir}{os.pathsep}{os.environ.get('PATH', '')}", "CHIRPC_LOG": str(log_path)},
                clear=False,
            ):
                code, _, err = self.run_cli(
                    "--db",
                    db_path,
                    "radio",
                    "add",
                    "--name",
                    "ht1",
                    "--chirp-id",
                    "test-radio",
                    "--serial",
                    "/dev/ttyUSB0",
                )
                self.assertEqual(code, 0, err)

                code, _, err = self.run_cli(
                    "--db",
                    db_path,
                    "channel",
                    "add",
                    "--radio",
                    "ht1",
                    "--memory",
                    "1",
                    "--name",
                    "S20",
                    "--rx",
                    "145.5",
                    "--mode",
                    "FM",
                )
                self.assertEqual(code, 0, err)

                code, output, err = self.run_cli(
                    "--db",
                    db_path,
                    "chirp",
                    "program-radio",
                    "--radio",
                    "ht1",
                    "--image",
                    str(image_path),
                )
                self.assertEqual(code, 0, err)
                self.assertIn("Download step: completed", output)
                self.assertIn("Upload step: completed", output)

            log_lines = log_path.read_text(encoding="utf-8").splitlines()
            self.assertTrue(any("--download-mmap" in line for line in log_lines))
            self.assertTrue(any("--set-mem-name 1:S20" in line for line in log_lines))
            self.assertTrue(any("--upload-mmap" in line for line in log_lines))


if __name__ == "__main__":
    unittest.main()
