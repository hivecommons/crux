# Runbook: rolling back a bad crux release

A crux release is a `vX.Y.Z` tag on this repository. `.github/workflows/release.yml`
turns the tag into: darwin/linux × amd64/arm64 archives, a cosign-signed
`checksums.txt`, a multi-arch `ghcr.io/hivecommons/crux:X.Y.Z` image, and a GitHub
release. The Homebrew formula (`Formula/crux.rb`) lives in
`hivecommons/homebrew-hive` and is bumped there by pull request. The Go code here
is a synced copy of `hivecommons/hive` `src/crux`, so a code fix is made in hive,
not here (see `.hive-sync`).

## Detect

- `crux --version` reports a version that fails on first use, or the pre-release
  smoke step (`scripts/smoke.sh`) passed but real agents fail to start.
- A `Release` workflow run failed part-way: some artifacts (image, release,
  signature) exist for the tag and others do not.
- Users report a bad `brew upgrade`, `go install`, or image pull for the tag.

## Contain

1. Identify the last good tag and the bad one:
   ```sh
   gh release list --repo hivecommons/crux
   ```
2. Mark the bad GitHub release as a pre-release (or draft it) so it stops being
   "Latest". Do not delete the tag: Go module proxies cache it, and a deleted tag
   that is later re-pushed with different content breaks checksum verification.
   ```sh
   gh release edit <bad-tag> --repo hivecommons/crux --prerelease --latest=false
   gh release edit <good-tag> --repo hivecommons/crux --latest
   ```
3. Homebrew: revert the `crux.rb` bump in `hivecommons/homebrew-hive` to the good
   version, following that repository's `runbooks/rollback.md`.
4. Container image: do not overwrite the bad `X.Y.Z` tag. Tell users to pin the
   good version (`ghcr.io/hivecommons/crux:<good-version>`).
5. Go users: `go install github.com/hivecommons/crux/cmd/crux@<good-tag>`. If the
   bad version must be withdrawn for module consumers, add a `retract` directive
   in the next release (made in hive `src/crux/go.mod`).

## Verify

1. `gh release view <good-tag> --repo hivecommons/crux` shows it as Latest.
2. A clean install of the good version runs: `crux --version`, then
   `CRUX_BIN=$(command -v crux) scripts/smoke.sh`.
3. Verify the signature of the good release's `checksums.txt` with the
   `cosign verify-blob` command documented in `.goreleaser.yaml`.
4. `brew info hivecommons/hive/crux` shows the good version.

## Fix forward

- Fix the cause in `hivecommons/hive` `src/crux`; the sync publishes it here and a
  new patch tag `vX.Y.(Z+1)` produces the replacement release. Never reuse a tag.
- If only the release workflow failed (code is fine), re-run it with
  `workflow_dispatch` and the existing tag as the `tag` input. goreleaser
  `--clean` rebuilds the artifacts; check that the release has no duplicated or
  missing assets afterwards.
- Do not weaken the smoke step, signing, or tag-sanity checks to get a release out.

After the incident is resolved, record it using
[postmortem-template.md](postmortem-template.md).
