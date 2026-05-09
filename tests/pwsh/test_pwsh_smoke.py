"""Python-side bridge for the Pester suite under tests/pwsh/.

Two roles:

1. **Without pwsh on PATH** (most dev boxes): cheap parse / balance /
   contract-shape checks on the Pester files. Catches partial edits
   that would crash a real Pester run.

2. **With pwsh on PATH** (CI's pwsh-tests job): shell out to
   ``Invoke-Pester`` and surface results to pytest's reporter. Each
   failed test from Pester maps to one assertion failure here. The
   pure-pwsh job runs Pester directly; this Python wrapper exists so
   ``pytest tests/`` on the Linux dev box also exercises the suite when
   pwsh happens to be available.

Anti-goal: this module does NOT install pwsh. CI does. Local dev runs
without pwsh skip the parse + Pester checks; the file-shape checks
still run.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
PWSH_DIR = REPO_ROOT / "tests" / "pwsh"
HELPERS_PS1 = REPO_ROOT / "config" / "oem" / "install-state-helpers.ps1"
STEPS_PS1 = REPO_ROOT / "config" / "oem" / "install-step-functions.ps1"
FIXTURES_JSON = REPO_ROOT / "tests" / "fixtures" / "redactor_cases.json"
SCHEMA_JSON = REPO_ROOT / "docs" / "design" / "install_failure.schema.json"

PESTER_FILES = [
    PWSH_DIR / "test_install_state_helpers.Tests.ps1",
    PWSH_DIR / "test_step_function_contract.Tests.ps1",
]


# ---------------------------------------------------------------------------
# File-shape checks (run regardless of pwsh availability)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("path", PESTER_FILES, ids=lambda p: p.name)
def test_pester_file_exists_and_nonempty(path: Path) -> None:
    assert path.is_file(), f"missing Pester file: {path}"
    assert path.stat().st_size > 0


def test_redactor_fixtures_exist() -> None:
    assert FIXTURES_JSON.is_file()
    data = json.loads(FIXTURES_JSON.read_text(encoding="utf-8"))
    assert "cases" in data and isinstance(data["cases"], list)
    assert len(data["cases"]) >= 20, "fixture set should cover broad redactor surface"
    # Every case has the four required keys.
    for case in data["cases"]:
        assert set(case.keys()) >= {"id", "description", "input", "expected", "must_not_contain"}


@pytest.mark.parametrize("path", PESTER_FILES, ids=lambda p: p.name)
def test_pester_file_brace_balance(path: Path) -> None:
    """Coarse check that braces balance — catches half-edited Pester files
    on dev boxes without pwsh. Mirrors test_agent_ps1_syntax.py's brace
    balance test."""
    text = path.read_text(encoding="utf-8")
    cleaned: list[str] = []
    for raw in text.splitlines():
        idx = raw.find("#")
        line = raw if idx == -1 else raw[:idx]
        out_chars: list[str] = []
        in_str: str | None = None
        i = 0
        while i < len(line):
            ch = line[i]
            if in_str is None:
                if ch in ("'", '"'):
                    in_str = ch
                else:
                    out_chars.append(ch)
            else:
                if ch == in_str:
                    in_str = None
            i += 1
        cleaned.append("".join(out_chars))
    body = "\n".join(cleaned)
    opens = body.count("{")
    closes = body.count("}")
    assert opens == closes, f"{path.name} brace mismatch: {opens} {{ vs {closes} }}"


@pytest.mark.parametrize("path", PESTER_FILES, ids=lambda p: p.name)
def test_pester_file_uses_describe_and_it(path: Path) -> None:
    """Pester 5+ requires Describe/It blocks. A file without either is
    almost certainly broken (we'd be paying to spin up pwsh for no
    assertions)."""
    text = path.read_text(encoding="utf-8")
    assert re.search(r"^\s*Describe\s+", text, re.MULTILINE), f"{path.name} has no Describe block"
    assert re.search(r"\bIt\s+['\"]", text), f"{path.name} has no It blocks"


# ---------------------------------------------------------------------------
# Pwsh parse + Pester invocation (skipped when pwsh isn't on PATH)
# ---------------------------------------------------------------------------


def _pwsh_path() -> str | None:
    return shutil.which("pwsh")


@pytest.mark.parametrize("path", PESTER_FILES + [HELPERS_PS1, STEPS_PS1], ids=lambda p: p.name)
def test_powershell_parses(path: Path) -> None:
    """If pwsh is on PATH, the .ps1 file must parse without errors."""
    pwsh = _pwsh_path()
    if not pwsh:
        pytest.skip("pwsh not installed on this host")
    cmd = [
        pwsh,
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        (
            "$errors = $null; "
            f"[void][System.Management.Automation.Language.Parser]::ParseFile('{path}', "
            "[ref]$null, [ref]$errors); "
            "if ($errors -and $errors.Count -gt 0) { "
            "  $errors | ForEach-Object { Write-Error $_.ToString() }; exit 1 "
            "}"
        ),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, (
        f"pwsh parse failed for {path.name}:\nstdout={result.stdout}\nstderr={result.stderr}"
    )


def test_invoke_pester_passes() -> None:
    """Run Invoke-Pester against tests/pwsh/ and surface the result.

    Skipped without pwsh + Pester. The CI ``pwsh-tests`` job is the
    authoritative runner; this is a convenience for dev boxes that do
    have pwsh installed.
    """
    pwsh = _pwsh_path()
    if not pwsh:
        pytest.skip("pwsh not installed on this host")

    # Confirm Pester 5+ is available before running. Older Pester (3.x)
    # ships with Windows PowerShell; we explicitly require 5+.
    pester_check = subprocess.run(
        [
            pwsh,
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "(Get-Module -ListAvailable Pester | Where-Object { $_.Version -ge '5.0' } | "
            "Measure-Object).Count",
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if pester_check.returncode != 0 or pester_check.stdout.strip() == "0":
        pytest.skip(
            "Pester >= 5.0 not installed (install with: "
            "Install-Module -Name Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck)"
        )

    # Run Invoke-Pester on the directory; the runner exits non-zero on
    # any failure, which we propagate to pytest.
    result = subprocess.run(
        [
            pwsh,
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            (
                "$cfg = New-PesterConfiguration; "
                f"$cfg.Run.Path = '{PWSH_DIR}'; "
                "$cfg.Run.Exit = $true; "
                "$cfg.Output.Verbosity = 'Detailed'; "
                "Invoke-Pester -Configuration $cfg"
            ),
        ],
        capture_output=True,
        text=True,
        timeout=600,
    )
    assert result.returncode == 0, (
        f"Pester suite failed (rc={result.returncode}):\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
