# Snapshot JSON schema (human-readable)

Each snapshot is UTF-8 JSON with the following structure:

```json
{
  "schemaVersion": 1,
  "capturedAtUtc": "2026-11-05T12:00:00Z",
  "scopeKey": "iam-quarterly-group-watch",
  "source": "synthetic",
  "requestedGroups": ["Domain Admins", "Finance Reports"],
  "groups": [
    {
      "id": "g-123",
      "name": "Domain Admins",
      "tier": "Privileged",
      "complete": true,
      "collectionError": "",
      "members": [
        {"id":"u-123", "name":"Sample Admin", "type":"user"}
      ]
    }
  ],
  "captureErrors": []
}
```

- `schemaVersion` is exactly integer `1`.
- `capturedAtUtc` requires `yyyy-MM-ddTHH:mm:ssZ` in UTC. The baseline must be older than current.
- `scopeKey` is a stable operator-provided identifier; change it when the intended set/meaning of captured groups changes.
- `requestedGroups` must be nonempty and unique. Compare requires the same entries on both sides, disregarding case and order.
- `groups` can be an empty array if collection fails; completeness is required on each observed group. Group IDs must be unique.
- `members` can be empty only when that group has no observed members, or when collection failed and `complete=false`. Member IDs must be unique within a group.
- `tier`: `Privileged`, `Sensitive`, or `Standard`.
- `member.type`: `user`, `group`, `computer`, `service`, `foreign`, `other`.
- `captureErrors`: array of human-readable collection errors; the AD collector intentionally suppresses detailed exception strings and credentials.

**Stable IDs matter:** the collector uses AD `ObjectGUID` or falls back to DN. The mock fixtures use synthetic opaque IDs. The analyzer does not rely on display names for change detection.
