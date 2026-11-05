# Synthetic fixture walkthrough

The JSON captures use entirely invented groups and people, with baseline **November 1, 2026, 12:00 UTC** and current **November 5, 2026, 12:00 UTC**.

| Finding | Group | Detail | Severity |
| --- | --- | --- | --- |
| MemberAdded | Domain Admins | Workstation Operators group nested directly | Critical |
| MemberAdded | Domain Admins | Mallory New Admin added | High |
| MemberAdded | MFA Exceptions | External Support added | High |
| MemberAdded | Finance Reports | Adam User added | Low |
| MemberAdded | VPN Remote | Temporary Contractor added | Medium |
| MemberRemoved | Helpdesk Operators | Adam User removed | Low |
| MemberRemoved | Legacy App | Leo Legacy removed | Low |
| CoverageGap | Auditors | Missing from current capture; no removals inferred | High |
| CoverageGap | Secret Projects | Current membership collection incomplete | High |
| CoverageGap | App Support | Missing from baseline; no additions inferred | High |

**Expected:** 10 findings → 1 critical, 5 high, 1 medium, 3 low. Five direct additions, two direct removals, three evidence gaps. Six fully comparable groups.

`Secret Projects` contains a member in the baseline but an empty current collection marked `complete=false`: the analyzer must **not** report a removal. `Auditors` is absent from the current snapshot: it must **not** report all old members as removed.

These data were designed to demonstrate safe comparison logic. They are **not** a capture of a live enterprise directory.
