#Requires -Version 7.2
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/GroupMembershipTracker.psm1') -Force
    $script:baselinePath = Join-Path $PSScriptRoot '../sample-data/baseline.json'
    $script:currentPath = Join-Path $PSScriptRoot '../sample-data/current.json'
    $script:baseline = Import-GmtSnapshot $script:baselinePath
    $script:current = Import-GmtSnapshot $script:currentPath
}

Describe 'Synthetic snapshot contract and event detection' {
    It 'loads the fixture and produces an exact deterministic total' {
        $result = Compare-GmtSnapshots -Baseline $script:baseline -Current $script:current
        $result.Summary.TotalFindings | Should -Be 10
        $result.Summary.Critical | Should -Be 1
        $result.Summary.High | Should -Be 5
        $result.Summary.Medium | Should -Be 1
        $result.Summary.Low | Should -Be 3
        $result.Summary.Added | Should -Be 5
        $result.Summary.Removed | Should -Be 2
        $result.Summary.EvidenceGaps | Should -Be 3
        $result.Summary.GroupsCompared | Should -Be 6
    }
    It 'classifies a nested privileged group addition as critical' {
        $result = Compare-GmtSnapshots $script:baseline $script:current
        $matching = @($result.Findings | Where-Object { $_.MemberId -eq 'g-workstations' })
        $matching.Count | Should -Be 1
        $matching[0].Severity | Should -Be 'Critical'
        $matching[0].Type | Should -Be 'MemberAdded'
    }
    It 'does not invent removals for missing or incomplete groups' {
        $result = Compare-GmtSnapshots $script:baseline $script:current
        @($result.Findings | Where-Object { $_.Type -eq 'MemberRemoved' -and $_.GroupId -in @('g-secret','g-audit') }).Count | Should -Be 0
        @($result.Findings | Where-Object { $_.Type -eq 'CoverageGap' }).Count | Should -Be 3
    }
    It 'matches stable member identifiers rather than display names' {
        $modified = $script:current | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
        $group = @($modified.groups | Where-Object { $_.id -eq 'g-da' })[0]
        $user = @($group.members | Where-Object { $_.id -eq 'u-alice' })[0]
        $user.name = 'Alice with a new display name'
        $result = Compare-GmtSnapshots $script:baseline $modified
        $result.Summary.TotalFindings | Should -Be 10
    }
    It 'can compare unchanged members without false findings' {
        $same = $script:baseline | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
        $same.capturedAtUtc = '2026-11-03T12:00:00Z'
        $result = Compare-GmtSnapshots $script:baseline $same
        $result.Summary.TotalFindings | Should -Be 0
        $report = Export-GmtReports $result (Join-Path $TestDrive 'empty-diff')
        (Get-Content -LiteralPath $report.Csv -Raw) | Should -Match 'EventId'
        @(Import-Csv -LiteralPath $report.Csv).Count | Should -Be 0
    }
    It 'rejects duplicates and mismatched scopes' {
        $bad = $script:current | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
        $bad.groups[0].members += [pscustomobject]@{id='u-alice';name='Duplicate';type='user'}
        { Assert-GmtSnapshot $bad } | Should -Throw -ExpectedMessage '*Duplicate member ID*'
        $other = $script:current | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
        $other.scopeKey = 'different-scope'
        { Compare-GmtSnapshots $script:baseline $other } | Should -Throw -ExpectedMessage '*scopeKey mismatch*'
    }
    It 'rejects reversed capture chronology' {
        { Compare-GmtSnapshots $script:current $script:baseline } | Should -Throw -ExpectedMessage '*Baseline must precede*'
    }
    It 'rejects changed requested group scopes even with same scopeKey' {
        $bad = $script:current | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
        $bad.requestedGroups = @('Domain Admins')
        { Compare-GmtSnapshots $script:baseline $bad } | Should -Throw -ExpectedMessage '*requestedGroups mismatch*'
    }
}

Describe 'Report safety and file outputs' {
    It 'neutralizes spreadsheet formula injection' {
        Protect-GmtCsvCell '=HYPERLINK("https://example.test")' | Should -Be "'=HYPERLINK(`"https://example.test`")"
        Protect-GmtCsvCell ' +SUM(1,2)' | Should -Be "' +SUM(1,2)"
        Protect-GmtCsvCell 'ordinary text' | Should -Be 'ordinary text'
    }
    It 'HTML-encodes untrusted display fields' {
        $result = Compare-GmtSnapshots $script:baseline $script:current
        $result.Findings[0].GroupName = '<img src=x onerror=alert(1)>'
        $html = ConvertTo-GmtHtml $result
        $html | Should -Match '&lt;img src=x onerror=alert\(1\)&gt;'
        $html | Should -Not -Match '<img src=x'
    }
    It 'writes parseable CSV, JSON, and offline HTML reports' {
        $result = Compare-GmtSnapshots $script:baseline $script:current
        $folder = Join-Path $TestDrive 'reports'
        $reports = Export-GmtReports -Result $result -OutputDirectory $folder
        @(Import-Csv -LiteralPath $reports.Csv).Count | Should -Be 10
        $json = Get-Content -LiteralPath $reports.Json -Raw | ConvertFrom-Json
        $json.Summary.TotalFindings | Should -Be 10
        (Get-Content -LiteralPath $reports.Html -Raw) | Should -Match '<!doctype html>'
    }
}
