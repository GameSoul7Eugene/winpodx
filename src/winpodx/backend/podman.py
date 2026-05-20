"""Podman backend for running Windows container."""

from __future__ import annotations

import logging
import subprocess
import time

from winpodx.backend.base import Backend
from winpodx.utils.paths import config_dir

log = logging.getLogger(__name__)


class PodmanBackend(Backend):
    def _compose_file(self) -> str:
        return str(config_dir() / "compose.yaml")

    def _compose_cmd(self) -> list[str]:
        # Prefer podman-compose directly (avoids docker-compose plugin hijacking)
        import shutil

        if shutil.which("podman-compose"):
            return ["podman-compose", "-f", self._compose_file()]
        return ["podman", "compose", "-f", self._compose_file()]

    def start(self) -> None:
        try:
            subprocess.run(
                [*self._compose_cmd(), "up", "-d"],
                check=True,
                capture_output=True,
                text=True,
                timeout=120,
            )
            log.info("Pod started (podman)")
        except subprocess.CalledProcessError as e:
            log.error("podman compose up failed: %s", e.stderr.strip())
            raise
        except subprocess.TimeoutExpired:
            log.error("podman compose up timed out (120s)")
            raise

    def stop(self) -> None:
        try:
            result = subprocess.run(
                [*self._compose_cmd(), "down"],
                capture_output=True,
                text=True,
                timeout=60,
            )
            if result.returncode != 0:
                log.warning(
                    "podman compose down failed (rc=%d): %s",
                    result.returncode,
                    result.stderr.strip(),
                )
        except subprocess.TimeoutExpired:
            log.error("podman compose down timed out (60s)")

    def _container_state(self) -> str:
        """Return the lower-cased container state, or empty string if unavailable."""
        try:
            result = subprocess.run(
                [
                    "podman",
                    "ps",
                    "-a",
                    "--filter",
                    f"name={self.cfg.pod.container_name}",
                    "--format",
                    "{{.State}}",
                ],
                capture_output=True,
                text=True,
                timeout=15,
            )
            if result.returncode != 0:
                log.warning(
                    "podman ps failed (rc=%d): %s",
                    result.returncode,
                    result.stderr.strip(),
                )
                return ""
            return result.stdout.strip().lower()
        except FileNotFoundError:
            log.warning("podman not found in PATH")
            return ""

    def is_running(self) -> bool:
        # Treat paused as alive; pod_status() distinguishes via is_paused().
        state = self._container_state()
        return "running" in state or "paused" in state

    def is_paused(self) -> bool:
        return "paused" in self._container_state()

    def uptime_secs(self) -> int | None:
        """Seconds since the container was last started, or None on probe failure.

        Tries inspect first by the configured container name and falls
        back to the compose-prefixed name (``{project}_{name}``) +
        ``--format`` variants. podman-compose sometimes overrides the
        explicit ``container_name:`` directive with the project prefix,
        so a bare inspect on ``cfg.pod.container_name`` will fail with
        ``no such object`` even though the container is running. The
        legacy ``is_running`` uses ``ps -a --filter name=^X$`` which
        does a regex match, so it succeeds with either naming.
        """
        import datetime
        import subprocess

        candidates = [
            self.cfg.pod.container_name,
            # podman-compose project-prefixed variants (project name is
            # `name:` in compose.yaml = "winpodx").
            f"winpodx_{self.cfg.pod.container_name}",
            f"winpodx_{self.cfg.pod.container_name}_1",
        ]
        ts = ""
        last_stderr = ""
        for name in candidates:
            try:
                result = subprocess.run(
                    ["podman", "inspect", "-f", "{{.State.StartedAt}}", name],
                    capture_output=True,
                    text=True,
                    timeout=5,
                    check=False,
                )
            except (FileNotFoundError, subprocess.TimeoutExpired):
                return None
            if result.returncode == 0 and result.stdout.strip():
                ts = result.stdout.strip()
                break
            last_stderr = (result.stderr or "").strip()

        if not ts:
            log.debug(
                "podman inspect StartedAt failed for all candidates %r: %s",
                candidates,
                last_stderr,
            )
            return None
        # podman prints RFC3339 (`2026-05-20T14:00:00.123456789Z`). Python's
        # fromisoformat handles `+00:00` but not bare `Z` until 3.11, and
        # the nanoseconds suffix until 3.11 either — strip both for the
        # 3.9 / 3.10 fallback path.
        ts = ts.replace("Z", "+00:00")
        if "." in ts:
            head, _, tail = ts.partition(".")
            # Truncate fractional seconds to microseconds (6 digits) so
            # the parser accepts it across Python versions.
            frac, _, tz = tail.partition("+")
            if tz:
                ts = f"{head}.{frac[:6]}+{tz}"
            else:
                ts = f"{head}.{frac[:6]}"
        try:
            started = datetime.datetime.fromisoformat(ts)
        except ValueError:
            log.debug("Could not parse podman StartedAt timestamp %r", ts)
            return None
        # Guard against the Go zero time ``0001-01-01T00:00:00Z`` that
        # podman emits for containers that never started.
        if started.year < 2000:
            return None
        now = datetime.datetime.now(tz=started.tzinfo)
        delta = (now - started).total_seconds()
        return max(0, int(delta))

    def get_ip(self) -> str:
        return self.cfg.rdp.ip or "127.0.0.1"

    def wait_for_ready(self, timeout: int = 300) -> bool:
        """Wait for the container to be running and RDP port available."""
        from winpodx.core.pod import check_rdp_port

        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if (
                self.is_running()
                and not self.is_paused()
                and check_rdp_port(self.get_ip(), self.cfg.rdp.port, timeout=3)
            ):
                return True
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            time.sleep(min(1.0, remaining))
        return False
