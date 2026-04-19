"""Atomic, flock-guarded JSON read-modify-write for TAB plugin scripts.

Several lifecycle scripts mutate the same JSON artifact concurrently:

  - telemetry.json      (update-telemetry, update-telemetry-subagent,
                         on-task-created, on-tool-failure, on-elicitation,
                         on-teammate-idle)
  - state-full.json     (update-telemetry-subagent, on-task-created,
                         on-subagent-start)
  - vanguard-timeline.json (bin/vanguard-timeline, global across projects)

Without a lock, two scripts can read the same file, compute their
respective updates, and each write back — the later writer silently
loses the other's change (last-writer-wins). Under rare timing, a
reader can also see a half-written file with invalid JSON.

This module provides a single helper that serializes the
read-modify-write cycle and swaps the result in atomically.

Guarantees (POSIX):

  - Exclusive advisory lock is held for the full read -> mutate -> write
    cycle. Multiple callers serialize naturally.
  - os.replace() gives an atomic rename. A concurrent reader either
    sees the old file or the new file, never a partial write.
  - One lock file per target, so unrelated files don't contend.
  - Corrupt JSON on disk is treated as "start from default" rather
    than as a hard error, because hooks are best-effort telemetry.

Limitations:

  - flock is advisory. Every writer that touches these artifacts MUST
    use this helper. A script that opens a file with plain open() and
    json.dump() will still race.
  - On NFS or other non-POSIX filesystems the advisory-lock semantics
    vary. The assumption is that `.tab/` and ${CLAUDE_PLUGIN_DATA}
    live on a POSIX filesystem. Degradation is graceful — readers
    still only see complete files thanks to the atomic rename.

Usage from a bash script:

    python3 - "<session_dir>/telemetry.json" <<'PYEOF'
    import os, sys
    sys.path.insert(0,
        os.path.join(os.environ.get("CLAUDE_PLUGIN_ROOT", ""),
                     "scripts", "lib"))
    from json_atomic import atomic_update
    from pathlib import Path

    def bump(tel):
        tel.setdefault("totals", {})
        tel["totals"]["artifacts_written"] = (
            int(tel["totals"].get("artifacts_written", 0)) + 1
        )
        return tel

    atomic_update(
        Path(sys.argv[1]),
        bump,
        default={"totals": {"artifacts_written": 0}},
    )
    PYEOF
"""
from __future__ import annotations

import errno
import fcntl
import json
import os
import time
from pathlib import Path
from typing import Any, Callable, Optional

__all__ = ["atomic_update", "atomic_append_ndjson", "acquire_flock"]

_DEFAULT_TIMEOUT = 5.0


def atomic_update(
    target: Path,
    mutator: Callable[[Any], Any],
    *,
    default: Any = None,
    indent: int = 2,
    timeout_seconds: float = _DEFAULT_TIMEOUT,
) -> Any:
    """Lock, read, mutate, write atomically. Returns the new value.

    Parameters
    ----------
    target : Path
        JSON file to update. Parent directory is created if missing.
    mutator : callable
        Receives the current JSON-deserialized value (or `default` if
        the file is absent or corrupt) and returns the new value.
        Must not have side effects outside the returned object —
        it may be re-invoked on retry in future versions.
    default : Any
        Value to pass to `mutator` when the file is absent, empty, or
        contains invalid JSON. Defaults to an empty dict.
    indent : int
        Indentation for the serialized output. Set to None for compact.
    timeout_seconds : float
        How long to wait for the exclusive lock. Must accommodate the
        surrounding hook's timeout budget.

    Returns
    -------
    Any
        The value written to disk (the return of `mutator`).

    Raises
    ------
    TimeoutError
        If the lock cannot be acquired within `timeout_seconds`.
    OSError
        On filesystem errors other than lock contention. Hook callers
        should catch and degrade to best-effort no-op.
    """
    target = Path(target)
    target.parent.mkdir(parents=True, exist_ok=True)

    lock_path = target.with_suffix(target.suffix + ".lock")
    tmp_path = target.with_suffix(target.suffix + ".tmp")

    with open(lock_path, "w") as lock_fd:
        acquire_flock(lock_fd, timeout_seconds)
        try:
            current = _read_or_default(target, default)
            updated = mutator(current)
            _write_atomic(tmp_path, target, updated, indent)
            return updated
        finally:
            # Explicit unlock is optional (closing fd releases flock)
            # but keeps intent clear.
            try:
                fcntl.flock(lock_fd, fcntl.LOCK_UN)
            except OSError:
                pass


