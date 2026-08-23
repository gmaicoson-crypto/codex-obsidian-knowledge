[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$VaultPath,
    [string]$CodexConfigPath,
    [switch]$Approve
)
& (Join-Path $PSScriptRoot 'connection-maintenance.ps1') -Action Uninstall -VaultPath $VaultPath -CodexConfigPath $CodexConfigPath -Approve:$Approve
