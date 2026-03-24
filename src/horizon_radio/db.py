from __future__ import annotations

import os
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Sequence

APP_NAME = "horizon-rf"
DB_ENV_VAR = "HORIZON_RF_DB"

SCHEMA = """
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS radios (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    model TEXT,
    chirp_id TEXT,
    serial_port TEXT,
    notes TEXT,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS contacts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    callsign TEXT NOT NULL,
    operator_name TEXT,
    frequency_mhz REAL,
    mode TEXT,
    radio_id INTEGER REFERENCES radios(id) ON DELETE SET NULL,
    report_sent TEXT,
    report_received TEXT,
    location TEXT,
    notes TEXT,
    contacted_at TEXT NOT NULL,
    created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_contacts_contacted_at ON contacts(contacted_at DESC);
CREATE INDEX IF NOT EXISTS idx_contacts_frequency ON contacts(frequency_mhz);

CREATE TABLE IF NOT EXISTS heard_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    frequency_mhz REAL NOT NULL,
    mode TEXT,
    radio_id INTEGER REFERENCES radios(id) ON DELETE SET NULL,
    source TEXT,
    signal_report TEXT,
    location TEXT,
    notes TEXT,
    heard_at TEXT NOT NULL,
    created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_heard_heard_at ON heard_entries(heard_at DESC);
CREATE INDEX IF NOT EXISTS idx_heard_frequency ON heard_entries(frequency_mhz);

CREATE TABLE IF NOT EXISTS channels (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    radio_id INTEGER REFERENCES radios(id) ON DELETE SET NULL,
    memory INTEGER,
    name TEXT NOT NULL,
    rx_frequency_mhz REAL NOT NULL,
    tx_frequency_mhz REAL,
    duplex TEXT NOT NULL DEFAULT '',
    offset_mhz REAL,
    tone_mode TEXT NOT NULL DEFAULT '',
    rtone_hz REAL NOT NULL DEFAULT 88.5,
    ctone_hz REAL NOT NULL DEFAULT 88.5,
    dtcs_code TEXT NOT NULL DEFAULT '023',
    rx_dtcs_code TEXT NOT NULL DEFAULT '023',
    dtcs_polarity TEXT NOT NULL DEFAULT 'NN',
    cross_mode TEXT NOT NULL DEFAULT 'Tone->Tone',
    mode TEXT NOT NULL DEFAULT 'FM',
    tune_step_khz REAL NOT NULL DEFAULT 5.0,
    skip TEXT NOT NULL DEFAULT '',
    power TEXT NOT NULL DEFAULT '',
    comment TEXT,
    created_at TEXT NOT NULL,
    UNIQUE (radio_id, memory)
);

CREATE INDEX IF NOT EXISTS idx_channels_memory ON channels(memory);
CREATE INDEX IF NOT EXISTS idx_channels_frequency ON channels(rx_frequency_mhz);
"""


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def isoformat(value: datetime | None = None) -> str:
    return (value or now_utc()).astimezone(timezone.utc).replace(microsecond=0).isoformat()


def default_data_dir() -> Path:
    home = Path.home()
    if sys.platform == "darwin":
        return home / "Library" / "Application Support" / APP_NAME

    xdg_data_home = os.environ.get("XDG_DATA_HOME")
    if xdg_data_home:
        return Path(xdg_data_home) / APP_NAME

    return home / ".local" / "share" / APP_NAME


def default_db_path() -> Path:
    return default_data_dir() / "radio-log.db"


def fallback_db_path() -> Path:
    return Path.cwd().resolve() / ".horizon-rf" / "radio-log.db"


def resolve_db_path(raw_path: str | os.PathLike[str] | None) -> Path:
    if raw_path:
        return Path(raw_path).expanduser().resolve()

    env_path = os.environ.get(DB_ENV_VAR)
    if env_path:
        return Path(env_path).expanduser().resolve()

    preferred = default_db_path()
    try:
        preferred.parent.mkdir(parents=True, exist_ok=True)
    except PermissionError:
        return fallback_db_path()

    return preferred


def connect(db_path: str | os.PathLike[str] | None = None) -> sqlite3.Connection:
    path = resolve_db_path(db_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(path)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    connection.executescript(SCHEMA)
    return connection


def fetch_one(connection: sqlite3.Connection, query: str, params: Sequence[object] = ()) -> sqlite3.Row | None:
    cursor = connection.execute(query, params)
    return cursor.fetchone()


def fetch_all(connection: sqlite3.Connection, query: str, params: Sequence[object] = ()) -> list[sqlite3.Row]:
    cursor = connection.execute(query, params)
    return cursor.fetchall()


def execute(connection: sqlite3.Connection, query: str, params: Sequence[object] = ()) -> sqlite3.Cursor:
    cursor = connection.execute(query, params)
    connection.commit()
    return cursor


def executemany(
    connection: sqlite3.Connection, query: str, params: Iterable[Sequence[object]]
) -> sqlite3.Cursor:
    cursor = connection.executemany(query, params)
    connection.commit()
    return cursor
