# Authorized pilot checklist

## Before collection

- [ ] Obtain approval from AD owner, security team, and data steward.
- [ ] Run first in a test OU / lab or nonproduction domain.
- [ ] Confirm Windows PowerShell 7.2+ and the RSAT ActiveDirectory module.
- [ ] Confirm operator has only the required directory **read** permissions.
- [ ] Document targeted domain controller and replication assumptions.
- [ ] Define explicit group identities and tier classifications; avoid accidental scope growth.
- [ ] Set a stable scope key, retention schedule, local ACLs, and encrypted evidence storage.
- [ ] Verify `.gitignore`; store real captures outside the public repository.

## During test

- [ ] Run `-Action CaptureAD` twice with the same scope and tier assignments.
- [ ] Verify group/member counts against independent read-only AD queries.
- [ ] Simulate one approved membership add and one removal in a **lab**, outside this tool.
- [ ] Simulate a denied query and confirm `complete=false` and no fabricated removals.
- [ ] Review GUID and DN fallback behavior, nested groups, and cross-forest cases.
- [ ] Compare snapshots and inspect all three reports.
- [ ] Confirm Pester tests pass and review HTML/CSV handling of untrusted names.

## After pilot

- [ ] Record the runbook, operator, scope, evidence location, and disposition of each finding.
- [ ] Remove or encrypt exported evidence according to internal data policy.
- [ ] Document known gaps (no approval correlation, no event attribution, no recursion).
- [ ] Do not label the tool production-ready until the organization completes validation.
