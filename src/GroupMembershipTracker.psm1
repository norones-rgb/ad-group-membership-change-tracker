#Requires -Version 7.2
Set-StrictMode -Version Latest

function Get-GmtProperty {
    param([Parameter(Mandatory)][object]$Record, [Parameter(Mandatory)][string]$Name)
    $property = $Record.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return ,$property.Value
}

function Assert-GmtText {
    param([object]$Value, [string]$Label)
    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        throw "Missing required text field: $Label"
    }
}

function Assert-GmtSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Snapshot)

    if ((Get-GmtProperty $Snapshot 'schemaVersion') -ne 1) {
        throw 'Unsupported snapshot schemaVersion; expected 1.'
    }
    foreach ($field in @('capturedAtUtc', 'scopeKey', 'source')) {
        Assert-GmtText (Get-GmtProperty $Snapshot $field) $field
    }
    # ConvertFrom-Json may materialize ISO-8601 strings as DateTime on newer
    # PowerShell versions. Keep the strict UTC contract for textual inputs.
    $captureValue = Get-GmtProperty $Snapshot 'capturedAtUtc'
    if ($captureValue -is [datetime]) {
        if ($captureValue.Kind -eq [DateTimeKind]::Unspecified) {
            throw 'capturedAtUtc must have an explicit UTC timezone.'
        }
        $stamp = $captureValue.ToUniversalTime().ToString(
            "yyyy-MM-ddTHH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
        $Snapshot.PSObject.Properties['capturedAtUtc'].Value = $stamp
    }
    elseif ($captureValue -is [datetimeoffset]) {
        $stamp = $captureValue.UtcDateTime.ToString(
            "yyyy-MM-ddTHH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
        $Snapshot.PSObject.Properties['capturedAtUtc'].Value = $stamp
    }
    else {
        $stamp = [string]$captureValue
    }
    if ($stamp -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$') {
        throw 'capturedAtUtc must use yyyy-MM-ddTHH:mm:ssZ (UTC).'
    }
    try {
        $null = [datetimeoffset]::ParseExact(
            $stamp, "yyyy-MM-ddTHH:mm:ss'Z'",
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal
        )
    } catch { throw "Invalid UTC capturedAtUtc: $stamp" }

    $requests = Get-GmtProperty $Snapshot 'requestedGroups'
    if ($null -eq $requests -or @($requests).Count -eq 0) {
        throw 'requestedGroups must be a nonempty array.'
    }
    $requestsSeen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($request in @($requests)) {
        Assert-GmtText $request 'requestedGroups item'
        if (-not $requestsSeen.Add(([string]$request).Trim())) {
            throw "Duplicate requested group: $request"
        }
    }

    $groups = Get-GmtProperty $Snapshot 'groups'
    if ($null -eq $groups) { throw 'groups must be an array (possibly empty).' }
    $groupIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($group in @($groups)) {
        foreach ($field in @('id', 'name', 'tier')) {
            Assert-GmtText (Get-GmtProperty $group $field) "group.$field"
        }
        $id = ([string](Get-GmtProperty $group 'id')).Trim()
        if (-not $groupIds.Add($id)) { throw "Duplicate group ID: $id" }
        $tier = [string](Get-GmtProperty $group 'tier')
        if ($tier -cnotin @('Privileged','Sensitive','Standard')) {
            throw "Invalid tier '$tier' for group '$id'."
        }
        $complete = Get-GmtProperty $group 'complete'
        if ($complete -isnot [bool]) { throw "Group '$id' must have boolean complete." }
        $members = Get-GmtProperty $group 'members'
        if ($null -eq $members) { throw "Group '$id' must have a members array." }
        $memberIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($member in @($members)) {
            foreach ($field in @('id','name','type')) {
                Assert-GmtText (Get-GmtProperty $member $field) "group[$id].member.$field"
            }
            $memberId = ([string](Get-GmtProperty $member 'id')).Trim()
            if (-not $memberIds.Add($memberId)) {
                throw "Duplicate member ID '$memberId' in group '$id'."
            }
            $memberType = [string](Get-GmtProperty $member 'type')
            if ($memberType -cnotin @('user','group','computer','service','foreign','other')) {
                throw "Invalid member type '$memberType' in group '$id'."
            }
        }
    }
    $captureErrors = Get-GmtProperty $Snapshot 'captureErrors'
    if ($null -eq $captureErrors) { throw 'captureErrors must be an array (possibly empty).' }
    foreach ($captureError in @($captureErrors)) {
        Assert-GmtText $captureError 'captureErrors item'
    }
}

function Import-GmtSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    $snapshot = Get-Content -LiteralPath $resolved -Raw -Encoding UTF8 -ErrorAction Stop |
        ConvertFrom-Json -Depth 40 -ErrorAction Stop
    Assert-GmtSnapshot $snapshot
    return $snapshot
}

