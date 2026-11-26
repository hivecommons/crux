# Incident: <short title>

Copy this file into the tracking issue while the incident is live; do not
commit filled-in incidents containing credentials or personal data. Once the
incident is resolved, continue in [postmortem-template.md](postmortem-template.md).

- **Status:** investigating | mitigating | monitoring | resolved
- **Severity:** <SEV1 users cannot use Crux / SEV2 degraded / SEV3 minor>
- **Started (UTC) / detected by:** <time, probe, alert or reporter>
- **Incident lead:**

## User impact

<Who is affected, which routes or agents, and since when. Update as it changes.>

## Triage

1. Is `GET /v1/health` failing? Follow [agent-not-working.md](agent-not-working.md).
2. Did it start after a release? Follow [release-rollback.md](release-rollback.md).
3. Record the version in use (`crux --version`) and the last known good version.

## Updates

| Time (UTC) | Update | Next check |
|---|---|---|
| | | |

## Mitigation

<What was done to stop the impact (rollback, restart, config change) and how
recovery was verified.>
