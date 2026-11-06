# AD Group Membership Change Tracker

> **IAM Automation Toolkit · Project 3/5** | Read-only PowerShell evaluation MVP · Synthetic-first design
>
> [**Portfolio directory**](https://github.com/norones-rgb/ad-ldap-exception-risk-analyzer/blob/main/IAM-AUTOMATION-PORTFOLIO.md) · [**Run the demo**](DEMO.md) · [**Sample HTML preview**](docs/fixture-preview.html) · [**Windows/Linux CI**](https://github.com/norones-rgb/ad-group-membership-change-tracker/actions/workflows/ci.yml)
>
> [![Pester CI](https://github.com/norones-rgb/ad-group-membership-change-tracker/actions/workflows/ci.yml/badge.svg)](https://github.com/norones-rgb/ad-group-membership-change-tracker/actions/workflows/ci.yml) · PowerShell 7.2+ · CSV / JSON / offline HTML output


**PowerShell 7.2+ · Read-only Active Directory collection · Synthetic demo · CSV/JSON/HTML audit reporting**

A focused, read-only tool for recording direct Active Directory group memberships at two points in time and generating a reviewable record of membership additions, removals, privileged-group changes, and evidence gaps. Built for IAM operations, access governance, and consulting demonstrations.

> **Status: MVP v0.1 — evaluation build.** Synthetic fixture expectations are independently checked. Run the Pester suite and pilot in an authorized test environment before using with real directory data. There is no automatic remediation, scheduled task, or approval integration.

## Why this exists

A membership diff is easy to get wrong: failed directory queries and incomplete snapshots can look exactly like hundreds of removals. This tool takes a conservative approach: **when either side lacks complete evidence for a group, it reports a coverage gap and suppresses membership change assertions for that group.**

## Capabilities

| Feature | Behavior |
| --- | --- |
| Direct memberships | Added/removed users, groups, computers, and other AD principals |
| Nested-group awareness | Detects when a **group object** is directly added to a privileged group (critical finding) |
| Privilege tiers | Explicit `Privileged`, `Sensitive`, `Standard` classification per group |
| Snapshot validation | Checks schema, timestamps, IDs, member types, duplicates, and capture order |
| Scope guardrails | Rejects different scope keys or different requested-group sets |
| Collection confidence | Missing, newly appearing, or incomplete groups generate coverage gaps instead of fabricated removals |
| Read-only AD collector | `Get-ADGroup` and `Get-ADGroupMember` only; no directory writes |
| Reports | CSV (spreadsheet formula neutralization), JSON, offline HTML (escaped output) |
| Test automation | Pester tests on Windows and Linux in GitHub Actions |

**Not included:** effective/transitive membership expansion, event-log attribution (who made a change), approval-ticket matching, SID history, cross-forest resolution, remediation, real-time monitoring, and entitlement verification outside AD. A finding is a **change or evidence issue**, not proof of unauthorized activity.

## Quick start — no AD connection

Install [PowerShell 7.2+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell), extract/clone this repository, then run in its root:

```powershell
./Invoke-GroupMembershipTracker.ps1 -Action Demo
```

This compares `sample-data/baseline.json` and `sample-data/current.json` and writes:

```text
output/group-membership-findings.csv
output/group-membership-findings.json
output/group-membership-report.html
```

The demonstration expects **10 findings: 1 Critical, 5 High, 1 Medium, 3 Low**, including 5 additions, 2 removals, and 3 evidence gaps. See [fixture walkthrough](docs/expected-fixture.md) and [sample HTML preview](docs/fixture-preview.html). **The preview is illustrative and was generated independently of a PowerShell runtime.**

To compare two existing snapshots:

```powershell
./Invoke-GroupMembershipTracker.ps1 -Action Compare `
  -BaselinePath ./sample-data/baseline.json `
  -CurrentPath ./sample-data/current.json `
  -OutputDirectory ./output
```

## Capture a read-only AD snapshot

**Requirements:** Windows host with PowerShell 7.2+, RSAT `ActiveDirectory` module installed, network access, and directory read permissions. The snapshot is saved **locally**. Capture mode refuses to overwrite an existing snapshot path. Explicitly scope group names; there is no whole-directory enumeration mode.

```powershell
./Invoke-GroupMembershipTracker.ps1 -Action CaptureAD `
  -ScopeKey 'iam-quarterly-group-watch' `
  -Groups @('Domain Admins', 'Account Operators', 'Finance Reports') `
  -PrivilegedGroups @('Domain Admins','Account Operators') `
  -SensitiveGroups @('Finance Reports') `
  -SnapshotPath './private-data/baseline.json'
```

Run the same capture later, using the **same scope key, requested groups, and tier lists**:

```powershell
./Invoke-GroupMembershipTracker.ps1 -Action CaptureAD `
  -ScopeKey 'iam-quarterly-group-watch' `
  -Groups @('Domain Admins', 'Account Operators', 'Finance Reports') `
  -PrivilegedGroups @('Domain Admins','Account Operators') `
  -SensitiveGroups @('Finance Reports') `
  -SnapshotPath './private-data/current.json'

./Invoke-GroupMembershipTracker.ps1 -Action Compare `
  -BaselinePath './private-data/baseline.json' `
  -CurrentPath './private-data/current.json' `
  -OutputDirectory './private-data/evidence'
```

Optionally add `-Server 'dc01.example.internal'` to both captures to select the same domain controller. Domain controller identifiers in this README are illustrative.

**Caution:** The tool intentionally does not scrub names, DNs, or GUIDs from real snapshots; treat every real snapshot and generated evidence as potentially sensitive internal data. The `private-data/` directory is excluded by `.gitignore`, but check `git status` before publishing anything.

## How comparison works

1. Validate both JSON snapshots and confirm baseline timestamp precedes current timestamp.
2. Require identical `scopeKey` and `requestedGroups` sets. Refuse unmatched scopes rather than produce misleading diffs.
3. Match groups by stable `id` (GUID or, when necessary, distinguished name), not display name.
4. For a group present and **complete** in both snapshots, match direct members by stable ID; compare additions and removals.
5. If a group is missing or incomplete on either side, flag a **High** coverage gap and **do not** infer removals or additions for it.
6. Escalate newly added *group members* in privileged groups to **Critical**. Tier levels are user-supplied, not automatically determined.
7. Produce deterministic event identifiers and local CSV/JSON/HTML reports. The comparison itself never changes AD.

See [rules and severity definitions](docs/rules.md), [architecture](docs/architecture.md), and [snapshot schema](docs/snapshot-schema.md).

## Tests and CI

Requires the [Pester](https://pester.dev/) module 5.6.1 or newer:

```powershell
Install-Module Pester -MinimumVersion 5.6.1 -Scope CurrentUser -Force
Invoke-Pester -Path ./tests -CI -Output Detailed
```

The GitHub Actions workflow runs Pester on Windows and Linux and runs the synthetic demo. **It does not connect to AD.** The AD collector requires separate authorized testing on Windows/RSAT.

## Repository layout

```text
.
├── Invoke-GroupMembershipTracker.ps1       # CLI: Demo, Compare, CaptureAD
├── src/GroupMembershipTracker.psm1         # Validation, diff, AD collector, reporting
├── sample-data/baseline.json               # Fake initial capture
├── sample-data/current.json                # Fake later capture
├── config/group-tiers.example.json         # Classification planning example
├── tests/GroupMembershipTracker.Tests.ps1  # Offline Pester regressions
├── docs/
│   ├── architecture.md
│   ├── rules.md
│   ├── snapshot-schema.md
│   ├── expected-fixture.md
│   ├── pilot-checklist.md
│   ├── security-and-privacy.md
│   └── fixture-preview.html
├── .github/workflows/ci.yml                # Windows/Linux verification
├── NOTICE
└── output/.gitkeep                        # Reports are ignored by Git
```

## Risk and permission boundaries

- **Directory access:** read-only (no `Set-AD*`, `Add-AD*`, `Remove-AD*`, or write-back endpoints).
- **Local access:** creates snapshot and report files in paths you specify; protect them as you would audit evidence.
- **Group scope:** explicit requested groups only. Capture failures are recorded as gaps.
- **Governance:** authorize a test pilot and review sensitivity of evidence before any production use.
- **Commercial/IP:** this is a public portfolio demonstration, not a grant of rights to reuse it. There is no open-source license in this repository; see `NOTICE`.

## Roadmap

- v0.2: signed baseline manifests, hashes, and immutable evidence packaging
- v0.3: optional change-ticket correlation and exception allowlists (read-only)
- v0.4: historical trends, ownership context, and scheduled report templates
- Future: optional effective-membership path analysis with explicit domain trust limits

*All supplied sample identities are fictional.*