function New-GmtFinding {
    param(
        [string]$Type, [string]$Severity, [string]$GroupId, [string]$GroupName,
        [string]$GroupTier, [string]$MemberId = '', [string]$MemberName = '',
        [string]$MemberType = '', [string]$Explanation,
        [string]$BaselineAtUtc, [string]$CurrentAtUtc
    )
    $material = @($Type,$GroupId,$MemberId,$BaselineAtUtc,$CurrentAtUtc,$Explanation) -join '|'
    $hash = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($material))
    $eventId = [Convert]::ToHexString($hash).Substring(0,16)
    return [pscustomobject][ordered]@{
        EventId = $eventId
        Type = $Type
        Severity = $Severity
        GroupId = $GroupId
        GroupName = $GroupName
        GroupTier = $GroupTier
        MemberId = $MemberId
        MemberName = $MemberName
        MemberType = $MemberType
        Explanation = $Explanation
        BaselineAtUtc = $BaselineAtUtc
        CurrentAtUtc = $CurrentAtUtc
    }
}

function ConvertTo-GmtIndex {
    param([object[]]$Records)
    $index = [System.Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($record in $Records) { $index.Add(([string]$record.id).Trim(), $record) }
    return ,$index
}

function Compare-GmtSnapshots {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Baseline, [Parameter(Mandatory)][object]$Current)
    Assert-GmtSnapshot $Baseline
    Assert-GmtSnapshot $Current
    if ($Baseline.scopeKey -cne $Current.scopeKey) {
        throw 'Snapshot scopeKey mismatch. Comparison refused.'
    }
    $baseRequests = @($Baseline.requestedGroups | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Sort-Object)
    $nowRequests = @($Current.requestedGroups | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Sort-Object)
    if ((@($baseRequests) -join "`n") -cne (@($nowRequests) -join "`n")) {
        throw 'Snapshot requestedGroups mismatch. Comparison refused.'
    }
    $baseTime = [datetimeoffset]::Parse([string]$Baseline.capturedAtUtc)
    $nowTime = [datetimeoffset]::Parse([string]$Current.capturedAtUtc)
    if ($baseTime -ge $nowTime) { throw 'Baseline must precede current capture time.' }
    $baseGroups = ConvertTo-GmtIndex @($Baseline.groups)
    $nowGroups = ConvertTo-GmtIndex @($Current.groups)
    $allKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $baseGroups.Keys) { $null = $allKeys.Add($key) }
    foreach ($key in $nowGroups.Keys) { $null = $allKeys.Add($key) }
    $findings = [System.Collections.Generic.List[object]]::new()
    $groupsCompared = 0
    foreach ($key in @($allKeys | Sort-Object)) {
        $baselineGroup = $null
        $currentGroup = $null
        $hasBaseline = $baseGroups.TryGetValue($key, [ref]$baselineGroup)
        $hasCurrent = $nowGroups.TryGetValue($key, [ref]$currentGroup)
        $referenceGroup = if ($hasCurrent) { $currentGroup } else { $baselineGroup }
        $id = [string]$referenceGroup.id
        $name = [string]$referenceGroup.name
        $tier = [string]$referenceGroup.tier
        $why = $null
        if (-not $hasBaseline) { $why = 'Group is absent from baseline; prior memberships cannot be established.' }
        elseif (-not $hasCurrent) { $why = 'Group is absent from current capture; removals cannot be established.' }
        elseif (-not $baselineGroup.complete -or -not $currentGroup.complete) {
            $why = 'At least one group membership collection was incomplete; membership changes suppressed.'
        }
        if ($null -ne $why) {
            $findings.Add((New-GmtFinding -Type 'CoverageGap' -Severity 'High' -GroupId $id -GroupName $name -GroupTier $tier -Explanation $why -BaselineAtUtc $Baseline.capturedAtUtc -CurrentAtUtc $Current.capturedAtUtc))
            continue
        }
        $groupsCompared++
        if ([string]$baselineGroup.tier -cne [string]$currentGroup.tier) {
            $findings.Add((New-GmtFinding -Type 'TierChanged' -Severity 'Medium' -GroupId $id -GroupName $name -GroupTier $tier -Explanation 'Risk classification changed between snapshots; verify approval.' -BaselineAtUtc $Baseline.capturedAtUtc -CurrentAtUtc $Current.capturedAtUtc))
        }
        if ([string]$baselineGroup.name -cne [string]$currentGroup.name) {
            $findings.Add((New-GmtFinding -Type 'GroupRenamed' -Severity 'Low' -GroupId $id -GroupName $name -GroupTier $tier -Explanation "Group display name changed from '$($baselineGroup.name)' to '$($currentGroup.name)'." -BaselineAtUtc $Baseline.capturedAtUtc -CurrentAtUtc $Current.capturedAtUtc))
        }
        $baselineMembers = ConvertTo-GmtIndex @($baselineGroup.members)
        $currentMembers = ConvertTo-GmtIndex @($currentGroup.members)
        foreach ($memberId in @($currentMembers.Keys | Sort-Object)) {
            if ($baselineMembers.ContainsKey($memberId)) { continue }
            $member = $currentMembers[$memberId]
            $memberType = [string]$member.type
            $severity = if ($tier -eq 'Privileged' -and $memberType -eq 'group') { 'Critical' }
                elseif ($tier -eq 'Privileged') { 'High' }
                elseif ($tier -eq 'Sensitive') { 'Medium' }
                else { 'Low' }
            $findings.Add((New-GmtFinding -Type 'MemberAdded' -Severity $severity -GroupId $id -GroupName $name -GroupTier $tier -MemberId ([string]$member.id) -MemberName ([string]$member.name) -MemberType $memberType -Explanation 'Direct group membership was added; review authorization and change record.' -BaselineAtUtc $Baseline.capturedAtUtc -CurrentAtUtc $Current.capturedAtUtc))
        }
        foreach ($memberId in @($baselineMembers.Keys | Sort-Object)) {
            if ($currentMembers.ContainsKey($memberId)) { continue }
            $member = $baselineMembers[$memberId]
            $severity = if ($tier -eq 'Privileged') { 'Medium' } else { 'Low' }
            $findings.Add((New-GmtFinding -Type 'MemberRemoved' -Severity $severity -GroupId $id -GroupName $name -GroupTier $tier -MemberId ([string]$member.id) -MemberName ([string]$member.name) -MemberType ([string]$member.type) -Explanation 'Direct group membership was removed; review against approved change.' -BaselineAtUtc $Baseline.capturedAtUtc -CurrentAtUtc $Current.capturedAtUtc))
        }
    }
    # Collection errors are separate from missing group findings because a failed lookup
    # may not provide enough stable identity to associate it with an existing group.
    foreach ($side in @('Baseline','Current')) {
        $snapshot = if ($side -eq 'Baseline') { $Baseline } else { $Current }
        foreach ($errorText in @($snapshot.captureErrors)) {
            $findings.Add((New-GmtFinding -Type 'CaptureError' -Severity 'High' -GroupId '' -GroupName $side -GroupTier '' -Explanation "${side} capture error: $errorText" -BaselineAtUtc $Baseline.capturedAtUtc -CurrentAtUtc $Current.capturedAtUtc))
        }
    }
    $orderedFindings = @($findings.ToArray() | Sort-Object GroupName,Type,MemberName,EventId)
    $summary = [pscustomobject][ordered]@{
        ScopeKey = [string]$Current.scopeKey
        BaselineAtUtc = [string]$Baseline.capturedAtUtc
        CurrentAtUtc = [string]$Current.capturedAtUtc
        BaselineGroups = @($Baseline.groups).Count
        CurrentGroups = @($Current.groups).Count
        GroupsCompared = $groupsCompared
        TotalFindings = $orderedFindings.Count
        Critical = @($orderedFindings | Where-Object Severity -eq 'Critical').Count
        High = @($orderedFindings | Where-Object Severity -eq 'High').Count
        Medium = @($orderedFindings | Where-Object Severity -eq 'Medium').Count
        Low = @($orderedFindings | Where-Object Severity -eq 'Low').Count
        Added = @($orderedFindings | Where-Object Type -eq 'MemberAdded').Count
        Removed = @($orderedFindings | Where-Object Type -eq 'MemberRemoved').Count
        EvidenceGaps = @($orderedFindings | Where-Object { $_.Type -in @('CoverageGap','CaptureError') }).Count
    }
    return [pscustomobject]@{ Summary = $summary; Findings = $orderedFindings }
}

