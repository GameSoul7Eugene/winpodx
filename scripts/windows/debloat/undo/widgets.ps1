# SPDX-License-Identifier: MIT
# winpodx debloat UNDO: widgets / taskbar news panel

Write-Host "[widgets] Restoring widgets / taskbar news panel..."

$widgetValues = @(
    # Windows 11
    @{Path="HKLM:\Software\Policies\Microsoft\Dsh"; Name="AllowNewsAndInterests"},

    # Windows 10
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"; Name="EnShellFeedsTaskbarViewMode"},
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"; Name="ShellFeedsTaskbarPreviousViewMode"},
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"; Name="ShellFeedsTaskbarContentUpdateMode"},
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"; Name="ShellFeedsTaskbarOpenOnHover"},
	
	# Misc
	@{Path="HKLM:\Software\Policies\Microsoft\Windows\Windows Feeds"; Name="EnableFeeds"},
	@{Path="HKLM:\Software\Microsoft\PolicyManager\default\NewsAndInterests\AllowNewsAndInterests"; Name="value"}
)

foreach ($item in $widgetValues) {
    Remove-ItemProperty -Path $item.Path -Name $item.Name -Force -ErrorAction SilentlyContinue
}

Write-Host "[widgets] Restoring taskbar widgets icon..."
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
