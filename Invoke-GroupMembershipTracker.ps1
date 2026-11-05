#Requires -Version 7.2
[CmdletBinding()]
param(
    [ValidateSet('Demo','Compare','CaptureAD')][string]$Action = 'Demo',
    [string]$BaselinePath,
    [string]$CurrentPath,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'output'),
    [string]$SnapshotPath,
    [string]$ScopeKey,
    [string[]]$Groups,
    [string[]]$PrivilegedGroups = @(),
    [string[]]$SensitiveGroups = @(),
    [string]$Server = ''
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src/GroupMembershipTracker.psm1') -Force -ErrorAction Stop

switch ($Action) {
    'Demo' {
        $BaselinePath = Join-Path $PSScriptRoot 'sample-data/baseline.json'
        $CurrentPath = Join-Path $PSScriptRoot 'sample-data/current.json'
    }
    'Compare' {
        if ([string]::IsNullOrWhiteSpace($BaselinePath) -or [string]::IsNullOrWhiteSpace($CurrentPath)) {
            throw 'Compare action requires -BaselinePath and -CurrentPath.'
        }
    }
    'CaptureAD' {
        if ([string]::IsNullOrWhiteSpace($SnapshotPath) -or [string]::IsNullOrWhiteSpace($ScopeKey) -or
            $null -eq $Groups -or $Groups.Count -eq 0) {
            throw 'CaptureAD requires -SnapshotPath, -ScopeKey, and -Groups.'
        }
        $absoluteSnapshotPath = [IO.Path]::GetFullPath($SnapshotPath)
        if (Test-Path -LiteralPath $absoluteSnapshotPath) {
            throw 'Snapshot path already exists. Choose a new path to preserve audit history.'
        }
        $snapshot = New-GmtAdSnapshot -ScopeKey $ScopeKey -GroupIdentities $Groups `
            -PrivilegedGroups $PrivilegedGroups -SensitiveGroups $SensitiveGroups -Server $Server
        $parent = Split-Path -Path $absoluteSnapshotPath -Parent
        $null = New-Item -ItemType Directory -Path $parent -Force
        $snapshot | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $absoluteSnapshotPath -Encoding UTF8 -ErrorAction Stop
        Write-Host "Read-only snapshot saved to: $absoluteSnapshotPath"
        if (@($snapshot.captureErrors).Count -gt 0 -or @($snapshot.groups | Where-Object { -not $_.complete }).Count -gt 0) {
            Write-Warning 'Capture has coverage gaps. Compare will flag gaps rather than infer removals.'
        }
        return
    }
}
$baseline = Import-GmtSnapshot -Path $BaselinePath
$current = Import-GmtSnapshot -Path $CurrentPath
$result = Compare-GmtSnapshots -Baseline $baseline -Current $current
$paths = Export-GmtReports -Result $result -OutputDirectory $OutputDirectory
Write-Host "Findings: $($result.Summary.TotalFindings) (critical $($result.Summary.Critical), high $($result.Summary.High), medium $($result.Summary.Medium), low $($result.Summary.Low))"
Write-Host "Evidence gaps: $($result.Summary.EvidenceGaps); groups compared: $($result.Summary.GroupsCompared)"
Write-Host "CSV: $($paths.Csv)"
Write-Host "JSON: $($paths.Json)"
Write-Host "HTML: $($paths.Html)"
