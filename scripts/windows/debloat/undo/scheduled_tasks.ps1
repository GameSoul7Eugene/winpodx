# SPDX-License-Identifier: MIT
# winpodx debloat UNDO: re-enable noisy/unnecessary Windows scheduled tasks disabled by apply

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
    Write-Host "[scheduled_tasks] Re-enabling $task"
    schtasks /change /tn $task /enable 2>$null | Out-Null
}
