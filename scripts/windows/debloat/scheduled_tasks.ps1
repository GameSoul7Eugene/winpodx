# SPDX-License-Identifier: MIT
# winpodx debloat: disable noisy/unnecessary Windows scheduled tasks
#
# Scope is deliberately limited to pure telemetry / CEIP / feedback / ad tasks.
# We do NOT touch security (Defender), licensing/activation, certificate
# services, Windows Update repair (WaaSMedic/UpdateOrchestrator), language
# packs, Windows Hello, or general health/maintenance tasks -- disabling those
# risks breaking activation, updates, the IME, or hiding disk-failure warnings.
# PR #590 proposed a ~170-task blanket list; only the telemetry-safe subset
# below was adopted. #669 kept the SQM (CEIP) task and dropped the compat /
# maintenance / disk-health / network-diagnostic tasks it also proposed.
#
# Tasks targeted:
#   * Application Experience: Microsoft Compatibility Appraiser, ProgramDataUpdater,
#     ProgramInventoryUpdater, AitAgent (application-impact telemetry)
#   * Autochk\Proxy
#   * Customer Experience Improvement Program: Consolidator, KernelCeipTask, UsbCeip, BthSQM
#   * DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector (telemetry only;
#     the DiskDiagnosticResolver that surfaces SMART failure warnings is NOT touched)
#   * Feedback\Siuf: DmClient + DmClientOnScenarioDownload (Windows feedback telemetry)
#   * PI\Sqm-Tasks (Software Quality Metrics / CEIP telemetry)
#   * WindowsAI: Copilot + Insights data-collection telemetry
#   * Office telemetry agents (no-op when Office is absent)
#   * Maps\MapsToastTask + MapsUpdateTask
#   * RetailDemo\CleanupOfflineContent (deals with rentable demo content)
#   * Windows Error Reporting\QueueReporting
#
# Unknown task paths are harmless: schtasks prints to stderr (suppressed) and
# the loop continues.

$tasks = @(
	"\Microsoft\Office\OfficeTelemetryAgentFallBack",
	"\Microsoft\Office\OfficeTelemetryAgentFallBack2016",
	"\Microsoft\Office\OfficeTelemetryAgentLogOn",
	"\Microsoft\Office\OfficeTelemetryAgentLogOn2016",
	"\Microsoft\Windows\AppID\SmartScreenSpecific",
	"\Microsoft\Windows\Application Experience\AitAgent",
	"\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
	"\Microsoft\Windows\Application Experience\ProgramDataUpdater",
	"\Microsoft\Windows\Application Experience\ProgramInventoryUpdater",
	"\Microsoft\Windows\Application Experience\StartupAppTask",
	"\Microsoft\Windows\Autochk\Proxy",
	"\Microsoft\Windows\Clip\License Validation",
	"\Microsoft\Windows\CloudExperienceHost\CreateObjectTask",
	"\Microsoft\Windows\Customer Experience Improvement Program\BthSQM",
	"\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
	"\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask",
	"\Microsoft\Windows\Customer Experience Improvement Program\Server\ServerCeipAssistant",
	"\Microsoft\Windows\Customer Experience Improvement Program\Server\ServerRoleCollector",
	"\Microsoft\Windows\Customer Experience Improvement Program\Server\ServerRoleUsageCollector",
	"\Microsoft\Windows\Customer Experience Improvement Program\Uploader",
	"\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
	"\Microsoft\Windows\Device Information\Device User",
	"\Microsoft\Windows\Device Information\Device",
	"\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
	"\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticResolver",
	"\Microsoft\Windows\DiskFootprint\Diagnostics",
	"\Microsoft\Windows\ErrorDetails\EnableErrorDetailsUpdate",
	"\Microsoft\Windows\Feedback\Siuf\DmClient",
	"\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload",
	"\Microsoft\Windows\License Manager\TempSignedLicenseExchange",
	"\Microsoft\Windows\Maintenance\WinSAT",
	"\Microsoft\Windows\Maps\MapsToastTask",
	"\Microsoft\Windows\Maps\MapsUpdateTask",
	"\Microsoft\Windows\NetTrace\GatherNetworkInfo",
	"\Microsoft\Windows\PI\Sqm-Tasks",
	"\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem",
	"\Microsoft\Windows\RetailDemo\CleanupOfflineContent",
	"\Microsoft\Windows\Shell\FamilySafetyMonitor",
	"\Microsoft\Windows\Shell\FamilySafetyRefresh",
	"\Microsoft\Windows\Shell\FamilySafetyUpload",
	"\Microsoft\Windows\Windows Error Reporting\QueueReporting",
	"\Microsoft\Windows\WindowsAI\Copilot\CopilotDataCollectionTask",
	"\Microsoft\Windows\WindowsAI\Insights\InsightsDataCollectionTask",
	"\Microsoft\Windows\WindowsUpdate\Automatic App Update"
)

foreach ($task in $tasks) {
    Write-Host "[scheduled_tasks] Disabling $task"
	schtasks /end /tn $task 2>$null | Out-Null
    schtasks /change /tn $task /disable 2>$null | Out-Null
}
