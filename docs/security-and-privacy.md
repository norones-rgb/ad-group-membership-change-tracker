# Security and privacy

This project performs **read-only AD queries** and writes data **only to operator-selected local paths**. Capture mode refuses to overwrite an existing snapshot file. It does not disable users, change groups, execute remediations, or contact cloud APIs.

## Sensitive data boundaries

Live snapshots can contain account and group names, DNs, stable identifiers, privilege classifications, and access history. These are potentially sensitive security records. Restrict operator access, protect exported files, use appropriate retention, and avoid public GitHub uploads. The supplied `sample-data/` files are synthetic.

## Failure behavior

- If a group query fails to enumerate every member, its members list is cleared and `complete=false`.
- Missing and incomplete groups lead to high-priority evidence gaps, **not** access-removal claims.
- Incompatible scopes and invalid snapshots cause termination without reports.
- No implicit AD-wide discovery; selected groups must be explicitly provided.
- CSV output neutralizes spreadsheet formula prefixes and HTML encodes untrusted values.
- Identity matching uses a stable GUID where available; DN fallback is less robust.

## Reporting vulnerabilities

If you discover a potential security defect, do not post live directory records in a public issue. Contact the repository owner using a private channel and provide a synthetic reproduction. This public repository does not contain a license granting production deployment rights.

## Limitations and audit evidence

The tool is an evidence-producing aid, not an IAM source of truth or a certification engine. Collection errors, directory permissions, replication delay, stale captures, domain trusts, and inaccurate tier lists may change what can be concluded from reports. Only fully observed direct memberships are compared.
