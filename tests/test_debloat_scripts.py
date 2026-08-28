# SPDX-License-Identifier: MIT

from __future__ import annotations

import re
from pathlib import Path
from typing import Final

DEBLOAT_DIR: Final = Path(__file__).resolve().parents[1] / "scripts" / "windows" / "debloat"
SAFE_SCHEDULED_TASKS: Final = (
    r"\Microsoft\Office\OfficeTelemetryAgentFallBack2016",
    r"\Microsoft\Office\OfficeTelemetryAgentLogOn2016",
    r"\Microsoft\Windows\Application Experience\AitAgent",
    r"\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
    r"\Microsoft\Windows\Application Experience\ProgramDataUpdater",
    r"\Microsoft\Windows\Application Experience\ProgramInventoryUpdater",
    r"\Microsoft\Windows\Autochk\Proxy",
    r"\Microsoft\Windows\Customer Experience Improvement Program\BthSQM",
    r"\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
    r"\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask",
    r"\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
    r"\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
    r"\Microsoft\Windows\Feedback\Siuf\DmClient",
    r"\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload",
    r"\Microsoft\Windows\Maps\MapsToastTask",
    r"\Microsoft\Windows\Maps\MapsUpdateTask",
    r"\Microsoft\Windows\PI\Sqm-Tasks",
    r"\Microsoft\Windows\RetailDemo\CleanupOfflineContent",
    r"\Microsoft\Windows\Windows Error Reporting\QueueReporting",
    r"\Microsoft\Windows\WindowsAI\Copilot\CopilotDataCollectionTask",
    r"\Microsoft\Windows\WindowsAI\Insights\InsightsDataCollectionTask",
)


def _read_script(relative_path: str) -> str:
    return (DEBLOAT_DIR / relative_path).read_text(encoding="utf-8")


def _scheduled_tasks(script: str) -> tuple[str, ...]:
    return tuple(re.findall(r'^\s*"([^"]+)"[,]?\s*$', script, flags=re.MULTILINE))


def test_scheduled_tasks_apply_uses_safe_allowlist() -> None:
    # Given
    script = _read_script("scheduled_tasks.ps1")

    # When
    tasks = _scheduled_tasks(script)

    # Then
    assert tasks == SAFE_SCHEDULED_TASKS


def test_scheduled_tasks_undo_matches_apply() -> None:
    # Given
    apply_script = _read_script("scheduled_tasks.ps1")
    undo_script = _read_script("undo/scheduled_tasks.ps1")

    # When
    apply_tasks = _scheduled_tasks(apply_script)
    undo_tasks = _scheduled_tasks(undo_script)

    # Then
    assert undo_tasks == apply_tasks


def test_scheduled_tasks_apply_does_not_terminate_running_tasks() -> None:
    # Given
    script = _read_script("scheduled_tasks.ps1")

    # When
    normalized_script = script.casefold()

    # Then
    assert "schtasks /end" not in normalized_script
