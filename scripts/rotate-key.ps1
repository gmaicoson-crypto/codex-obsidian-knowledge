[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$VaultPath,
    [string]$CodexConfigPath,
    [ValidateSet('User', 'Process')][string]$SecretScope = 'User',
    [switch]$Approve
)
& (Join-Path $PSScriptRoot 'connection-maintenance.ps1') -Action RotateKey -VaultPath $VaultPath -CodexConfigPath $CodexConfigPath -SecretScope $SecretScope -Approve:$Approve
