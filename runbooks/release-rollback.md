# Runbook: rolling back a Crux release

Use this when a published `vX.Y.Z` release ships a binary, container image or
Homebrew formula that crashes, will not start agents, or is otherwise worse
than the previous release. Stop the spread first, diagnose afterwards.

## What a release publishes

A `vX.Y.Z` tag triggers `.github/workflows/release.yml`, which runs a smoke
test and then goreleaser. One tag produces:

- GitHub release archives (darwin and linux, amd64 and arm64) plus a
  cosign-signed `checksums.txt`.
- The multi-arch image `ghcr.io/hivecommons/crux:X.Y.Z` and `:latest`.
- The Go module version, which `go install ...@vX.Y.Z` resolves through the
  Go module proxy.
- Nothing in Homebrew by itself: `Formula/crux.rb` in
  `hivecommons/homebrew-hive` is bumped by a separate PR there.

The Go code here is a synced copy of `hivecommons/hive` `src/crux`, so the
code fix is a PR in `hivecommons/hive`; only the release scaffolding is
changed here.

## 1. Confirm the release is the cause

```sh
crux --version                      # the version users report
gh release view vX.Y.Z --repo hivecommons/crux
gh run list --repo hivecommons/crux --workflow Release --limit 5
```

If the Release run failed part-way, the release may be incomplete (archives
without an image, or the reverse). Re-run it with the `tag` input of
`workflow_dispatch` once the cause is fixed instead of rolling back.

## 2. Stop new installs of the bad release

Do these in order; each is independent and reversible.

1. **Homebrew.** If `Formula/crux.rb` already points at the bad version,
   revert that bump with the process in
   `hivecommons/homebrew-hive` `runbooks/rollback.md`. If the bump PR is
   still open, close it.
2. **GitHub release.** Mark the bad release as a pre-release or draft so it
   stops being "latest":

   ```sh
   gh release edit vX.Y.Z --repo hivecommons/crux --prerelease --latest=false
   gh release edit vPREVIOUS --repo hivecommons/crux --latest
   ```

3. **Container image.** `:latest` is a moving tag. Re-point it at the last
   good image so unpinned pulls recover:

   ```sh
   docker buildx imagetools create \
     -t ghcr.io/hivecommons/crux:latest \
     ghcr.io/hivecommons/crux:PREVIOUS
   ```

   Verify the good image is still the signed one before relying on it:

   ```sh
   cosign verify ghcr.io/hivecommons/crux:PREVIOUS \
     --certificate-identity-regexp '^https://github\.com/hivecommons/crux/\.github/workflows/release\.yml@' \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com
   ```

   Needs a token with `packages: write`; if you do not have one, hand this
   step to a maintainer.

## 3. Retract the Go module version

Release tags are never moved or deleted: the Go module proxy and checksum
database cache them permanently, and a rewritten tag breaks everyone who
already fetched it. Retract instead, by landing in `hivecommons/hive`
`src/crux/go.mod`:

```
retract vX.Y.Z // crashes on start; use vPREVIOUS
```

and publishing a new patch release (`crux/vX.Y.Z+1` tag in hive). Users on
`@latest` then skip the retracted version.

## 4. Ship the fix forward

Roll forward with a new patch tag; do not reuse the failed tag. The smoke
step in `release.yml` (`scripts/smoke.sh`) must pass before goreleaser runs.
If the bug escaped it, add the failing case to `scripts/smoke.sh` in the same
PR as the fix.

## 5. Verify recovery

- `docker run --rm ghcr.io/hivecommons/crux:latest --version` prints the
  good version.
- `brew update && brew info hivecommons/hive/crux` shows the good version.
- `go list -m -u github.com/hivecommons/crux@latest` does not return the
  retracted version (the proxy can take a few minutes).
- `gh release list --repo hivecommons/crux --limit 3` shows the good release
  as Latest.

Then write the postmortem: what shipped, why the smoke test missed it, and
what now catches it.
