## Summary

<!-- What does this PR change, and why? Name the files it touches: workflows, .github/scripts, release config (.goreleaser.yaml, Dockerfile*), README.md or runbooks/. -->

Fixes #<!-- issue number, if this PR resolves one -->

## Validation

<!-- Which commands did you run, and what did you check by hand? -->

## Checklist

The Go code in this repository is a synced copy of [`src/crux` in hivecommons/hive](https://github.com/hivecommons/hive/tree/v5/src/crux). See [Contributing](https://github.com/hivecommons/crux#contributing) for how changes reach it.

- [ ] This PR touches no `*.go`, `go.mod`, `go.sum` or `.hive-sync` file. Those changes go to hivecommons/hive under `src/crux/` (base `v5`); the `Sync guard` check refuses them here
- [ ] Workflow changes pin every action to a full commit SHA, and `bash .github/scripts/check-action-pins.sh .github/workflows` passes
- [ ] Changes to `.github/scripts/` pass the matching self-test: `test-check-action-pins.sh`, `test-coverage-floors.sh` or `test-file-size-ratchet.sh`. `check-action-pins.sh` is a copy of hive's `src/scripts/check-action-pins.sh`; change it in hive first, then re-copy it here
- [ ] Changes to `.goreleaser.yaml` or `Dockerfile.goreleaser` pass `goreleaser check` and `goreleaser release --snapshot --clean --skip=publish,docker,sign,sbom`
- [ ] A new runbook is linked from `runbooks/README.md`
- [ ] Commits are signed off (`git commit -s`)
