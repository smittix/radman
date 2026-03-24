from __future__ import annotations

import argparse
import csv
import io
import shutil
import sqlite3
import sys
from datetime import datetime
from pathlib import Path
from typing import Callable, Iterable, Sequence
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from horizon_radio import __version__
from horizon_radio.chirp import (
    ChirpError,
    apply_memory_fields,
    chirpc_path,
    download_image,
    list_radios,
    upload_image,
    version_text,
)
from horizon_radio.db import connect, default_db_path, execute, fetch_all, fetch_one, isoformat, resolve_db_path

CHIRP_HEADERS = [
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


def parse_datetime(raw: str | None) -> datetime:
    if not raw:
        return datetime.now().astimezone()

    normalized = raw.strip().replace("Z", "+00:00")
    try:
        value = datetime.fromisoformat(normalized)
    except ValueError as exc:
        raise ValueError(
            "Use an ISO-like timestamp such as 2026-03-23T18:30 or 2026-03-23T18:30+00:00."
        ) from exc

    if value.tzinfo is None:
        return value.astimezone()
    return value


def print_table(rows: Sequence[dict[str, object]], columns: Sequence[str]) -> None:
    if not rows:
        print("No records found.")
        return

    widths = {column: len(column) for column in columns}
    for row in rows:
        for column in columns:
            widths[column] = max(widths[column], len(str(row.get(column, ""))))

    header = "  ".join(column.ljust(widths[column]) for column in columns)
    divider = "  ".join("-" * widths[column] for column in columns)
    print(header)
    print(divider)
    for row in rows:
        print("  ".join(str(row.get(column, "")).ljust(widths[column]) for column in columns))


def format_frequency(value: float | None) -> str:
    if value is None:
        return ""
    return f"{value:.6f}".rstrip("0").rstrip(".")


def format_timestamp(raw: str) -> str:
    try:
        return datetime.fromisoformat(raw).astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")
    except ValueError:
        return raw


def open_database(path: str | None) -> sqlite3.Connection:
    return connect(path)


def get_radio_row(connection: sqlite3.Connection, name: str | None) -> sqlite3.Row | None:
    if not name:
        return None
    row = fetch_one(connection, "SELECT * FROM radios WHERE name = ?", (name,))
    if not row:
        raise ValueError(f"Unknown radio profile: {name}")
    return row


def output_csv(path: str, fieldnames: Sequence[str], rows: Iterable[dict[str, object]]) -> None:
    output_stream: io.TextIOBase
    close_stream = False

    if path == "-":
        output_stream = sys.stdout
    else:
        target = Path(path).expanduser().resolve()
        target.parent.mkdir(parents=True, exist_ok=True)
        output_stream = target.open("w", newline="", encoding="utf-8")
        close_stream = True

    try:
        writer = csv.DictWriter(output_stream, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)
    finally:
        if close_stream:
            output_stream.close()


def build_chirp_row(row: sqlite3.Row, location: int) -> dict[str, object]:
    duplex = row["duplex"] or ""
    offset_value: float | None = None
    if duplex in {"+", "-"}:
        offset_value = row["offset_mhz"] or 0.0
    elif duplex == "split":
        offset_value = row["tx_frequency_mhz"] or row["offset_mhz"] or 0.0
    elif duplex == "off":
        offset_value = 0.0

    return {
        "Location": row["memory"] if row["memory"] is not None else location,
        "Name": row["name"],
        "Frequency": f"{row['rx_frequency_mhz']:.6f}",
        "Duplex": duplex,
        "Offset": f"{offset_value:.6f}" if offset_value is not None else "0.000000",
        "Tone": row["tone_mode"] or "",
        "rToneFreq": f"{row['rtone_hz']:.1f}",
        "cToneFreq": f"{row['ctone_hz']:.1f}",
        "DtcsCode": row["dtcs_code"],
        "DtcsPolarity": row["dtcs_polarity"],
        "RxDtcsCode": row["rx_dtcs_code"],
        "CrossMode": row["cross_mode"],
        "Mode": row["mode"],
        "TStep": f"{row['tune_step_khz']:.2f}",
        "Skip": row["skip"],
        "Power": row["power"],
        "Comment": row["comment"] or "",
        "URCALL": "",
        "RPT1CALL": "",
        "RPT2CALL": "",
        "DVCODE": "",
    }


def add_where_clause(filters: list[str], params: list[object], clause: str, value: object | None) -> None:
    if value is not None:
        filters.append(clause)
        params.append(value)


def make_args(db_path: str | None, **kwargs: object) -> argparse.Namespace:
    return argparse.Namespace(db=db_path, **kwargs)


def is_interactive_terminal() -> bool:
    try:
        return sys.stdin.isatty()
    except Exception:
        return False


def pause(message: str = "Press Enter to continue...") -> None:
    try:
        input(message)
    except EOFError:
        pass


def prompt_text(label: str, default: str | None = None, required: bool = False) -> str | None:
    while True:
        suffix = f" [{default}]" if default not in (None, "") else ""
        try:
            raw = input(f"{label}{suffix}: ").strip()
        except EOFError:
            raw = ""

        if raw:
            return raw
        if default is not None:
            return default
        if not required:
            return None
        print("This field is required.")


def prompt_float(label: str, default: float | None = None, required: bool = False) -> float | None:
    while True:
        default_text = None if default is None else format_frequency(default)
        raw = prompt_text(label, default=default_text, required=required)
        if raw in (None, ""):
            return None
        try:
            return float(raw)
        except ValueError:
            print("Enter a valid number.")


def prompt_int(label: str, default: int | None = None, required: bool = False) -> int | None:
    while True:
        raw = prompt_text(label, default=str(default) if default is not None else None, required=required)
        if raw in (None, ""):
            return None
        try:
            return int(raw)
        except ValueError:
            print("Enter a whole number.")


def prompt_bool(label: str, default: bool = False) -> bool:
    hint = "Y/n" if default else "y/N"
    while True:
        raw = prompt_text(f"{label} ({hint})")
        if raw is None:
            return default
        normalized = raw.strip().lower()
        if normalized in {"y", "yes"}:
            return True
        if normalized in {"n", "no"}:
            return False
        print("Enter y or n.")


def prompt_choice(label: str, options: Sequence[str], default: str | None = None) -> str:
    rendered = "/".join(options)
    while True:
        raw = prompt_text(f"{label} [{rendered}]", default=default, required=default is None)
        assert raw is not None
        if raw in options:
            return raw
        print(f"Choose one of: {', '.join(options)}")


def prompt_csv_zones() -> list[str] | None:
    raw = prompt_text("Time zones, comma-separated, blank for local and UTC")
    if not raw:
        return None
    values = [item.strip() for item in raw.split(",") if item.strip()]
    return values or None


def print_available_radios(db_path: str | None) -> None:
    connection = open_database(db_path)
    rows = fetch_all(connection, "SELECT name FROM radios ORDER BY name")
    connection.close()
    if rows:
        print("Available radio profiles:", ", ".join(row["name"] for row in rows))


def run_menu_action(action: Callable[[], object]) -> None:
    try:
        action()
    except (ValueError, sqlite3.IntegrityError, ChirpError) as exc:
        print(f"Error: {exc}")
    print()
    pause()


def cmd_init(args: argparse.Namespace) -> int:
    connection = open_database(args.db)
    connection.close()
    print(f"Database ready at {resolve_db_path(args.db)}")
    return 0


def cmd_radio_add(args: argparse.Namespace) -> int:
    connection = open_database(args.db)
    execute(
        connection,
        """
        INSERT INTO radios (name, model, chirp_id, serial_port, notes, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (args.name, args.model, args.chirp_id, args.serial, args.notes, isoformat()),
    )
    connection.close()
    print(f"Saved radio profile `{args.name}`.")
    return 0


def cmd_radio_list(args: argparse.Namespace) -> int:
    connection = open_database(args.db)
    rows = fetch_all(connection, "SELECT name, model, chirp_id, serial_port, notes FROM radios ORDER BY name")
    table_rows = [
        {
            "name": row["name"],
            "model": row["model"] or "",
            "chirp_id": row["chirp_id"] or "",
            "serial": row["serial_port"] or "",
            "notes": row["notes"] or "",
        }
        for row in rows
    ]
    print_table(table_rows, ["name", "model", "chirp_id", "serial", "notes"])
    connection.close()
    return 0


def cmd_contact_add(args: argparse.Namespace) -> int:
    connection = open_database(args.db)
    radio = get_radio_row(connection, args.radio)
    contacted_at = parse_datetime(args.when)
    execute(
        connection,
        """
        INSERT INTO contacts (
            callsign, operator_name, frequency_mhz, mode, radio_id,
            report_sent, report_received, location, notes, contacted_at, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            args.callsign.upper(),
            args.name,
            args.freq,
            args.mode,
            radio["id"] if radio else None,
            args.sent,
            args.received,
            args.location,
            args.notes,
            contacted_at.astimezone().isoformat(timespec="seconds"),
            isoformat(),
        ),
    )
    connection.close()
    print(f"Logged contact with {args.callsign.upper()}.")
    return 0


def cmd_contact_list(args: argparse.Namespace) -> int:
    connection = open_database(args.db)
    filters: list[str] = []
    params: list[object] = []

    add_where_clause(filters, params, "r.name = ?", args.radio)
    add_where_clause(filters, params, "c.callsign = ?", args.callsign.upper() if args.callsign else None)
    add_where_clause(filters, params, "c.frequency_mhz = ?", args.freq)

    if args.since:
        filters.append("c.contacted_at >= ?")
        params.append(parse_datetime(args.since).astimezone().isoformat(timespec="seconds"))

    where = f"WHERE {' AND '.join(filters)}" if filters else ""
    params.append(args.limit)
    query = f"""
        SELECT c.id, c.callsign, c.operator_name, c.frequency_mhz, c.mode,
               c.report_sent, c.report_received, c.location, c.contacted_at, r.name AS radio_name
        FROM contacts c
        LEFT JOIN radios r ON r.id = c.radio_id
        {where}
        ORDER BY c.contacted_at DESC
        LIMIT ?
    """
    rows = fetch_all(connection, query, params)
    print_table(
        [
            {
                "id": row["id"],
                "callsign": row["callsign"],
                "name": row["operator_name"] or "",
                "freq": format_frequency(row["frequency_mhz"]),
                "mode": row["mode"] or "",
                "radio": row["radio_name"] or "",
                "rst": "/".join(part for part in [row["report_sent"], row["report_received"]] if part),
                "location": row["location"] or "",
                "when": format_timestamp(row["contacted_at"]),
            }
            for row in rows
        ],
        ["id", "callsign", "name", "freq", "mode", "radio", "rst", "location", "when"],
    )
    connection.close()
    return 0


def cmd_heard_add(args: argparse.Namespace) -> int:
    connection = open_database(args.db)
    radio = get_radio_row(connection, args.radio)
    heard_at = parse_datetime(args.when)
    execute(
        connection,
        """
        INSERT INTO heard_entries (
            frequency_mhz, mode, radio_id, source, signal_report,
            location, notes, heard_at, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            args.freq,
            args.mode,
            radio["id"] if radio else None,
            args.source,
            args.signal,
            args.location,
            args.notes,
            heard_at.astimezone().isoformat(timespec="seconds"),
            isoformat(),
        ),
    )
    connection.close()
    print(f"Logged heard frequency {format_frequency(args.freq)} MHz.")
    return 0


def cmd_heard_list(args: argparse.Namespace) -> int:
    connection = open_database(args.db)
    filters: list[str] = []
    params: list[object] = []

    add_where_clause(filters, params, "r.name = ?", args.radio)
    add_where_clause(filters, params, "h.frequency_mhz = ?", args.freq)

    if args.since:
        filters.append("h.heard_at >= ?")
        params.append(parse_datetime(args.since).astimezone().isoformat(timespec="seconds"))

    where = f"WHERE {' AND '.join(filters)}" if filters else ""
    params.append(args.limit)
    query = f"""
        SELECT h.id, h.frequency_mhz, h.mode, h.source, h.signal_report,
               h.location, h.heard_at, r.name AS radio_name
        FROM heard_entries h
        LEFT JOIN radios r ON r.id = h.radio_id
        {where}
        ORDER BY h.heard_at DESC
        LIMIT ?
    """
    rows = fetch_all(connection, query, params)
    print_table(
        [
            {
                "id": row["id"],
                "freq": format_frequency(row["frequency_mhz"]),
                "mode": row["mode"] or "",
                "radio": row["radio_name"] or "",
                "source": row["source"] or "",
                "signal": row["signal_report"] or "",
                "location": row["location"] or "",
                "when": format_timestamp(row["heard_at"]),
            }
            for row in rows
        ],
        ["id", "freq", "mode", "radio", "source", "signal", "location", "when"],
    )
    connection.close()
    return 0


def normalize_duplex(args: argparse.Namespace) -> tuple[str, float | None, float | None]:
    duplex = "" if args.duplex == "simplex" else args.duplex
    offset: float | None = args.offset
    tx_frequency: float | None = args.tx

    if duplex == "":
        tx_frequency = tx_frequency if tx_frequency is not None else args.rx
        offset = 0.0
    elif duplex in {"+", "-"}:
        if offset is None:
            if tx_frequency is None:
                raise ValueError("Use --offset or --tx when duplex is + or -.")
            offset = abs(tx_frequency - args.rx)
        if tx_frequency is None:
            tx_frequency = args.rx + offset if duplex == "+" else args.rx - offset
    elif duplex == "split":
        if tx_frequency is None:
            raise ValueError("Use --tx when duplex is split.")
    elif duplex == "off":
        tx_frequency = None
        offset = 0.0

    return duplex, offset, tx_frequency


def normalize_tone_mode(raw: str) -> str:
    return "" if raw == "none" else raw


def cmd_channel_add(args: argparse.Namespace) -> int:
    connection = open_database(args.db)
    radio = get_radio_row(connection, args.radio)
    duplex, offset, tx_frequency = normalize_duplex(args)
    execute(
        connection,
        """
        INSERT INTO channels (
            radio_id, memory, name, rx_frequency_mhz, tx_frequency_mhz, duplex, offset_mhz,
            tone_mode, rtone_hz, ctone_hz, dtcs_code, rx_dtcs_code, dtcs_polarity, cross_mode,
            mode, tune_step_khz, skip, power, comment, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            radio["id"] if radio else None,
            args.memory,
            args.name,
            args.rx,
            tx_frequency,
            duplex,
            offset,
            normalize_tone_mode(args.tone_mode),
            args.rtone,
            args.ctone,
            args.dtcs,
            args.rx_dtcs,
            args.dtcs_polarity,
            args.cross_mode,
            args.mode,
            args.step,
            args.skip,
            args.power,
            args.comment,
            isoformat(),
        ),
    )
    connection.close()
    print(f"Saved channel `{args.name}`.")
    return 0


def cmd_channel_list(args: argparse.Namespace) -> int:
    connection = open_database(args.db)
    filters: list[str] = []
    params: list[object] = []

    add_where_clause(filters, params, "r.name = ?", args.radio)

    where = f"WHERE {' AND '.join(filters)}" if filters else ""
    params.append(args.limit)
    query = f"""
        SELECT c.memory, c.name, c.rx_frequency_mhz, c.tx_frequency_mhz, c.duplex,
               c.offset_mhz, c.mode, c.power, c.skip, c.comment, r.name AS radio_name
        FROM channels c
        LEFT JOIN radios r ON r.id = c.radio_id
        {where}
        ORDER BY COALESCE(c.memory, 999999), c.name
        LIMIT ?
    """
    rows = fetch_all(connection, query, params)
    print_table(
        [
            {
                "memory": row["memory"] if row["memory"] is not None else "",
                "name": row["name"],
                "rx": format_frequency(row["rx_frequency_mhz"]),
                "tx": format_frequency(row["tx_frequency_mhz"]),
                "duplex": row["duplex"] or "simplex",
                "offset": format_frequency(row["offset_mhz"]),
                "mode": row["mode"],
                "radio": row["radio_name"] or "",
                "power": row["power"] or "",
                "skip": row["skip"] or "",
            }
            for row in rows
        ],
        ["memory", "name", "rx", "tx", "duplex", "offset", "mode", "radio", "power", "skip"],
    )
    connection.close()
    return 0


def cmd_export_contacts(args: argparse.Namespace) -> int:
    connection = open_database(args.db)
    filters: list[str] = []
    params: list[object] = []

    add_where_clause(filters, params, "r.name = ?", args.radio)
    where = f"WHERE {' AND '.join(filters)}" if filters else ""
    query = f"""
        SELECT c.id, c.callsign, c.operator_name, c.frequency_mhz, c.mode, c.report_sent,
               c.report_received, c.location, c.notes, c.contacted_at, r.name AS radio_name
        FROM contacts c
        LEFT JOIN radios r ON r.id = c.radio_id
        {where}
        ORDER BY c.contacted_at DESC
    """
    rows = fetch_all(connection, query, params)
    output_csv(
        args.path,
        ["id", "callsign", "operator_name", "frequency_mhz", "mode", "report_sent", "report_received", "location", "notes", "contacted_at", "radio_name"],
        [
            {
                "id": row["id"],
                "callsign": row["callsign"],
                "operator_name": row["operator_name"] or "",
                "frequency_mhz": format_frequency(row["frequency_mhz"]),
                "mode": row["mode"] or "",
                "report_sent": row["report_sent"] or "",
                "report_received": row["report_received"] or "",
                "location": row["location"] or "",
                "notes": row["notes"] or "",
                "contacted_at": row["contacted_at"],
                "radio_name": row["radio_name"] or "",
            }
            for row in rows
        ],
    )
    connection.close()
    print(f"Exported {len(rows)} contact(s) to {args.path}.")
    return 0


def cmd_export_heard(args: argparse.Namespace) -> int:
    connection = open_database(args.db)
    filters: list[str] = []
    params: list[object] = []

    add_where_clause(filters, params, "r.name = ?", args.radio)
    where = f"WHERE {' AND '.join(filters)}" if filters else ""
    query = f"""
        SELECT h.id, h.frequency_mhz, h.mode, h.source, h.signal_report,
               h.location, h.notes, h.heard_at, r.name AS radio_name
        FROM heard_entries h
        LEFT JOIN radios r ON r.id = h.radio_id
        {where}
        ORDER BY h.heard_at DESC
    """
    rows = fetch_all(connection, query, params)
    output_csv(
        args.path,
        ["id", "frequency_mhz", "mode", "source", "signal_report", "location", "notes", "heard_at", "radio_name"],
        [
            {
                "id": row["id"],
                "frequency_mhz": format_frequency(row["frequency_mhz"]),
                "mode": row["mode"] or "",
                "source": row["source"] or "",
                "signal_report": row["signal_report"] or "",
                "location": row["location"] or "",
                "notes": row["notes"] or "",
                "heard_at": row["heard_at"],
                "radio_name": row["radio_name"] or "",
            }
            for row in rows
        ],
    )
    connection.close()
    print(f"Exported {len(rows)} heard record(s) to {args.path}.")
    return 0


def cmd_export_chirp_csv(args: argparse.Namespace) -> int:
    connection = open_database(args.db)
    filters: list[str] = []
    params: list[object] = []
    add_where_clause(filters, params, "r.name = ?", args.radio)

    where = f"WHERE {' AND '.join(filters)}" if filters else ""
    query = f"""
        SELECT c.*, r.name AS radio_name
        FROM channels c
        LEFT JOIN radios r ON r.id = c.radio_id
        {where}
        ORDER BY COALESCE(c.memory, 999999), c.name
    """
    rows = fetch_all(connection, query, params)
    chirp_rows = [build_chirp_row(row, location=index) for index, row in enumerate(rows)]
    output_csv(args.path, CHIRP_HEADERS, chirp_rows)
    connection.close()
    print(f"Exported {len(chirp_rows)} channel(s) to {args.path}.")
    return 0


def fetch_channels_for_profile(connection: sqlite3.Connection, profile_name: str) -> list[dict[str, object]]:
    get_radio_row(connection, profile_name)
    rows = fetch_all(
        connection,
        """
        SELECT c.*, r.name AS radio_name
        FROM channels c
        LEFT JOIN radios r ON r.id = c.radio_id
        WHERE r.name = ?
        ORDER BY COALESCE(c.memory, 999999), c.name
        """,
        (profile_name,),
    )
    return [{key: row[key] for key in row.keys()} for row in rows]


def build_image_backup(image_path: Path) -> Path:
    suffix = f"{image_path.suffix}.bak" if image_path.suffix else ".bak"
    backup_path = image_path.with_suffix(suffix)
    shutil.copy2(image_path, backup_path)
    return backup_path


def compute_programming_offset(channel: dict[str, object]) -> float:
    offset = channel["offset_mhz"]
    if offset is not None:
        return float(offset)

    rx = float(channel["rx_frequency_mhz"])
    tx = channel["tx_frequency_mhz"]
    if tx is None:
        return 0.0
    return abs(float(tx) - rx)


def describe_chirp_blockers(channel: dict[str, object]) -> list[str]:
    blockers: list[str] = []
    duplex = channel["duplex"] or ""
    tone_mode = channel["tone_mode"] or ""
    rx_frequency = float(channel["rx_frequency_mhz"])
    tx_frequency = channel["tx_frequency_mhz"]

    if duplex in {"split", "off"}:
        blockers.append(f"duplex `{duplex}` is not exposed through the chirpc memory CLI")
    if duplex == "" and tx_frequency is not None and abs(float(tx_frequency) - rx_frequency) > 0.000001:
        blockers.append("simplex channel has a different TX frequency, which requires split support")
    if tone_mode == "Cross":
        blockers.append("Cross tone mode is not programmable through the chirpc memory CLI")
    if tone_mode == "DTCS" and str(channel["rx_dtcs_code"]) != str(channel["dtcs_code"]):
        blockers.append("separate RX and TX DTCS codes are not programmable through the chirpc memory CLI")
    return blockers


def describe_chirp_warnings(channel: dict[str, object]) -> list[str]:
    warnings: list[str] = []
    if channel["comment"]:
        warnings.append("comment is stored in Horizon RF but not written through chirpc")
    if channel["power"]:
        warnings.append("power labels are not written through chirpc")
    if channel["skip"]:
        warnings.append("skip flags are not written through chirpc")
    if channel["tune_step_khz"] not in (None, 5.0):
        warnings.append("tuning step is stored and exported to CSV, but not written through chirpc")
    return warnings


def build_chirpc_memory_fields(channel: dict[str, object]) -> list[tuple[str, str | None]]:
    fields: list[tuple[str, str | None]] = [
        ("--set-mem-name", str(channel["name"])),
        ("--set-mem-freq", f"{float(channel['rx_frequency_mhz']):.6f}"),
    ]

    mode = channel["mode"]
    if mode:
        fields.append(("--set-mem-mode", str(mode)))

    duplex = channel["duplex"] or ""
    if duplex in {"+", "-"}:
        fields.append(("--set-mem-dup", duplex))
        fields.append(("--set-mem-offset", f"{compute_programming_offset(channel):.6f}"))

    tone_mode = channel["tone_mode"] or ""
    if tone_mode == "Tone":
        fields.append(("--set-mem-tencon", None))
        fields.append(("--set-mem-tenc", f"{float(channel['rtone_hz']):.1f}"))
    elif tone_mode == "TSQL":
        fields.append(("--set-mem-tencon", None))
        fields.append(("--set-mem-tsqlon", None))
        fields.append(("--set-mem-tenc", f"{float(channel['rtone_hz']):.1f}"))
        fields.append(("--set-mem-tsql", f"{float(channel['ctone_hz']):.1f}"))
    elif tone_mode == "DTCS":
        fields.append(("--set-mem-dtcson", None))
        fields.append(("--set-mem-dtcs", str(channel["dtcs_code"])))
        fields.append(("--set-mem-dtcspol", str(channel["dtcs_polarity"])))

    return fields


def prepare_chirp_programming(
    channels: Sequence[dict[str, object]], auto_number_from: int | None
) -> tuple[list[tuple[dict[str, object], list[tuple[str, str | None]]]], list[str], list[str]]:
    programmable: list[tuple[dict[str, object], list[tuple[str, str | None]]]] = []
    warnings: list[str] = []
    skipped: list[str] = []

    used_memories = {int(channel["memory"]) for channel in channels if channel["memory"] is not None}
    next_auto_memory = auto_number_from

    for channel in channels:
        item = dict(channel)
        memory = item["memory"]

        if memory is None:
            if next_auto_memory is None:
                skipped.append(
                    f"Skipped `{item['name']}` because it has no memory slot. Use --auto-number-from to place it temporarily."
                )
                continue
            while next_auto_memory in used_memories:
                next_auto_memory += 1
            item["memory"] = next_auto_memory
            used_memories.add(next_auto_memory)
            warnings.append(
                f"Memory {next_auto_memory} `{item['name']}` was auto-assigned for this run and was not written back to the database."
            )
            next_auto_memory += 1

        blockers = describe_chirp_blockers(item)
        if blockers:
            skipped.append(f"Skipped memory {item['memory']} `{item['name']}`: {'; '.join(blockers)}")
            continue

        warnings.extend(
            f"Memory {item['memory']} `{item['name']}`: {warning}" for warning in describe_chirp_warnings(item)
        )
        programmable.append((item, build_chirpc_memory_fields(item)))

    return programmable, warnings, skipped


def apply_channels_to_image(
    image_path: Path,
    channels: Sequence[dict[str, object]],
    auto_number_from: int | None,
    backup: bool,
) -> tuple[int, list[str], list[str], Path | None]:
    resolved_image = image_path.expanduser().resolve()
    if not resolved_image.exists():
        raise ValueError(f"Image file not found: {resolved_image}")
    if not resolved_image.is_file():
        raise ValueError(f"Image path is not a file: {resolved_image}")

    programmable, warnings, skipped = prepare_chirp_programming(channels, auto_number_from)
    if not programmable:
        raise ValueError("No programmable channels were found for this apply operation.")

    backup_path = build_image_backup(resolved_image) if backup else None
    applied = 0
    for channel, fields in programmable:
        apply_memory_fields(resolved_image, int(channel["memory"]), fields)
        applied += 1

    return applied, warnings, skipped, backup_path


def cmd_stats(args: argparse.Namespace) -> int:
    connection = open_database(args.db)
    radio_total = fetch_one(connection, "SELECT COUNT(*) AS count FROM radios")["count"]
    contact_total = fetch_one(connection, "SELECT COUNT(*) AS count FROM contacts")["count"]
    heard_total = fetch_one(connection, "SELECT COUNT(*) AS count FROM heard_entries")["count"]
    channel_total = fetch_one(connection, "SELECT COUNT(*) AS count FROM channels")["count"]
    last_contact = fetch_one(connection, "SELECT callsign, contacted_at FROM contacts ORDER BY contacted_at DESC LIMIT 1")
    last_heard = fetch_one(connection, "SELECT frequency_mhz, heard_at FROM heard_entries ORDER BY heard_at DESC LIMIT 1")
    top_contacts = fetch_all(
        connection,
        """
        SELECT frequency_mhz, COUNT(*) AS uses
        FROM contacts
        WHERE frequency_mhz IS NOT NULL
        GROUP BY frequency_mhz
        ORDER BY uses DESC, frequency_mhz ASC
        LIMIT 3
        """,
    )
    top_heard = fetch_all(
        connection,
        """
        SELECT frequency_mhz, COUNT(*) AS uses
        FROM heard_entries
        GROUP BY frequency_mhz
        ORDER BY uses DESC, frequency_mhz ASC
        LIMIT 3
        """,
    )
    connection.close()

    print(f"Database: {resolve_db_path(args.db)}")
    print(f"Profiles:  {radio_total}")
    print(f"Contacts:  {contact_total}")
    print(f"Heard:     {heard_total}")
    print(f"Channels:  {channel_total}")
    print()
    if last_contact:
        print(
            f"Last contact: {last_contact['callsign']} at {format_timestamp(last_contact['contacted_at'])}"
        )
    else:
        print("Last contact: none")
    if last_heard:
        print(
            f"Last heard:   {format_frequency(last_heard['frequency_mhz'])} MHz at {format_timestamp(last_heard['heard_at'])}"
        )
    else:
        print("Last heard:   none")

    if top_contacts:
        print()
        print("Top contact frequencies:")
        for row in top_contacts:
            print(f"- {format_frequency(row['frequency_mhz'])} MHz ({row['uses']} contact(s))")

    if top_heard:
        print()
        print("Top heard frequencies:")
        for row in top_heard:
            print(f"- {format_frequency(row['frequency_mhz'])} MHz ({row['uses']} hit(s))")
    return 0


def resolve_timezones(raw_timezones: Sequence[str] | None) -> list[str]:
    if raw_timezones:
        return list(raw_timezones)
    return ["local", "UTC"]


def load_zone(zone_name: str) -> ZoneInfo:
    try:
        return ZoneInfo(zone_name)
    except ZoneInfoNotFoundError as exc:
        raise ValueError(f"Unknown time zone: {zone_name}") from exc


def render_time_row(label: str, value: datetime) -> dict[str, str]:
    return {
        "zone": label,
        "time": value.strftime("%Y-%m-%d %H:%M:%S"),
        "offset": value.strftime("%z"),
        "weekday": value.strftime("%A"),
    }


def cmd_time_now(args: argparse.Namespace) -> int:
    rows: list[dict[str, str]] = []
    now = datetime.now().astimezone()
    for zone_name in resolve_timezones(args.tz):
        if zone_name.lower() == "local":
            rows.append(render_time_row("local", now))
            continue
        zone = load_zone(zone_name)
        rows.append(render_time_row(zone_name, now.astimezone(zone)))
    print_table(rows, ["zone", "time", "offset", "weekday"])
    return 0


def cmd_time_convert(args: argparse.Namespace) -> int:
    base = parse_datetime(args.timestamp)
    rows: list[dict[str, str]] = []
    for zone_name in resolve_timezones(args.tz):
        if zone_name.lower() == "local":
            rows.append(render_time_row("local", base.astimezone()))
            continue
        zone = load_zone(zone_name)
        rows.append(render_time_row(zone_name, base.astimezone(zone)))
    print_table(rows, ["zone", "time", "offset", "weekday"])
    return 0


def resolve_chirp_profile(connection: sqlite3.Connection, radio_name: str) -> tuple[str, str]:
    row = get_radio_row(connection, radio_name)
    if row is None:
        raise ValueError(f"Unknown radio profile: {radio_name}")
    if not row["chirp_id"]:
        raise ValueError(f"Radio profile `{radio_name}` does not have a --chirp-id value.")
    if not row["serial_port"]:
        raise ValueError(f"Radio profile `{radio_name}` does not have a --serial value.")
    return row["chirp_id"], row["serial_port"]


def cmd_chirp_doctor(args: argparse.Namespace) -> int:
    print(f"Database path: {resolve_db_path(args.db)}")
    path = chirpc_path()
    if not path:
        print("chirpc: not installed")
        print("Direct CHIRP image upload/download is unavailable until CHIRP is installed.")
        return 0
    print(f"chirpc: {path}")
    print(f"version: {version_text()}")
    return 0


def cmd_chirp_list_radios(args: argparse.Namespace) -> int:
    radios = list_radios()
    print(radios)
    return 0


def cmd_chirp_download_image(args: argparse.Namespace) -> int:
    connection = open_database(args.db)
    chirp_id, serial_port = resolve_chirp_profile(connection, args.radio)
    connection.close()
    download_image(chirp_id, args.serial or serial_port, Path(args.image))
    print(f"Downloaded CHIRP image to {Path(args.image).expanduser().resolve()}.")
    return 0


def cmd_chirp_upload_image(args: argparse.Namespace) -> int:
    connection = open_database(args.db)
    chirp_id, serial_port = resolve_chirp_profile(connection, args.radio)
    connection.close()
    upload_image(chirp_id, args.serial or serial_port, Path(args.image))
    print(f"Uploaded CHIRP image from {Path(args.image).expanduser().resolve()}.")
    return 0


def cmd_chirp_apply_image(args: argparse.Namespace) -> int:
    connection = open_database(args.db)
    channels = fetch_channels_for_profile(connection, args.channels_from)
    connection.close()

    if not channels:
        raise ValueError(f"No channels were found for profile `{args.channels_from}`.")

    image_path = Path(args.image)
    applied, warnings, skipped, backup_path = apply_channels_to_image(
        image_path=image_path,
        channels=channels,
        auto_number_from=args.auto_number_from,
        backup=args.backup,
    )

    print(f"Applied {applied} channel(s) from `{args.channels_from}` to {image_path.expanduser().resolve()}.")
    if backup_path:
        print(f"Backup image: {backup_path}")
    if warnings:
        print()
        print("Warnings:")
        for warning in warnings:
            print(f"- {warning}")
    if skipped:
        print()
        print("Skipped:")
        for item in skipped:
            print(f"- {item}")
    return 0


def cmd_chirp_program_radio(args: argparse.Namespace) -> int:
    connection = open_database(args.db)
    chirp_id, serial_port = resolve_chirp_profile(connection, args.radio)
    source_profile = args.channels_from or args.radio
    channels = fetch_channels_for_profile(connection, source_profile)
    connection.close()

    if not channels:
        raise ValueError(f"No channels were found for profile `{source_profile}`.")

    image_path = Path(args.image).expanduser().resolve()
    chosen_serial = args.serial or serial_port

    if not args.no_download:
        download_image(chirp_id, chosen_serial, image_path)
    elif not image_path.exists():
        raise ValueError(f"Image file not found: {image_path}")

    applied, warnings, skipped, backup_path = apply_channels_to_image(
        image_path=image_path,
        channels=channels,
        auto_number_from=args.auto_number_from,
        backup=args.backup,
    )

    upload_image(chirp_id, chosen_serial, image_path)

    print(f"Programmed radio `{args.radio}` from profile `{source_profile}` using {applied} channel(s).")
    print(f"Image path: {image_path}")
    if args.no_download:
        print("Download step: skipped")
    else:
        print("Download step: completed")
    print("Upload step: completed")
    if backup_path:
        print(f"Backup image: {backup_path}")
    if warnings:
        print()
        print("Warnings:")
        for warning in warnings:
            print(f"- {warning}")
    if skipped:
        print()
        print("Skipped:")
        for item in skipped:
            print(f"- {item}")
    return 0


def cmd_chirp_workflow(args: argparse.Namespace) -> int:
    connection = open_database(args.db)
    row = get_radio_row(connection, args.radio)
    connection.close()
    if row is None:
        raise ValueError(f"Unknown radio profile: {args.radio}")

    csv_path = Path(args.csv).expanduser()
    image_path = Path(args.image).expanduser()
    print(f"Recommended workflow for `{args.radio}`")
    print()
    print("1. Fastest direct path:")
    print(f"   horizon-rf chirp program-radio --radio {args.radio} --image {image_path}")
    print("2. If you want a review step in the middle:")
    print(f"   horizon-rf chirp download-image --radio {args.radio} --image {image_path}")
    print(f"   horizon-rf chirp apply-image --channels-from {args.radio} --image {image_path}")
    print(f"   horizon-rf chirp upload-image --radio {args.radio} --image {image_path}")
    print("3. If you prefer CHIRP CSV import by hand:")
    print(f"   horizon-rf export chirp-csv {csv_path} --radio {args.radio}")
    print()
    print("Notes:")
    print("- This is safest when the radio profile has the exact CHIRP ID for the device.")
    print("- Raw CSV alone is not a complete upload format for many radios.")
    print("- Direct image programming uses the memory-edit commands exposed by chirpc, which do not cover every CHIRP field.")
    if row["chirp_id"]:
        print(f"- Stored CHIRP ID: {row['chirp_id']}")
    if row["serial_port"]:
        print(f"- Stored serial port: {row['serial_port']}")
    return 0


def menu_choice(title: str, items: Sequence[tuple[str, str]]) -> str:
    print()
    print(title)
    for key, label in items:
        print(f"{key}. {label}")
    valid = {key for key, _ in items}
    while True:
        raw = prompt_text("Choose an option", required=True)
        assert raw is not None
        if raw in valid:
            return raw
        print(f"Choose one of: {', '.join(key for key, _ in items)}")


def show_menu_header(db_path: str | None) -> None:
    print()
    print("Horizon RF")
    print(f"Database: {resolve_db_path(db_path)}")
    print(f"CHIRP: {chirpc_path() or 'not installed'}")


def menu_radio_profiles(db_path: str | None) -> None:
    while True:
        choice = menu_choice(
            "Radio Profiles",
            [
                ("1", "List radio profiles"),
                ("2", "Add radio profile"),
                ("0", "Back"),
            ],
        )
        if choice == "0":
            return
        if choice == "1":
            run_menu_action(lambda: cmd_radio_list(make_args(db_path)))
            continue

        name = prompt_text("Profile name", required=True)
        assert name is not None
        model = prompt_text("Model")
        chirp_id = prompt_text("CHIRP radio ID")
        serial = prompt_text("Default serial port")
        notes = prompt_text("Notes")
        run_menu_action(
            lambda: cmd_radio_add(
                make_args(db_path, name=name, model=model, chirp_id=chirp_id, serial=serial, notes=notes)
            )
        )


def menu_contacts(db_path: str | None) -> None:
    while True:
        choice = menu_choice(
            "Contacts",
            [
                ("1", "List recent contacts"),
                ("2", "Add a contact"),
                ("0", "Back"),
            ],
        )
        if choice == "0":
            return
        if choice == "1":
            print_available_radios(db_path)
            radio = prompt_text("Filter by radio profile")
            callsign = prompt_text("Filter by callsign")
            freq = prompt_float("Filter by frequency MHz")
            since = prompt_text("Since timestamp")
            limit = prompt_int("How many rows", default=20, required=True)
            assert limit is not None
            run_menu_action(
                lambda: cmd_contact_list(
                    make_args(db_path, radio=radio, callsign=callsign, freq=freq, since=since, limit=limit)
                )
            )
            continue

        print_available_radios(db_path)
        callsign = prompt_text("Callsign", required=True)
        assert callsign is not None
        name = prompt_text("Operator name")
        freq = prompt_float("Frequency MHz")
        mode = prompt_text("Mode")
        radio = prompt_text("Radio profile name")
        sent = prompt_text("Signal report sent")
        received = prompt_text("Signal report received")
        location = prompt_text("Location")
        notes = prompt_text("Notes")
        when = prompt_text("Timestamp")
        run_menu_action(
            lambda: cmd_contact_add(
                make_args(
                    db_path,
                    callsign=callsign,
                    name=name,
                    freq=freq,
                    mode=mode,
                    radio=radio,
                    sent=sent,
                    received=received,
                    location=location,
                    notes=notes,
                    when=when,
                )
            )
        )


def menu_heard(db_path: str | None) -> None:
    while True:
        choice = menu_choice(
            "Heard Frequencies",
            [
                ("1", "List heard frequencies"),
                ("2", "Add a heard frequency"),
                ("0", "Back"),
            ],
        )
        if choice == "0":
            return
        if choice == "1":
            print_available_radios(db_path)
            radio = prompt_text("Filter by radio profile")
            freq = prompt_float("Filter by frequency MHz")
            since = prompt_text("Since timestamp")
            limit = prompt_int("How many rows", default=20, required=True)
            assert limit is not None
            run_menu_action(
                lambda: cmd_heard_list(make_args(db_path, radio=radio, freq=freq, since=since, limit=limit))
            )
            continue

        print_available_radios(db_path)
        freq = prompt_float("Frequency MHz", required=True)
        assert freq is not None
        mode = prompt_text("Mode")
        radio = prompt_text("Radio profile name")
        source = prompt_text("Source or description")
        signal = prompt_text("Signal report")
        location = prompt_text("Location")
        notes = prompt_text("Notes")
        when = prompt_text("Timestamp")
        run_menu_action(
            lambda: cmd_heard_add(
                make_args(
                    db_path,
                    freq=freq,
                    mode=mode,
                    radio=radio,
                    source=source,
                    signal=signal,
                    location=location,
                    notes=notes,
                    when=when,
                )
            )
        )


def menu_channels(db_path: str | None) -> None:
    while True:
        choice = menu_choice(
            "Channel Memories",
            [
                ("1", "List channels"),
                ("2", "Add a channel"),
                ("0", "Back"),
            ],
        )
        if choice == "0":
            return
        if choice == "1":
            print_available_radios(db_path)
            radio = prompt_text("Filter by radio profile")
            limit = prompt_int("How many rows", default=50, required=True)
            assert limit is not None
            run_menu_action(lambda: cmd_channel_list(make_args(db_path, radio=radio, limit=limit)))
            continue

        print_available_radios(db_path)
        radio = prompt_text("Radio profile name")
        memory = prompt_int("Memory number")
        name = prompt_text("Channel name", required=True)
        assert name is not None
        rx = prompt_float("Receive frequency MHz", required=True)
        assert rx is not None
        tx = prompt_float("Transmit frequency MHz")
        duplex = prompt_choice("Duplex", ["simplex", "+", "-", "split", "off"], default="simplex")
        offset = prompt_float("Offset MHz")
        tone_mode = prompt_choice("Tone mode", ["none", "Tone", "TSQL", "DTCS", "Cross"], default="none")
        rtone = prompt_float("Encode tone Hz", default=88.5, required=True)
        ctone = prompt_float("Decode tone Hz", default=88.5, required=True)
        assert rtone is not None and ctone is not None
        dtcs = prompt_text("DTCS code", default="023")
        rx_dtcs = prompt_text("RX DTCS code", default="023")
        dtcs_polarity = prompt_text("DTCS polarity", default="NN")
        cross_mode = prompt_text("Cross mode", default="Tone->Tone")
        mode = prompt_text("Mode", default="FM")
        step = prompt_float("Tuning step kHz", default=5.0, required=True)
        assert step is not None
        skip = prompt_text("Skip flag", default="")
        power = prompt_text("Power label", default="")
        comment = prompt_text("Comment")
        run_menu_action(
            lambda: cmd_channel_add(
                make_args(
                    db_path,
                    radio=radio,
                    memory=memory,
                    name=name,
                    rx=rx,
                    tx=tx,
                    duplex=duplex,
                    offset=offset,
                    tone_mode=tone_mode,
                    rtone=rtone,
                    ctone=ctone,
                    dtcs=dtcs,
                    rx_dtcs=rx_dtcs,
                    dtcs_polarity=dtcs_polarity,
                    cross_mode=cross_mode,
                    mode=mode,
                    step=step,
                    skip=skip,
                    power=power,
                    comment=comment,
                )
            )
        )


def menu_exports(db_path: str | None) -> None:
    while True:
        choice = menu_choice(
            "Export CSV",
            [
                ("1", "Export contacts CSV"),
                ("2", "Export heard frequencies CSV"),
                ("3", "Export CHIRP channels CSV"),
                ("0", "Back"),
            ],
        )
        if choice == "0":
            return

        print_available_radios(db_path)
        path = prompt_text("Output path", required=True)
        assert path is not None
        radio = prompt_text("Filter by radio profile")
        if choice == "1":
            run_menu_action(lambda: cmd_export_contacts(make_args(db_path, path=path, radio=radio)))
        elif choice == "2":
            run_menu_action(lambda: cmd_export_heard(make_args(db_path, path=path, radio=radio)))
        else:
            run_menu_action(lambda: cmd_export_chirp_csv(make_args(db_path, path=path, radio=radio)))


def menu_chirp(db_path: str | None) -> None:
    while True:
        choice = menu_choice(
            "CHIRP Tools",
            [
                ("1", "Check CHIRP availability"),
                ("2", "List CHIRP-supported radios"),
                ("3", "Download image from radio"),
                ("4", "Upload image to radio"),
                ("5", "Apply channels into an image"),
                ("6", "Program a radio end-to-end"),
                ("7", "Show recommended workflow"),
                ("0", "Back"),
            ],
        )
        if choice == "0":
            return
        if choice == "1":
            run_menu_action(lambda: cmd_chirp_doctor(make_args(db_path)))
            continue
        if choice == "2":
            run_menu_action(lambda: cmd_chirp_list_radios(make_args(db_path)))
            continue

        print_available_radios(db_path)
        if choice == "3":
            radio = prompt_text("Radio profile name", required=True)
            image = prompt_text("Image path", required=True)
            assert radio is not None and image is not None
            serial = prompt_text("Override serial port")
            run_menu_action(lambda: cmd_chirp_download_image(make_args(db_path, radio=radio, image=image, serial=serial)))
        elif choice == "4":
            radio = prompt_text("Radio profile name", required=True)
            image = prompt_text("Image path", required=True)
            assert radio is not None and image is not None
            serial = prompt_text("Override serial port")
            run_menu_action(lambda: cmd_chirp_upload_image(make_args(db_path, radio=radio, image=image, serial=serial)))
        elif choice == "5":
            channels_from = prompt_text("Channel source profile", required=True)
            image = prompt_text("Image path", required=True)
            assert channels_from is not None and image is not None
            auto_number_from = prompt_int("Auto-number blank channels from memory")
            backup = prompt_bool("Create a backup first", default=True)
            run_menu_action(
                lambda: cmd_chirp_apply_image(
                    make_args(
                        db_path,
                        channels_from=channels_from,
                        image=image,
                        auto_number_from=auto_number_from,
                        backup=backup,
                    )
                )
            )
        elif choice == "6":
            radio = prompt_text("Target radio profile", required=True)
            image = prompt_text("Working image path", required=True)
            assert radio is not None and image is not None
            channels_from = prompt_text("Channel source profile, blank to use same profile")
            serial = prompt_text("Override serial port")
            auto_number_from = prompt_int("Auto-number blank channels from memory")
            no_download = prompt_bool("Reuse an existing image instead of downloading first", default=False)
            backup = prompt_bool("Create a backup first", default=True)
            run_menu_action(
                lambda: cmd_chirp_program_radio(
                    make_args(
                        db_path,
                        radio=radio,
                        image=image,
                        channels_from=channels_from,
                        serial=serial,
                        auto_number_from=auto_number_from,
                        no_download=no_download,
                        backup=backup,
                    )
                )
            )
        else:
            radio = prompt_text("Radio profile name", required=True)
            assert radio is not None
            csv = prompt_text("Suggested CSV path", default="channels.csv")
            image = prompt_text("Suggested image path", default="radio.img")
            run_menu_action(lambda: cmd_chirp_workflow(make_args(db_path, radio=radio, csv=csv, image=image)))


def menu_time_tools(db_path: str | None) -> None:
    while True:
        choice = menu_choice(
            "Time Tools",
            [
                ("1", "Show current time"),
                ("2", "Convert a timestamp"),
                ("0", "Back"),
            ],
        )
        if choice == "0":
            return
        if choice == "1":
            zones = prompt_csv_zones()
            run_menu_action(lambda: cmd_time_now(make_args(db_path, tz=zones)))
            continue

        timestamp = prompt_text("Timestamp to convert", required=True)
        assert timestamp is not None
        zones = prompt_csv_zones()
        run_menu_action(lambda: cmd_time_convert(make_args(db_path, timestamp=timestamp, tz=zones)))


def menu_database(db_path: str | None) -> None:
    while True:
        choice = menu_choice(
            "Database",
            [
                ("1", "Initialize database"),
                ("2", "Show stats"),
                ("3", "Show database path"),
                ("0", "Back"),
            ],
        )
        if choice == "0":
            return
        if choice == "1":
            run_menu_action(lambda: cmd_init(make_args(db_path)))
        elif choice == "2":
            run_menu_action(lambda: cmd_stats(make_args(db_path)))
        else:
            print(resolve_db_path(db_path))
            print()
            pause()


def run_interactive_menu(db_path: str | None) -> int:
    while True:
        show_menu_header(db_path)
        choice = menu_choice(
            "Main Menu",
            [
                ("1", "Dashboard and stats"),
                ("2", "Radio profiles"),
                ("3", "Contacts"),
                ("4", "Heard frequencies"),
                ("5", "Channel memories"),
                ("6", "Export CSV"),
                ("7", "CHIRP tools"),
                ("8", "Time tools"),
                ("9", "Database"),
                ("0", "Exit"),
            ],
        )
        if choice == "0":
            print("Exiting Horizon RF.")
            return 0
        if choice == "1":
            run_menu_action(lambda: cmd_stats(make_args(db_path)))
        elif choice == "2":
            menu_radio_profiles(db_path)
        elif choice == "3":
            menu_contacts(db_path)
        elif choice == "4":
            menu_heard(db_path)
        elif choice == "5":
            menu_channels(db_path)
        elif choice == "6":
            menu_exports(db_path)
        elif choice == "7":
            menu_chirp(db_path)
        elif choice == "8":
            menu_time_tools(db_path)
        else:
            menu_database(db_path)


def cmd_menu(args: argparse.Namespace) -> int:
    return run_interactive_menu(args.db)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="horizon-rf",
        description="Track radio contacts, heard frequencies, and channel memories with CHIRP export support.",
    )
    parser.add_argument("--db", help="Path to the SQLite database file.")
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    subparsers = parser.add_subparsers(dest="command", required=False)

    menu_parser = subparsers.add_parser("menu", help="Open the interactive menu.")
    menu_parser.set_defaults(func=cmd_menu)

    init_parser = subparsers.add_parser("init", help="Create the database if it does not already exist.")
    init_parser.set_defaults(func=cmd_init)

    radio_parser = subparsers.add_parser("radio", help="Manage radio profiles.")
    radio_subparsers = radio_parser.add_subparsers(dest="radio_command", required=True)

    radio_add = radio_subparsers.add_parser("add", help="Add a radio profile.")
    radio_add.add_argument("--name", required=True, help="Short profile name used by other commands.")
    radio_add.add_argument("--model", help="Human-friendly radio model name.")
    radio_add.add_argument("--chirp-id", help="Exact radio identifier used by `chirpc -r`.")
    radio_add.add_argument("--serial", help="Default serial port for this radio profile.")
    radio_add.add_argument("--notes", help="Free-form notes.")
    radio_add.set_defaults(func=cmd_radio_add)

    radio_list = radio_subparsers.add_parser("list", help="List stored radio profiles.")
    radio_list.set_defaults(func=cmd_radio_list)

    contact_parser = subparsers.add_parser("contact", help="Track contacts you made.")
    contact_subparsers = contact_parser.add_subparsers(dest="contact_command", required=True)

    contact_add = contact_subparsers.add_parser("add", help="Log a contact.")
    contact_add.add_argument("--callsign", required=True, help="Contact callsign.")
    contact_add.add_argument("--name", help="Operator name.")
    contact_add.add_argument("--freq", type=float, help="Frequency in MHz.")
    contact_add.add_argument("--mode", help="Operating mode, for example FM, AM, SSB, DMR.")
    contact_add.add_argument("--radio", help="Radio profile name.")
    contact_add.add_argument("--sent", help="Signal report you sent.")
    contact_add.add_argument("--received", help="Signal report you received.")
    contact_add.add_argument("--location", help="Where you were operating.")
    contact_add.add_argument("--notes", help="Free-form notes.")
    contact_add.add_argument("--when", help="Timestamp, defaults to now.")
    contact_add.set_defaults(func=cmd_contact_add)

    contact_list = contact_subparsers.add_parser("list", help="List contacts.")
    contact_list.add_argument("--radio", help="Filter by radio profile name.")
    contact_list.add_argument("--callsign", help="Filter by callsign.")
    contact_list.add_argument("--freq", type=float, help="Filter by exact frequency in MHz.")
    contact_list.add_argument("--since", help="Show records on or after the given timestamp.")
    contact_list.add_argument("--limit", type=int, default=20, help="Maximum rows to return.")
    contact_list.set_defaults(func=cmd_contact_list)

    heard_parser = subparsers.add_parser("heard", help="Track frequencies you heard.")
    heard_subparsers = heard_parser.add_subparsers(dest="heard_command", required=True)

    heard_add = heard_subparsers.add_parser("add", help="Log a heard frequency.")
    heard_add.add_argument("--freq", type=float, required=True, help="Frequency in MHz.")
    heard_add.add_argument("--mode", help="Operating mode.")
    heard_add.add_argument("--radio", help="Radio profile name.")
    heard_add.add_argument("--source", help="What you think the signal was.")
    heard_add.add_argument("--signal", help="Signal report or signal strength note.")
    heard_add.add_argument("--location", help="Where you heard it.")
    heard_add.add_argument("--notes", help="Free-form notes.")
    heard_add.add_argument("--when", help="Timestamp, defaults to now.")
    heard_add.set_defaults(func=cmd_heard_add)

    heard_list = heard_subparsers.add_parser("list", help="List heard frequencies.")
    heard_list.add_argument("--radio", help="Filter by radio profile name.")
    heard_list.add_argument("--freq", type=float, help="Filter by exact frequency in MHz.")
    heard_list.add_argument("--since", help="Show records on or after the given timestamp.")
    heard_list.add_argument("--limit", type=int, default=20, help="Maximum rows to return.")
    heard_list.set_defaults(func=cmd_heard_list)

    channel_parser = subparsers.add_parser("channel", help="Manage channel memories.")
    channel_subparsers = channel_parser.add_subparsers(dest="channel_command", required=True)

    channel_add = channel_subparsers.add_parser("add", help="Add a channel memory.")
    channel_add.add_argument("--radio", help="Radio profile name.")
    channel_add.add_argument("--memory", type=int, help="Memory number.")
    channel_add.add_argument("--name", required=True, help="Memory label.")
    channel_add.add_argument("--rx", type=float, required=True, help="Receive frequency in MHz.")
    channel_add.add_argument("--tx", type=float, help="Transmit frequency in MHz.")
    channel_add.add_argument(
        "--duplex",
        choices=["simplex", "+", "-", "split", "off"],
        default="simplex",
        help="Duplex mode.",
    )
    channel_add.add_argument("--offset", type=float, help="Offset in MHz for + or - duplex.")
    channel_add.add_argument(
        "--tone-mode",
        choices=["none", "Tone", "TSQL", "DTCS", "Cross"],
        default="none",
        help="CHIRP tone mode.",
    )
    channel_add.add_argument("--rtone", type=float, default=88.5, help="Encode tone frequency.")
    channel_add.add_argument("--ctone", type=float, default=88.5, help="Decode tone frequency.")
    channel_add.add_argument("--dtcs", default="023", help="DTCS code.")
    channel_add.add_argument("--rx-dtcs", default="023", help="Receive DTCS code.")
    channel_add.add_argument("--dtcs-polarity", default="NN", help="DTCS polarity.")
    channel_add.add_argument("--cross-mode", default="Tone->Tone", help="Cross mode.")
    channel_add.add_argument("--mode", default="FM", help="Modulation mode.")
    channel_add.add_argument("--step", type=float, default=5.0, help="Tuning step in kHz.")
    channel_add.add_argument("--skip", default="", help="Skip flag.")
    channel_add.add_argument("--power", default="", help="Power label.")
    channel_add.add_argument("--comment", help="Channel comment.")
    channel_add.set_defaults(func=cmd_channel_add)

    channel_list = channel_subparsers.add_parser("list", help="List stored channels.")
    channel_list.add_argument("--radio", help="Filter by radio profile name.")
    channel_list.add_argument("--limit", type=int, default=50, help="Maximum rows to return.")
    channel_list.set_defaults(func=cmd_channel_list)

    export_parser = subparsers.add_parser("export", help="Export stored data.")
    export_subparsers = export_parser.add_subparsers(dest="export_command", required=True)

    export_contacts = export_subparsers.add_parser("contacts", help="Export contacts to CSV.")
    export_contacts.add_argument("path", help="Target CSV path, or - for stdout.")
    export_contacts.add_argument("--radio", help="Filter by radio profile name.")
    export_contacts.set_defaults(func=cmd_export_contacts)

    export_heard = export_subparsers.add_parser("heard", help="Export heard frequencies to CSV.")
    export_heard.add_argument("path", help="Target CSV path, or - for stdout.")
    export_heard.add_argument("--radio", help="Filter by radio profile name.")
    export_heard.set_defaults(func=cmd_export_heard)

    export_chirp = export_subparsers.add_parser("chirp-csv", help="Export channel memories in CHIRP CSV format.")
    export_chirp.add_argument("path", help="Target CSV path, or - for stdout.")
    export_chirp.add_argument("--radio", help="Filter by radio profile name.")
    export_chirp.set_defaults(func=cmd_export_chirp_csv)

    stats_parser = subparsers.add_parser("stats", help="Show useful totals and recent activity.")
    stats_parser.set_defaults(func=cmd_stats)

    time_parser = subparsers.add_parser("time", help="Show current time or convert a timestamp.")
    time_subparsers = time_parser.add_subparsers(dest="time_command", required=True)

    time_now = time_subparsers.add_parser("now", help="Show current time in one or more zones.")
    time_now.add_argument("--tz", action="append", help="Time zone name. Use multiple times to show several.")
    time_now.set_defaults(func=cmd_time_now)

    time_convert = time_subparsers.add_parser("convert", help="Convert a timestamp into one or more zones.")
    time_convert.add_argument("timestamp", help="Timestamp to convert.")
    time_convert.add_argument("--tz", action="append", help="Time zone name. Use multiple times to show several.")
    time_convert.set_defaults(func=cmd_time_convert)

    chirp_parser = subparsers.add_parser("chirp", help="Optional CHIRP integration helpers.")
    chirp_subparsers = chirp_parser.add_subparsers(dest="chirp_command", required=True)

    chirp_doctor = chirp_subparsers.add_parser("doctor", help="Check whether chirpc is installed.")
    chirp_doctor.set_defaults(func=cmd_chirp_doctor)

    chirp_radios = chirp_subparsers.add_parser("list-radios", help="List radios known to chirpc.")
    chirp_radios.set_defaults(func=cmd_chirp_list_radios)

    chirp_download = chirp_subparsers.add_parser("download-image", help="Download a CHIRP image from a radio.")
    chirp_download.add_argument("--radio", required=True, help="Radio profile name.")
    chirp_download.add_argument("--image", required=True, help="Path for the image file.")
    chirp_download.add_argument("--serial", help="Override the stored serial port.")
    chirp_download.set_defaults(func=cmd_chirp_download_image)

    chirp_upload = chirp_subparsers.add_parser("upload-image", help="Upload a CHIRP image to a radio.")
    chirp_upload.add_argument("--radio", required=True, help="Radio profile name.")
    chirp_upload.add_argument("--image", required=True, help="Path to the image file.")
    chirp_upload.add_argument("--serial", help="Override the stored serial port.")
    chirp_upload.set_defaults(func=cmd_chirp_upload_image)

    chirp_apply = chirp_subparsers.add_parser(
        "apply-image",
        help="Write stored channels into an existing CHIRP image.",
    )
    chirp_apply.add_argument("--channels-from", required=True, help="Profile name that owns the channel memories to apply.")
    chirp_apply.add_argument("--image", required=True, help="Existing CHIRP image to modify in place.")
    chirp_apply.add_argument(
        "--auto-number-from",
        type=int,
        help="Temporarily assign memory numbers to channels that do not have one yet.",
    )
    chirp_apply.add_argument("--backup", action="store_true", help="Write a .bak copy before modifying the image.")
    chirp_apply.set_defaults(func=cmd_chirp_apply_image)

    chirp_program = chirp_subparsers.add_parser(
        "program-radio",
        help="Download a CHIRP image, apply stored channels, and upload it back to the radio.",
    )
    chirp_program.add_argument("--radio", required=True, help="Target radio profile name.")
    chirp_program.add_argument("--image", required=True, help="Working CHIRP image path.")
    chirp_program.add_argument("--channels-from", help="Override the profile used as the channel source.")
    chirp_program.add_argument("--serial", help="Override the stored serial port.")
    chirp_program.add_argument(
        "--auto-number-from",
        type=int,
        help="Temporarily assign memory numbers to channels that do not have one yet.",
    )
    chirp_program.add_argument("--no-download", action="store_true", help="Reuse an existing image instead of downloading first.")
    chirp_program.add_argument("--backup", action="store_true", help="Write a .bak copy before modifying the image.")
    chirp_program.set_defaults(func=cmd_chirp_program_radio)

    chirp_workflow = chirp_subparsers.add_parser("workflow", help="Print a safe CHIRP workflow for a radio profile.")
    chirp_workflow.add_argument("--radio", required=True, help="Radio profile name.")
    chirp_workflow.add_argument("--csv", default="channels.csv", help="Suggested CSV path.")
    chirp_workflow.add_argument("--image", default="radio.img", help="Suggested image path.")
    chirp_workflow.set_defaults(func=cmd_chirp_workflow)

    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        if args.command == "menu":
            return cmd_menu(args)
        if args.command is None:
            if is_interactive_terminal():
                return cmd_menu(args)
            parser.print_help()
            return 0
        return args.func(args)
    except (ValueError, sqlite3.IntegrityError, ChirpError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
