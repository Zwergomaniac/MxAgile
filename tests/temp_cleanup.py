"""Bounded cleanup for suite-owned Windows temporary directories."""

from __future__ import annotations

import shutil
import tempfile
import time
import warnings
from pathlib import Path
from tempfile import TemporaryDirectory


def cleanup_temporary_directory(
    temporary: TemporaryDirectory[str], *, expected_prefix: str, attempts: int = 20
) -> None:
    root = Path(temporary.name)
    temp_parent = Path(tempfile.gettempdir()).resolve()
    if root.parent.resolve() != temp_parent or not root.name.startswith(expected_prefix):
        raise RuntimeError(f"Refusing to clean an unexpected test temp path: {root}")
    if attempts < 1:
        raise ValueError("attempts must be at least one")

    last_error: PermissionError | None = None
    try:
        temporary.cleanup()
    except PermissionError as error:
        last_error = error
    if not root.exists():
        return

    for attempt in range(attempts):
        try:
            shutil.rmtree(root)
        except FileNotFoundError:
            return
        except PermissionError as error:
            last_error = error
        if not root.exists():
            return
        if attempt + 1 < attempts:
            time.sleep(min(0.1 * (attempt + 1), 0.5))

    try:
        remaining = list(root.rglob("*"))
    except OSError as error:
        raise RuntimeError(f"Could not inspect remaining test temp artifacts under {root}") from error
    if remaining:
        raise RuntimeError(
            f"Test temp cleanup left artifacts under {root}: {remaining[0]}"
        ) from last_error

    try:
        root.rmdir()
    except FileNotFoundError:
        return
    except PermissionError as error:
        warnings.warn(
            f"Suite-owned temporary root remains empty after {attempts} cleanup attempts: {root}",
            RuntimeWarning,
        )
        return