def atomic_append_ndjson(
    target: Path,
    record: Any,
    *,
    timeout_seconds: float = _DEFAULT_TIMEOUT,
    max_lines: Optional[int] = None,
    max_bytes: Optional[int] = None,
    max_rotations: int = 3,
) -> None:
    """Append one JSON record as a line to an NDJSON file, under lock.

    POSIX already guarantees atomic writes for appends below PIPE_BUF
    (≈4 KiB), so small telemetry records rarely tear. The lock here
    protects against the rarer case where two records exceed that and
    also against readers that might parse mid-append.

    When `max_lines` or `max_bytes` is set and the existing file
    exceeds either cap, the file is rotated BEFORE appending the new
    record. Rotation scheme:

        target           → target.1
        target.1         → target.2
        ...
        target.N-1       → target.N
        target.N         → unlinked (oldest discarded)

    where N is `max_rotations`. A rotation happens inside the flock
    critical section so the invariant "target plus rotations together
    contain at most cap×(N+1) lines / bytes" holds even under
    concurrent writers.

    Parameters
    ----------
    target : Path
        NDJSON file to append to.
    record : Any
        JSON-serializable record. Encoded with no indentation.
    timeout_seconds : float
        Max wait for the flock.
    max_lines : int or None
        If set, rotate when the current file has >= this many lines.
        Disabled when None.
    max_bytes : int or None
        If set, rotate when the current file's on-disk size (bytes)
        >= this value. Checked first (O(1) via stat), so pairs well
        with a large max_lines fallback.
    max_rotations : int
        Keep at most this many old rotations. Default 3 → up to
        ``target`` plus ``target.1`` through ``target.3`` coexist.
    """
    target = Path(target)
    target.parent.mkdir(parents=True, exist_ok=True)

    lock_path = target.with_suffix(target.suffix + ".lock")
    line = json.dumps(record, separators=(",", ":"), ensure_ascii=False) + "\n"

    with open(lock_path, "w") as lock_fd:
        acquire_flock(lock_fd, timeout_seconds)
        try:
            _rotate_ndjson_if_needed(target, max_lines, max_bytes, max_rotations)
            with open(target, "a", encoding="utf-8") as f:
                f.write(line)
        finally:
            try:
                fcntl.flock(lock_fd, fcntl.LOCK_UN)
            except OSError:
                pass


def _rotate_ndjson_if_needed(
    target: Path,
    max_lines: Optional[int],
    max_bytes: Optional[int],
    max_rotations: int,
) -> None:
    """Perform rotation if either cap is exceeded. Caller holds the flock."""
    if max_lines is None and max_bytes is None:
        return
    if not target.exists():
        return

    should_rotate = False
    # Bytes check is O(1) — run first.
    if max_bytes is not None:
        try:
            if target.stat().st_size >= max_bytes:
                should_rotate = True
        except OSError:
            return
    # Line count is O(file) — run only if bytes cap didn't fire.
    if not should_rotate and max_lines is not None:
        try:
            with open(target, "rb") as f:
                n_lines = sum(1 for _ in f)
            if n_lines >= max_lines:
                should_rotate = True
        except OSError:
            return

    if not should_rotate:
        return

    # Build path at rotation index N (N=0 is the live target).
    def rot_path(n: int) -> Path:
        if n == 0:
            return target
        return target.parent / f"{target.name}.{n}"

    # Drop the oldest slot (beyond max_rotations) to make room.
    oldest = rot_path(max_rotations)
    if oldest.exists():
        try:
            oldest.unlink()
        except OSError:
            # If we can't drop the oldest, still try to rotate — the
            # next pass will retry the unlink. Worst case: one extra
            # file lingers; invariant "bounded growth" still holds
            # since max_rotations+1 slots is a fixed small number.
            pass

    # Shift every existing .N-1 to .N, starting from the largest so
    # we don't overwrite. os.replace is atomic (readers either see
    # the old file or the new name).
    for n in range(max_rotations, 0, -1):
        src = rot_path(n - 1)
        dst = rot_path(n)
        if src.exists():
            try:
                os.replace(src, dst)
            except OSError:
                # Partial rotation can leave the file in a usable
                # state — the next append will create a fresh target
                # and the oldest slot might lose one rotation cycle.
                # Better than exploding on the hot path.
                return


def acquire_flock(fd, timeout_seconds: float) -> None:
    """Acquire LOCK_EX with a bounded retry loop.

    fcntl.flock() with LOCK_EX blocks indefinitely by default, which
    would break hook timeout budgets. We instead poll with LOCK_NB.
    """
    deadline = time.monotonic() + max(0.0, timeout_seconds)
    sleep_s = 0.02
    max_sleep_s = 0.25
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return
        except OSError as exc:
            # EWOULDBLOCK / EAGAIN means someone else holds the lock.
            # Any other errno is a genuine failure.
            if exc.errno not in (errno.EAGAIN, errno.EWOULDBLOCK):
                raise
            if time.monotonic() >= deadline:
                raise TimeoutError(
                    f"flock not acquired within {timeout_seconds:.1f}s "
                    f"on fd {fd.name if hasattr(fd, 'name') else fd}"
                ) from exc
            time.sleep(sleep_s)
            sleep_s = min(sleep_s * 1.5, max_sleep_s)


def _read_or_default(path: Path, default: Any) -> Any:
    """Read JSON from path, returning a deep-ish copy of `default` on miss.

    Treats missing, empty, and corrupt files uniformly so hook
    telemetry never aborts on a previous bad write.
    """
    base = {} if default is None else default
    if not path.exists():
        return _copy_default(base)
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return _copy_default(base)
    if not text.strip():
        return _copy_default(base)
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return _copy_default(base)


def _copy_default(value: Any) -> Any:
    """Shallow round-trip so callers can mutate without touching the sentinel."""
    if value is None:
        return {}
    # JSON round-trip gives us a detached, mutable copy for any
    # JSON-serializable default. Non-serializable defaults are
    # a programming error that should surface loudly.
    return json.loads(json.dumps(value))


def _write_atomic(
    tmp_path: Path, target: Path, value: Any, indent: Optional[int]
) -> None:
    """Write `value` to `tmp_path` then atomically rename to `target`."""
    text = json.dumps(value, indent=indent, ensure_ascii=False)
    if indent is not None and not text.endswith("\n"):
        text += "\n"
    # Open with O_TRUNC semantics (default) so a stale tmp from a
    # previous crash is overwritten cleanly.
    tmp_path.write_text(text, encoding="utf-8")
    os.replace(tmp_path, target)
