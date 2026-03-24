from __future__ import annotations

import shutil
import subprocess
from pathlib import Path
from typing import Sequence


class ChirpError(RuntimeError):
    """Raised when CHIRP integration fails."""


def chirpc_path() -> str | None:
    return shutil.which("chirpc")


def ensure_chirpc() -> str:
    path = chirpc_path()
    if not path:
        raise ChirpError(
            "chirpc was not found on PATH. Install CHIRP and make sure the `chirpc` command is available."
        )
    return path


def run_chirpc(
    arguments: Sequence[str], capture_output: bool = True, check: bool = True
) -> subprocess.CompletedProcess[str]:
    executable = ensure_chirpc()
    completed = subprocess.run(
        [executable, *arguments],
        text=True,
        capture_output=capture_output,
        check=False,
    )
    if check and completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "chirpc exited with a non-zero status."
        raise ChirpError(detail)
    return completed


def list_radios() -> str:
    result = run_chirpc(["--list-radios"])
    return result.stdout.strip()


def version_text() -> str:
    try:
        result = run_chirpc(["--version"])
    except ChirpError:
        return "installed, but version lookup failed"
    return result.stdout.strip() or "installed"


def download_image(chirp_id: str, serial_port: str, image_path: Path) -> None:
    image_path = image_path.expanduser().resolve()
    image_path.parent.mkdir(parents=True, exist_ok=True)
    run_chirpc(["-r", chirp_id, "--serial", serial_port, "--mmap", str(image_path), "--download-mmap"])


def upload_image(chirp_id: str, serial_port: str, image_path: Path) -> None:
    image_path = image_path.expanduser().resolve()
    run_chirpc(["-r", chirp_id, "--serial", serial_port, "--mmap", str(image_path), "--upload-mmap"])


def clear_memory(image_path: Path, memory: int) -> None:
    image_path = image_path.expanduser().resolve()
    run_chirpc(["--mmap", str(image_path), "--clear-mem", str(memory)])


def _run_batch_memory_update(
    image_path: Path, memory: int, field_options: Sequence[tuple[str, str | None]]
) -> subprocess.CompletedProcess[str]:
    arguments: list[str] = ["--mmap", str(image_path)]
    for option, value in field_options:
        arguments.append(option)
        if value is not None:
            arguments.append(value)
    arguments.append(str(memory))
    return run_chirpc(arguments, check=False)


def _run_inline_memory_update(image_path: Path, memory: int, option: str, value: str | None) -> None:
    arguments = ["--mmap", str(image_path), option]
    if value is None:
        arguments.append(str(memory))
    else:
        if ":" in value:
            raise ChirpError(
                f"Cannot use fallback CHIRP inline syntax for memory {memory}: value for {option} contains a colon."
            )
        arguments.append(f"{memory}:{value}")
    run_chirpc(arguments)


def apply_memory_fields(image_path: Path, memory: int, field_options: Sequence[tuple[str, str | None]]) -> str:
    image_path = image_path.expanduser().resolve()
    clear_memory(image_path, memory)

    batch_result = _run_batch_memory_update(image_path, memory, field_options)
    if batch_result.returncode == 0:
        return "legacy-positional"

    first_error = batch_result.stderr.strip() or batch_result.stdout.strip() or "batch memory update failed"
    clear_memory(image_path, memory)

    try:
        for option, value in field_options:
            _run_inline_memory_update(image_path, memory, option, value)
    except ChirpError as second_error:
        raise ChirpError(
            f"Failed to program memory {memory}. Positional syntax error: {first_error}. "
            f"Inline fallback error: {second_error}"
        ) from second_error

    return "inline"
