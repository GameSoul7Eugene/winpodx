# SPDX-License-Identifier: MIT
# winpodx debloat: widgets / taskbar news panel

Write-Host "[widgets] Disabling widgets / taskbar news panel..."

$widgetValues = @(
    # Windows 11 -- widgets policy + taskbar icon
    @{Path="HKLM:\Software\Policies\Microsoft\Dsh"; Name="AllowNewsAndInterests"; Value=0},
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="TaskbarDa"; Value=0},

    # Windows 10 -- news and interests feed on the taskbar
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"; Name="EnShellFeedsTaskbarViewMode"; Value=10750826},
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"; Name="ShellFeedsTaskbarPreviousViewMode"; Value=1},
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"; Name="ShellFeedsTaskbarContentUpdateMode"; Value=1},
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"; Name="ShellFeedsTaskbarOpenOnHover"; Value=0},
	
	# Misc
	@{Path="HKLM:\Software\Policies\Microsoft\Windows\Windows Feeds"; Name="EnableFeeds"; Value=0},
	@{Path="HKLM:\Software\Microsoft\PolicyManager\default\NewsAndInterests\AllowNewsAndInterests"; Name="value"; Value=0}
)

foreach ($item in $widgetValues) {
    New-Item -Path $item.Path -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path $item.Path -Name $item.Name -Value $item.Value -Type DWord -Force -ErrorAction SilentlyContinue
}
