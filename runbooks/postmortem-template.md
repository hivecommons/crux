# Postmortem template

Copy this file into an issue on this repository after any release that reached
users and was broken, withdrawn, or only partly published, and after a near miss
where the pre-release smoke test did not catch a defect. Keep it blameless:
describe what the system allowed, not who tagged or merged the change.

Do not paste tokens, registry credentials, or unreviewed workflow logs.

## Summary

One or two sentences: which tag was affected and how long the bad release was
available.

## Impact

- Who was affected: users who installed or upgraded through Homebrew,
  `go install`, a release archive, or the container image while the bad tag was
  current.
- Symptom, for example a crash on startup, agents that never launch, or a missing
  or unverifiable artifact.
- Bad version and the last known-good version.

## Timeline

| When (UTC) | Event |
|---|---|
| | Hive tagged `crux/vX.Y.Z` and the sync pushed `vX.Y.Z` here |
| | `Release` workflow finished (or failed) |
| | First report |
| | Cause identified |
| | Rollback completed ([release-rollback.md](release-rollback.md)) |
| | Fixed release published |

## Cause

What changed, and why the CI gates and the pre-release smoke test
(`scripts/smoke.sh`) did not catch it.

## What went well / what did not

- Detection: found by CI, a user report, or monitoring?
- Recovery: did [release-rollback.md](release-rollback.md) work as written?

## Follow-ups

Each item needs an owner and a linked issue. Prefer a CI or smoke-test check over
a documentation-only fix. Code fixes belong in `hivecommons/hive` `src/crux`.

- [ ] Check added to the smoke test or CI
- [ ] Runbook updated where a step was missing or wrong
