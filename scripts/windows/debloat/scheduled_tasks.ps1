# SPDX-License-Identifier: MIT
# winpodx debloat: disable noisy/unnecessary scheduled tasks.
#
# Scope is deliberately limited to pure telemetry / CEIP / feedback / ad tasks.
# We do NOT touch security (Defender), licensing/activation, certificate
# services, Windows Update repair (WaaSMedic/UpdateOrchestrator), language
# packs, Windows Hello, or general health/maintenance tasks – disabling those
# risks breaking activation, updates, or the IME. PR #590 proposed a ~170-task
# blanket list; only the telemetry-safe subset below was adopted.
#
# Tasks targeted:
#   * Application Experience: Microsoft Compatibility Appraiser, ProgramDataUpdater,
#     ProgramInventoryUpdater, AitAgent (application-impact telemetry)
#   * Autochk\Proxy
#   * Customer Experience Improvement Program: Consolidator, KernelCeipTask, UsbCeip, BthSQM
#   * DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector
#   * Feedback\Siuf: DmClient + DmClientOnScenarioDownload (Windows feedback telemetry)
#   * WindowsAI: Copilot + Insights data-collection telemetry
#   * Office telemetry agents (no-op when Office is absent)
#   * Maps\MapsToastTask + MapsUpdateTask
#   * RetailDemo\CleanupOfflineContent (deals with rentable demo content)
#   * Windows Error Reporting\QueueReporting
#
# Unknown task paths are harmless: schtasks prints to stderr (suppressed) and
# the loop continues.

$tasks = @(
	"\Microsoft\Office\OfficeTelemetryAgentFallBack2016",
	"\Microsoft\Office\OfficeTelemetryAgentLogOn2016",
	"\Microsoft\Windows\Application Experience\AitAgent",
	"\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
	"\Microsoft\Windows\Application Experience\PcaPatchDbTask",
	"\Microsoft\Windows\Application Experience\ProgramDataUpdater",
	"\Microsoft\Windows\Application Experience\ProgramInventoryUpdater",
	"\Microsoft\Windows\Application Experience\StartupAppTask",
	"\Microsoft\Windows\Autochk\Proxy",
	"\Microsoft\Windows\Customer Experience Improvement Program\BthSQM",
	"\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
	"\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask",
	"\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
	"\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
	"\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticResolver",
	"\Microsoft\Windows\Feedback\Siuf\DmClient",
	"\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload",
	"\Microsoft\Windows\Maintenance\WinSAT",
	"\Microsoft\Windows\Maps\MapsToastTask",
	"\Microsoft\Windows\Maps\MapsUpdateTask",
	"\Microsoft\Windows\NetTrace\GatherNetworkInfo",
	"\Microsoft\Windows\PI\Sqm-Tasks",
	"\Microsoft\Windows\RetailDemo\CleanupOfflineContent",
	"\Microsoft\Windows\Windows Error Reporting\QueueReporting",
	"\Microsoft\Windows\WindowsAI\Copilot\CopilotDataCollectionTask",
	"\Microsoft\Windows\WindowsAI\Insights\InsightsDataCollectionTask"
)

foreach ($task in $tasks) {
    Write-Host "[scheduled_tasks] Disabling $task"
    schtasks /Change /TN $task /Disable 2>$null | Out-Null
}
