# Pester 5+ tests for the generic Invoke-WinpodxStep contract in
# config/oem/install-step-functions.ps1.
#
# The contract under test is the 8-point sequence documented in
# docs/design/AGENT_FIRST_INSTALL_DESIGN.md (§"Component contracts ->
# install.bat"):
#
#   1. If marker exists AND post_condition holds -> skip (return 0).
#   2. If marker exists but post_condition fails -> log drift, delete marker,
#      fall through to a fresh run.
#   3. Verify pre-condition; on failure return 1 without running body.
#   4. Run the body.
#   5. Verify post-condition.
#   6. On post-condition fail -> Increment-WinpodxRetry, return 1.
#   7. On retries exhausted -> Write-WinpodxFailure, then return 1.
#   8. On success -> New-WinpodxMarker, return 0.
#
# These tests use synthetic body / pre / post scriptblocks so we can probe
# ordering and side-effects without touching Windows-only surfaces (the
# concrete Phase 0/1/2 step bodies hit registry, netsh, Get-Volume etc.,
# which we cover in real-Windows smoke tests not in CI).

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot    = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:HelpersPath = Join-Path $script:RepoRoot 'config' 'oem' 'install-state-helpers.ps1'
    $script:StepsPath   = Join-Path $script:RepoRoot 'config' 'oem' 'install-step-functions.ps1'

    if (-not (Test-Path $script:HelpersPath)) {
        throw "install-state-helpers.ps1 not present at $script:HelpersPath"
    }
    if (-not (Test-Path $script:StepsPath)) {
        throw "install-step-functions.ps1 not present at $script:StepsPath"
    }

    # Helper functions defined in BeforeAll are visible to BeforeEach /
    # AfterEach / It blocks in the same container (Pester 5 contract).

    function Initialize-FakeWindowsDrive {
        if (-not (Get-PSDrive -Name 'C' -ErrorAction SilentlyContinue)) {
            $root = (New-Item -ItemType Directory `
                -Path (Join-Path ([System.IO.Path]::GetTempPath()) ("winpodx-fakec-" + [guid]::NewGuid())) `
                -Force).FullName
            New-PSDrive -Name 'C' -PSProvider FileSystem -Root $root -Scope Global `
                -ErrorAction Stop | Out-Null
            return $root
        }
        return $null
    }

    function Use-WpxTestStateDir {
        param([string] $SubDir)
        $dir = Join-Path $script:WpxTestRoot $SubDir
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'install_session_id.txt') `
            -Value 'abcd1234-1111-2222-3333-444455556666' -NoNewline
        $script:WpxStateDir        = $dir
        $script:WpxLogPath         = Join-Path $dir 'install.log'
        $script:WpxRetryCountsPath = Join-Path $dir 'retry_counts.json'
        $script:WpxFailurePath     = Join-Path $dir 'install_failure.json'
        $script:WpxSessionIdPath   = Join-Path $dir 'install_session_id.txt'
        # Lower the retry budget so the "retries exhausted" test doesn't take 3 attempts.
        $script:WpxMaxRetries      = 3
        return $dir
    }

    $script:FakeWindowsRoot = Initialize-FakeWindowsDrive

    # Dot-source helpers FIRST (provides marker / retry / log / failure
    # primitives), then steps (provides Invoke-WinpodxStep runner).
    . $script:HelpersPath
    . $script:StepsPath

    $script:WpxTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
        ("winpodx-pester-step-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:WpxTestRoot -Force | Out-Null
}

AfterAll {
    if ($null -ne $script:WpxTestRoot -and (Test-Path -LiteralPath $script:WpxTestRoot)) {
        Remove-Item -LiteralPath $script:WpxTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($null -ne $script:FakeWindowsRoot -and (Test-Path -LiteralPath $script:FakeWindowsRoot)) {
        Remove-PSDrive -Name 'C' -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:FakeWindowsRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Invoke-WinpodxStep contract (success)' {

    BeforeEach {
        $script:CurrentStateDir = Use-WpxTestStateDir -SubDir ("ok-" + [guid]::NewGuid())
        # Side-effect ledger lets us assert ordering.
        $script:Calls = [System.Collections.Generic.List[string]]::new()
    }

    It 'Marker is written AFTER post-condition succeeds (not before body returns)' {
        $calls = $script:Calls
        $rc = Invoke-WinpodxStep `
            -Name 'success_step' `
            -Phase 2 `
            -ErrorClass 'never_used' `
            -VerifyPreCondition  { $calls.Add('pre');  return $true } `
            -Body                { $calls.Add('body'); return 0 } `
            -VerifyPostCondition { $calls.Add('post'); return $true }

        $rc | Should -Be 0

        # Order MUST be pre -> body -> post; marker write happens AFTER all three.
        # (We can't directly observe the marker write inside the runner, but
        # it must be present on disk after Invoke-WinpodxStep returns.)
        $calls | Should -Be @('pre', 'body', 'post')
        Test-Path -LiteralPath (Join-Path $script:CurrentStateDir 'success_step.done') | Should -BeTrue
    }

    It 'Idempotent: re-running a completed step is a no-op (skip via marker)' {
        $calls = $script:Calls
        # First run: full pre/body/post.
        Invoke-WinpodxStep -Name 'idem_step' -Phase 2 -ErrorClass 'x' `
            -VerifyPreCondition  { $calls.Add('pre1');  return $true } `
            -Body                { $calls.Add('body1'); return 0 } `
            -VerifyPostCondition { $calls.Add('post1'); return $true } | Out-Null

        # Second run: only post-condition is re-verified; body must NOT run.
        $rc = Invoke-WinpodxStep -Name 'idem_step' -Phase 2 -ErrorClass 'x' `
            -VerifyPreCondition  { $calls.Add('pre2');  return $true } `
            -Body                { $calls.Add('body2'); return 0 } `
            -VerifyPostCondition { $calls.Add('post2'); return $true }

        $rc | Should -Be 0
        # Body did NOT run in the second invocation; pre1/body1/post1 happened
        # plus a single post2 (the marker-skip drift check).
        $calls | Should -Contain 'body1'
        $calls | Should -Not -Contain 'body2'
        $calls | Should -Contain 'post2'
    }
}

Describe 'Invoke-WinpodxStep contract (drift)' {

    BeforeEach {
        $script:CurrentStateDir = Use-WpxTestStateDir -SubDir ("drift-" + [guid]::NewGuid())
        $script:Calls = [System.Collections.Generic.List[string]]::new()
    }

    It 'Drift detected: marker present but post-cond fails -> marker deleted, body re-run' {
        $calls = $script:Calls
        # Plant a marker manually (simulates a marker from a prior run).
        New-WinpodxMarker -Name 'drift_step'
        Test-Path -LiteralPath (Join-Path $script:CurrentStateDir 'drift_step.done') | Should -BeTrue

        # Post-condition is initially $false (drift!), then $true once body runs.
        # We use a script-scope flag so the closure captures it across calls.
        $script:HasRun = $false
        $rc = Invoke-WinpodxStep -Name 'drift_step' -Phase 2 -ErrorClass 'x' `
            -VerifyPreCondition  { $calls.Add('pre');  return $true } `
            -Body                {
                $calls.Add('body')
                $script:HasRun = $true
                return 0
            } `
            -VerifyPostCondition {
                $calls.Add('post')
                return [bool]$script:HasRun
            }

        $rc | Should -Be 0
        # Body MUST have run (drift recovery), and post must have been
        # re-evaluated after.
        $calls | Should -Contain 'body'
        # Expected order: post (drift detect) -> pre -> body -> post (verify success).
        $calls | Should -Be @('post', 'pre', 'body', 'post')
        # Marker is rewritten at the end.
        Test-Path -LiteralPath (Join-Path $script:CurrentStateDir 'drift_step.done') | Should -BeTrue
    }
}

Describe 'Invoke-WinpodxStep contract (failure paths)' {

    BeforeEach {
        $script:CurrentStateDir = Use-WpxTestStateDir -SubDir ("fail-" + [guid]::NewGuid())
        $script:Calls = [System.Collections.Generic.List[string]]::new()
    }

    It 'Pre-condition false -> body NOT invoked, no marker written, no retry increment' {
        $calls = $script:Calls
        $rc = Invoke-WinpodxStep -Name 'precond_fail_step' -Phase 2 -ErrorClass 'x' `
            -VerifyPreCondition  { $calls.Add('pre');  return $false } `
            -Body                { $calls.Add('body'); return 0 } `
            -VerifyPostCondition { $calls.Add('post'); return $true }

        $rc | Should -Be 1
        $calls | Should -Not -Contain 'body'
        $calls | Should -Not -Contain 'post'
        Test-Path -LiteralPath (Join-Path $script:CurrentStateDir 'precond_fail_step.done') | Should -BeFalse
        # Pre-condition failures do NOT count against the retry budget.
        Get-WinpodxRetry -Name 'precond_fail_step' | Should -Be 0
    }

    It 'Post-condition false -> retry counter incremented, marker absent' {
        $calls = $script:Calls
        $rc = Invoke-WinpodxStep -Name 'postcond_fail_step' -Phase 2 -ErrorClass 'x' `
            -VerifyPreCondition  { return $true } `
            -Body                { $calls.Add('body'); return 0 } `
            -VerifyPostCondition { $calls.Add('post'); return $false }

        $rc | Should -Be 1
        $calls | Should -Contain 'body'
        $calls | Should -Contain 'post'
        Test-Path -LiteralPath (Join-Path $script:CurrentStateDir 'postcond_fail_step.done') | Should -BeFalse
        Get-WinpodxRetry -Name 'postcond_fail_step' | Should -Be 1
    }

    It 'Body throws -> body_rc=1, post-cond skipped, retry incremented' {
        $rc = Invoke-WinpodxStep -Name 'throw_step' -Phase 2 -ErrorClass 'x' `
            -VerifyPreCondition  { return $true } `
            -Body                { throw 'kaboom' } `
            -VerifyPostCondition { return $true }
        # Even with a throwing body the runner must NOT propagate the
        # exception (logging path expects deterministic rc).
        $rc | Should -Be 1
        Get-WinpodxRetry -Name 'throw_step' | Should -Be 1
    }

    It 'Retries exhausted -> Write-WinpodxFailure produces install_failure.json' {
        # The helper hits WpxMaxRetries (3) on the third consecutive failure.
        for ($i = 1; $i -le 3; $i++) {
            $rc = Invoke-WinpodxStep -Name 'exhaust_step' -Phase 2 -ErrorClass 'exhaust_failed' `
                -VerifyPreCondition  { return $true } `
                -Body                { return 0 } `
                -VerifyPostCondition { return $false }
            $rc | Should -Be 1
        }

        Get-WinpodxRetry -Name 'exhaust_step' | Should -Be 3
        Test-Path -LiteralPath $script:WpxFailurePath | Should -BeTrue

        $parsed = Get-Content -Raw -LiteralPath $script:WpxFailurePath | ConvertFrom-Json
        $parsed.failed_step  | Should -BeExactly 'exhaust_step'
        $parsed.phase        | Should -Be 2
        $parsed.attempt      | Should -Be 3
        $parsed.max_attempts | Should -Be 3
        $parsed.error_class  | Should -BeExactly 'exhaust_failed'
    }
}

Describe 'Invoke-WinpodxStep does not write marker on any failure path' {

    BeforeEach {
        $script:CurrentStateDir = Use-WpxTestStateDir -SubDir ("nomarker-" + [guid]::NewGuid())
    }

    It 'Marker is absent when pre-cond fails' {
        Invoke-WinpodxStep -Name 'nm_pre' -Phase 2 -ErrorClass 'x' `
            -VerifyPreCondition  { return $false } `
            -Body                { return 0 } `
            -VerifyPostCondition { return $true } | Out-Null
        Test-Path -LiteralPath (Join-Path $script:CurrentStateDir 'nm_pre.done') | Should -BeFalse
    }

    It 'Marker is absent when post-cond fails' {
        Invoke-WinpodxStep -Name 'nm_post' -Phase 2 -ErrorClass 'x' `
            -VerifyPreCondition  { return $true } `
            -Body                { return 0 } `
            -VerifyPostCondition { return $false } | Out-Null
        Test-Path -LiteralPath (Join-Path $script:CurrentStateDir 'nm_post.done') | Should -BeFalse
    }

    It 'Marker is absent when body throws' {
        Invoke-WinpodxStep -Name 'nm_throw' -Phase 2 -ErrorClass 'x' `
            -VerifyPreCondition  { return $true } `
            -Body                { throw 'kaboom' } `
            -VerifyPostCondition { return $true } | Out-Null
        Test-Path -LiteralPath (Join-Path $script:CurrentStateDir 'nm_throw.done') | Should -BeFalse
    }
}

Describe 'PHASE_ORDER constant matches design doc' {

    It 'Has exactly the 10 ordered steps documented in AGENT_FIRST_INSTALL_DESIGN.md' {
        $expectedNames = @(
            'defender_exclusion',
            'state_dir_ready',
            'token_staged',
            'agent_ready',
            'rdprrap_installed',
            'vbs_launchers',
            'oem_runtime_fixes',
            'max_sessions',
            'multi_session_active',
            'install_complete'
        )
        $actualNames = @($PHASE_ORDER | ForEach-Object { $_.name })
        $actualNames | Should -Be $expectedNames
    }

    It 'Every PHASE_ORDER entry has a matching Invoke-Step function' {
        foreach ($entry in $PHASE_ORDER) {
            $fn = "Invoke-Step-$($entry.name)"
            (Get-Command -Name $fn -ErrorAction SilentlyContinue) |
                Should -Not -BeNullOrEmpty -Because "missing step function $fn"
        }
    }
}
