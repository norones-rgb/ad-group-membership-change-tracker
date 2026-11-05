# Detection rules and severity (v0.1)

| Rule | Trigger | Severity | Caveat |
| --- | --- | --- | --- |
| Direct member added | Stable member ID exists only in current *complete* group | Privileged → High, Sensitive → Medium, Standard → Low | Change may be approved; ownership not checked |
| Group nested in privileged group | Newly added direct member has type `group` in a Privileged group | **Critical** | Detects a direct edge, not recursive members |
| Direct member removed | Stable member ID exists only in baseline *complete* group | Privileged → Medium, otherwise Low | Not proof of completed offboarding |
| Group missing from either capture | Group ID exists in only one side | High coverage gap | Not asserted as directory deletion |
| Group incomplete on either side | `complete=false` | High coverage gap | Membership diff suppressed entirely for group |
| Capture error | Failed requested-group lookup reported by collector | High evidence gap | May overlap with a missing group finding |
| Tier changed | Same group, changed `tier` | Medium | Classifications are provided by operator |
| Group renamed | Same group ID, changed display name | Low | No member change inferred |

**Severity is a review prioritization aid, not a certified risk score.**

## Why missing groups are not interpreted as empty groups

A missing group could mean a deleted AD group, an API failure, insufficient permissions, a forest trust issue, or a flawed snapshot scope. Without independent evidence, generating mass `MemberRemoved` findings would be misleading. This tool emits a group-level `CoverageGap` instead.

## Scope consistency

Snapshots must have the same `scopeKey` and identical sets of `requestedGroups` (case-insensitive) and be ordered by UTC capture time. Different inventory scopes are rejected rather than quietly intersected.

## No automatic privileged group discovery

Explicitly classify domain-specific privileged and sensitive groups. `Domain Admins` in the demo is marked privileged, but the engine does **not** automatically assign that tier for a real capture. Use `-PrivilegedGroups` when collecting in AD mode.