function Protect-GmtCsvCell {
    param([object]$Value)
    $text = [string]$Value
    if ($text -match '^\s*[=+\-@]') { return "'$text" }
    return $text
}

function ConvertTo-GmtSafeCsvRow {
    param([object]$Finding)
    $row = [ordered]@{}
    foreach ($prop in $Finding.PSObject.Properties) {
        $row[$prop.Name] = Protect-GmtCsvCell $prop.Value
    }
    return [pscustomobject]$row
}

function ConvertTo-GmtHtml {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Result)
    $encode = { param($value) [System.Net.WebUtility]::HtmlEncode([string]$value) }
    $s = $Result.Summary
    $html = [Text.StringBuilder]::new()
    $null = $html.AppendLine(@'
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>AD Group Membership Change Tracker — Audit Report</title>
<style>
:root{color-scheme:light;font-family:Segoe UI,Arial,sans-serif;color:#182b36;background:#f3f5f6}
*{box-sizing:border-box}body{margin:0}main{max-width:1150px;margin:0 auto;padding:32px 20px}
header{background:#122b36;color:#fff;padding:38px 20px}header .inner{max-width:1150px;margin:auto}
h1{font-size:30px;letter-spacing:-.6px;margin:8px 0}.eyebrow{font-size:12px;letter-spacing:2px;text-transform:uppercase;color:#b4d5c9}
.subtitle{color:#dce9ea;font-size:14px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(145px,1fr));gap:12px;margin:24px 0}
.stat{background:white;border:1px solid #dce3e6;border-radius:12px;padding:18px}.stat b{display:block;font-size:29px;margin-top:8px}.stat span{font-size:12px;color:#55707b}
.table-wrap{background:white;border:1px solid #dce3e6;border-radius:12px;overflow:auto}
table{width:100%;border-collapse:collapse;font-size:13px}th{background:#ebf1f2;text-align:left;color:#38525e;font-size:12px}
th,td{padding:12px 11px;border-bottom:1px solid #e7ecee;vertical-align:top}td{overflow-wrap:anywhere;min-width:95px}tr:last-child td{border-bottom:0}
.pill{display:inline-block;border-radius:6px;font-size:11px;font-weight:700;padding:4px 8px;background:#e9eef0}
.Critical{background:#ffe3de;color:#a22212}.High{background:#fff0d7;color:#8d4e00}.Medium{background:#fff7de;color:#725600}.Low{background:#e3f3e9;color:#16633b}
h2{font-size:20px;margin:30px 0 14px}footer{color:#64757d;font-size:12px;margin:18px 0}p.note{background:#e7f0ef;padding:14px;border-left:4px solid #4d8977;border-radius:3px;font-size:13px}
</style></head><body><header><div class="inner"><div class="eyebrow">Identity Governance / Read-only evidence</div>
<h1>AD Group Membership Change Tracker</h1><div class="subtitle">Direct membership changes and collection coverage report</div></div></header><main>
'@)
    $null = $html.AppendLine('<p><strong>Scope:</strong> ' + (& $encode $s.ScopeKey) + '</p>')
    $null = $html.AppendLine('<p><strong>Baseline:</strong> ' + (& $encode $s.BaselineAtUtc) + ' &nbsp; <strong>Current:</strong> ' + (& $encode $s.CurrentAtUtc) + '</p>')
    $null = $html.AppendLine('<section class="grid">')
    $metrics = @(
        [pscustomobject]@{ Label='Total findings'; Value=$s.TotalFindings }
        [pscustomobject]@{ Label='Critical'; Value=$s.Critical }
        [pscustomobject]@{ Label='High'; Value=$s.High }
        [pscustomobject]@{ Label='Medium'; Value=$s.Medium }
        [pscustomobject]@{ Label='Low'; Value=$s.Low }
        [pscustomobject]@{ Label='Groups compared'; Value=$s.GroupsCompared }
        [pscustomobject]@{ Label='Added'; Value=$s.Added }
        [pscustomobject]@{ Label='Removed'; Value=$s.Removed }
        [pscustomobject]@{ Label='Evidence gaps'; Value=$s.EvidenceGaps }
    )
    foreach ($item in $metrics) {
        $null = $html.AppendLine('<div class="stat"><span>' + (& $encode $item.Label) + '</span><b>' + (& $encode $item.Value) + '</b></div>')
    }
    $null = $html.AppendLine('</section><p class="note">Evidence gaps are not proven access removals. Nested group memberships are tracked as direct edges; effective/transitive privilege expansion is outside this MVP.</p>')
    $null = $html.AppendLine('<h2>Findings</h2><div class="table-wrap"><table><thead><tr><th>Severity</th><th>Type</th><th>Group</th><th>Member</th><th>Type</th><th>Explanation</th><th>Event ID</th></tr></thead><tbody>')
    foreach ($finding in @($Result.Findings)) {
        $severity = [string]$finding.Severity
        $null = $html.AppendLine('<tr><td><span class="pill ' + (& $encode $severity) + '">' + (& $encode $severity) + '</span></td><td>' + (& $encode $finding.Type) + '</td><td>' + (& $encode $finding.GroupName) + '</td><td>' + (& $encode $finding.MemberName) + '</td><td>' + (& $encode $finding.MemberType) + '</td><td>' + (& $encode $finding.Explanation) + '</td><td><code>' + (& $encode $finding.EventId) + '</code></td></tr>')
    }
    if (@($Result.Findings).Count -eq 0) { $null = $html.AppendLine('<tr><td colspan="7">No findings for the supplied snapshots.</td></tr>') }
    $null = $html.AppendLine('</tbody></table></div><footer>Generated locally. No directory changes were performed. Review classifications before using as formal compliance evidence.</footer></main></body></html>')
    return $html.ToString()
}

function Export-GmtReports {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Result, [Parameter(Mandatory)][string]$OutputDirectory)
    $resolvedOutput = [IO.Path]::GetFullPath($OutputDirectory)
    $null = New-Item -ItemType Directory -Path $resolvedOutput -Force -ErrorAction Stop
    $csvPath = Join-Path $resolvedOutput 'group-membership-findings.csv'
    $jsonPath = Join-Path $resolvedOutput 'group-membership-findings.json'
    $htmlPath = Join-Path $resolvedOutput 'group-membership-report.html'
    if (@($Result.Findings).Count -gt 0) {
        $rows = @($Result.Findings | ForEach-Object { ConvertTo-GmtSafeCsvRow $_ })
        $rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding utf8 -ErrorAction Stop
    } else {
        '"EventId","Type","Severity","GroupId","GroupName","GroupTier","MemberId","MemberName","MemberType","Explanation","BaselineAtUtc","CurrentAtUtc"' |
            Set-Content -LiteralPath $csvPath -Encoding UTF8 -ErrorAction Stop
    }
    $Result | ConvertTo-Json -Depth 18 | Set-Content -LiteralPath $jsonPath -Encoding UTF8 -ErrorAction Stop
    ConvertTo-GmtHtml $Result | Set-Content -LiteralPath $htmlPath -Encoding UTF8 -ErrorAction Stop
    return [pscustomobject]@{ Csv = $csvPath; Json = $jsonPath; Html = $htmlPath }
}

function New-GmtAdSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScopeKey,
        [Parameter(Mandatory)][string[]]$GroupIdentities,
        [string[]]$PrivilegedGroups = @(),
        [string[]]$SensitiveGroups = @(),
        [string]$Server = ''
    )
    Assert-GmtText $ScopeKey 'ScopeKey'
    if ($GroupIdentities.Count -eq 0) { throw 'Supply at least one group identity.' }
    if ($null -eq (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw 'ActiveDirectory RSAT module not found. Use Demo/Compare mode or run on a Windows host with RSAT.'
    }
    Import-Module ActiveDirectory -ErrorAction Stop
    $found = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($identity in $GroupIdentities) {
        Assert-GmtText $identity 'GroupIdentities item'
        $adArgs = @{ Identity = $identity; ErrorAction = 'Stop' }
        if (-not [string]::IsNullOrWhiteSpace($Server)) { $adArgs['Server'] = $Server }
        try {
            $group = Get-ADGroup @adArgs
            $groupId = if ($null -ne $group.ObjectGUID) { ([string]$group.ObjectGUID).ToLowerInvariant() } else { [string]$group.DistinguishedName }
            $tier = if ($identity -in $PrivilegedGroups -or $group.Name -in $PrivilegedGroups) { 'Privileged' }
                elseif ($identity -in $SensitiveGroups -or $group.Name -in $SensitiveGroups) { 'Sensitive' }
                else { 'Standard' }
            $members = [System.Collections.Generic.List[object]]::new()
            $complete = $true
            $collectionError = ''
            try {
                $memberArgs = @{ Identity = $group.DistinguishedName; ErrorAction = 'Stop' }
                if (-not [string]::IsNullOrWhiteSpace($Server)) { $memberArgs['Server'] = $Server }
                foreach ($principal in @(Get-ADGroupMember @memberArgs)) {
                    $principalId = if ($null -ne $principal.ObjectGUID) { ([string]$principal.ObjectGUID).ToLowerInvariant() }
                        else { [string]$principal.DistinguishedName }
                    if ([string]::IsNullOrWhiteSpace($principalId)) { throw 'Member has no stable ID or distinguished name.' }
                    $kind = switch ([string]$principal.objectClass) {
                        'user' { 'user' }
                        'group' { 'group' }
                        'computer' { 'computer' }
                        'foreignSecurityPrincipal' { 'foreign' }
                        default { 'other' }
                    }
                    $members.Add([pscustomobject]@{ id = $principalId; name = [string]$principal.Name; type = $kind })
                }
            } catch {
                $complete = $false
                $members.Clear() # Never export a partial group as complete.
                $collectionError = 'Failed to enumerate all direct members; inspect AD permissions and connectivity.'
            }
            $found.Add([pscustomobject]@{
                id = $groupId; name = [string]$group.Name; tier = $tier
                complete = $complete; collectionError = $collectionError; members = @($members.ToArray())
            })
        } catch {
            $errors.Add("Failed to locate requested group '$identity'; check spelling, permissions, and directory connectivity.")
        }
    }
    $stamp = ([datetime]::UtcNow).ToString("yyyy-MM-ddTHH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
    $snapshot = [pscustomobject]@{
        schemaVersion = 1; capturedAtUtc = $stamp; scopeKey = $ScopeKey
        source = 'ActiveDirectory'; requestedGroups = @($GroupIdentities)
        groups = @($found.ToArray()); captureErrors = @($errors.ToArray())
    }
    Assert-GmtSnapshot $snapshot
    return $snapshot
}

Export-ModuleMember -Function Import-GmtSnapshot,Assert-GmtSnapshot,Compare-GmtSnapshots,Export-GmtReports,New-GmtAdSnapshot,Protect-GmtCsvCell,ConvertTo-GmtHtml
