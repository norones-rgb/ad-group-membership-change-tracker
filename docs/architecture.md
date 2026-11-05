# Architecture and trust boundaries

## Components

```text
Synthetic snapshots ────────────────┐
                                    │
Read-only AD collector ── local JSON┼── schema/scope validation ── stable-ID diff
                                    │                                  │
Existing snapshot pairs ────────────┘                                  ├── CSV evidence (formula safe)
                                                                       ├── JSON machine report
                                                                       └── HTML review dashboard
```

The controller `Invoke-GroupMembershipTracker.ps1` chooses one of three actions:

- `Demo`: compares two deterministic synthetic JSON snapshots shipped with the repository.
- `Compare`: loads any two schema-compatible local snapshot files, validates all scope and identity fields, and emits local reports.
- `CaptureAD`: reads **explicitly selected** groups with `Get-ADGroup` and `Get-ADGroupMember` (direct members only). Produces a local JSON snapshot; no comparison unless the operator runs one later.

## Stable keys and renames

Groups and members use the AD `ObjectGUID` when available, falling back to distinguished name when not. The sample uses opaque synthetic IDs. Renaming a group with the same ID does not become a deletion and re-addition; it creates a low-severity metadata event. A member display-name change with a stable ID is not a membership change.

A DN fallback is less stable across moves/renames, and cross-forest identity resolution has known limitations. For production, favor GUID coverage and document exceptions.

## Fail-closed observation model

Each group has `complete: true|false`. A group can be trusted for diff purposes **only if it appears in both captures and both observations are marked complete**. An empty `members: []` list is meaningful only on a complete group. If an AD membership enumeration errors, the collector clears the partial list and sets `complete: false`.

Groups missing on either side are a **coverage gap**, not a confirmed group deletion or a removal of every prior member. Failed group lookups additionally populate `captureErrors` for review.

These controls prevent many common false positives, but the system cannot prove directory replication consistency or validate external change approvals. Treat findings as evidence to investigate.

## Risk classification

Group tiers are input data. `-PrivilegedGroups` and `-SensitiveGroups` explicitly classify groups during AD capture. All others default to `Standard`; **that default is a limitation** and must not be interpreted as a verified risk rating.

## Output safety

- HTML uses server-side HTML entity encoding for every data-derived value, with no external assets or scripts.
- CSV strings starting with spreadsheet formula prefixes (`=`, `+`, `-`, `@`, optionally after whitespace) are prefixed with a literal apostrophe.
- JSON preserves raw report values for structured ingestion and therefore requires access controls.
- Local output overwrites files with the same report names in the destination folder.
- `.gitignore` excludes `output/` and `private-data/`, not arbitrary paths. Do not place production captures in the repository.

## Operational limitation

The collector is intentionally not run as part of CI. The workflow exercises only synthetic fixture data on hosted Windows/Linux PowerShell. An authorized Windows/RSAT pilot is needed to validate real directory behavior.
