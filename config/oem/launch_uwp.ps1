# launch_uwp.ps1 — activate a UWP/MSIX app by AUMID via COM, no explorer.exe
#
# The default RemoteApp UWP launch (`explorer.exe shell:AppsFolder\<AUMID>`)
# briefly shows an explorer.exe RemoteApp window before dispatching to the
# UWP frame — that's the "PowerShell-looking flash" users see when launching
# Calculator / Settings / Terminal et al. Calling IApplicationActivationManager
# directly skips the explorer transition: the UWP frame appears immediately
# without an intermediate window.
#
# Invoked via launch_uwp.vbs which keeps powershell.exe itself hidden so
# this script never flashes either.
#
# Usage: powershell.exe -NoProfile -ExecutionPolicy Bypass -File launch_uwp.ps1 <AUMID>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Aumid
)

$ErrorActionPreference = 'Stop'

# IApplicationActivationManager — Windows shell COM interface for launching
# packaged apps by AUMID. Documented in MSDN; available since Windows 8.
# CLSID 45BA127D-10A8-46EA-8AB7-56EA9078943C (ApplicationActivationManager class)
# IID   2E941141-7F97-4756-BA1D-9DECDE894A3D (IApplicationActivationManager)
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[ComImport,
 Guid("2E941141-7F97-4756-BA1D-9DECDE894A3D"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IApplicationActivationManager
{
    int ActivateApplication(
        [In] string appUserModelId,
        [In] string arguments,
        [In] int options,
        [Out] out uint processId);
    int ActivateForFile(
        [In] string appUserModelId,
        [In] IntPtr itemArray,
        [In] string verb,
        [Out] out uint processId);
    int ActivateForProtocol(
        [In] string appUserModelId,
        [In] IntPtr itemArray,
        [Out] out uint processId);
}

[ComImport, Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]
public class ApplicationActivationManagerImpl { }
"@

try {
    $aam = [IApplicationActivationManager]([ApplicationActivationManagerImpl]::new())
    [uint32]$pid = 0
    [void]$aam.ActivateApplication($Aumid, $null, 0, [ref]$pid)
    exit 0
} catch {
    # Don't surface to the user with a console — write to a log the agent can
    # tail. We swallow the failure here; if activation truly fails (bad AUMID,
    # unregistered package), the user just sees nothing happen — same as the
    # legacy explorer.exe path on a typo'd AUMID.
    try {
        $logDir = Join-Path $env:LOCALAPPDATA 'winpodx'
        if (-not (Test-Path $logDir)) {
            [void](New-Item -ItemType Directory -Path $logDir -Force)
        }
        $logPath = Join-Path $logDir 'uwp-launcher.log'
        $line = "$((Get-Date).ToUniversalTime().ToString('o')) FAIL aumid=$Aumid err=$($_.Exception.Message)"
        Add-Content -Path $logPath -Value $line -ErrorAction SilentlyContinue
    } catch { }
    exit 1
}
