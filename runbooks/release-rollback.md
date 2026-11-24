# Release rollback

Use this when a published Crux release is broken and must be withdrawn or
superseded.

A release is built by `.github/workflows/release.yml` from a `vX.Y.Z` tag. It
publishes archives, the `ghcr.io/hivecommons/crux` image and a GitHub release.
The Homebrew formula (`Formula/crux.rb` in hivecommons/homebrew-hive) is bumped
by pull request.

Do not move or delete a published tag: `go install ...@vX.Y.Z` consumers and
the Go module proxy have already cached it. Supersede it instead.

## 1. Stop the spread

1. Mark the GitHub release as a pre-release, or edit its notes to say it is
   broken and which version to use instead.
2. If the formula was already bumped, revert that pull request in
   hivecommons/homebrew-hive so `brew install hivecommons/hive/crux` resolves
   to the last good version.

## 2. Ship the fix

1. Fix the code in hivecommons/hive under `src/crux/`; this repository's Go
   code is a synced copy and its `Sync guard` check refuses direct changes.
2. Tag the next patch version (`crux/vX.Y.Z+1` in hive). The sync workflow
   pushes the `vX.Y.Z+1` tag here and `Release` runs.
3. To rebuild an existing tag without a new version, run `Release` by hand
   with the `tag` input.

## 3. Verify

```sh
brew update && brew upgrade hivecommons/hive/crux
crux --version
docker run --rm ghcr.io/hivecommons/crux:<version> --version
```

Then record what happened with [postmortem-template.md](postmortem-template.md).
