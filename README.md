# Crux

## What is this?

Crux is a program that runs AI coding agents for you. You give it a short
YAML file that says which agent to run and with which model. Crux starts
the agent, keeps an eye on it, sends it work, and stops it when you say so.
It is the engine inside [Hive](https://github.com/hivecommons/hive), split
out so other projects can use it too.

## Why would I use it?

Running one coding agent by hand is easy. Running several, for hours,
without watching them, is not. Agents hang, crash, lose their place, or
try to do things they were never asked to do. Crux handles that part:

- It starts each agent inside tmux. tmux is a tool that keeps a terminal
  session alive in the background, so the agent keeps running after you
  close your window.
- It supports many agent CLIs behind one interface: Claude, Copilot,
  Gemini, Goose, Codex, Aider and Bob.
- It sends work to a running agent. Crux calls this a "kick". A small
  reminder to a stuck agent is a "nudge".
- It notices when an agent stalls or crashes over and over, and restarts
  or pauses it.
- Inside Hive, every write an agent makes to GitHub goes through a proxy.
  A proxy is a middle step that sees each request before it goes out, so
  it can log the request or refuse it. Crux also has tool approval (an
  allow list of what an agent may call) and an opt-in sandbox (a separate
  container or Kubernetes Job for each piece of work). These parts are
  wired up by Hive today; a plain `crux run` on your laptop does not turn
  them on for you.

Hive has run this engine in the open on real repositories. In one five-day
window in October 2026 it made 4,349 agent writes to GitHub, all through
the proxy, with 7 refused and recorded.

## Install

Pick one.

```sh
# Homebrew (macOS, Linux)
brew install hivecommons/hive/crux

# Go
go install github.com/hivecommons/crux/cmd/crux@latest

# Container image (amd64 and arm64; tmux is already inside)
docker run --rm ghcr.io/hivecommons/crux:0.1.0 --help
```

Or download a release archive from the
[releases page](https://github.com/hivecommons/crux/releases). There is
one for darwin and linux, each for amd64 and arm64. The checksums are
signed with cosign. cosign is a tool that proves a file was published by
this repo's release workflow and not changed since. That proof only holds
when you tell cosign which signer to expect, so the identity and issuer
flags below are required: cosign refuses to run without them, and a
wildcard would accept a signature from anyone. To check:

```sh
# from the v0.1.0 release page, download these three files first
cosign verify-blob checksums.txt \
  --bundle checksums.txt.sigstore.json \
  --certificate-identity-regexp '^https://github\.com/hivecommons/crux/\.github/workflows/release\.yml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
sha256sum -c checksums.txt --ignore-missing
tar xzf crux_0.1.0_linux_amd64.tar.gz
./crux --version
```

The container image is signed the same way:

```sh
cosign verify ghcr.io/hivecommons/crux:0.1.0 \
  --certificate-identity-regexp '^https://github\.com/hivecommons/crux/\.github/workflows/release\.yml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

The agent CLIs themselves (for example `copilot` or `claude`) are not
included. Install and log in to the one you want to run first, and make
sure `tmux` is on your PATH.

## Run your first agent

Make a folder with one definition file:

```sh
mkdir -p defs
cat > defs/scout.yaml <<'YAML'
apiVersion: hive.kubestellar.io/v1
kind: AgentDefinition
metadata:
  name: scout
spec:
  backend: copilot
  model: claude-sonnet-4-6
YAML
```

Then run it:

```sh
export CRUX_DEFS=./defs             # where crux looks for definitions
crux run scout                      # start scout and stream its output; Ctrl-C stops it
```

From a second terminal, while it is running:

```sh
crux ps                             # what is running
crux logs scout -n 50               # the last 50 lines of its screen
crux kick scout "look at issue 42"  # send it work
crux stop scout                     # stop it
```

Agent files live under `--workdir` (default `$HIVE_WORK_DIR`, then
`$HOME/.crux`). While `crux run` is in the foreground it opens a small
control socket in that folder, and `ps`, `logs`, `kick` and `stop` use it
to reach the live agent.

## Run it as a service

`crux serve` keeps the runtime up and exposes it over HTTP+JSON, so other
programs (or you, from another shell) can drive it:

```sh
# Serve on a unix socket. A unix socket is a file on disk that two
# programs on the same machine use to talk to each other.
crux serve --socket /run/crux/crux.sock

# From another shell, point the CLI at it.
export CRUX_SERVER=/run/crux/crux.sock
crux ps
crux run ./defs/scout.yaml
crux logs -f scout                  # follow its output
```

`--listen 127.0.0.1:PORT --token T` adds a loopback TCP listener. It
refuses to start without a token. Set `CRUX_TOKEN` instead of passing
`--token` each time. The routes are documented in Hive's
[`crux serve`](https://github.com/hivecommons/hive/blob/v5/src/docs/crux-serve.md)
page; the Go client lives in `github.com/hivecommons/crux/api`.

## How it fits with Hive

Hive is a system that runs a whole team of agents against a set of
repositories, with a governor that decides what runs, a dashboard, review
and evidence. Crux is the part of Hive that touches the agent processes.
Hive is its first user and can run Crux as a sidecar: a second process
that sits next to Hive and is reached over the unix socket from
`crux serve`. In-process is still Hive's default while the sidecar mode is
proven. Nothing in Crux depends on Hive. Hive's
[security model](https://github.com/hivecommons/hive/blob/v5/src/docs/security-model.md)
lists the controls, which ones belong to Crux, and what is still missing.

## Commands

| Command | What it does |
|---|---|
| `crux run <definition.yaml \| agent>` | Start an agent, stream its output, stop it on Ctrl-C. `--detach` returns right away. |
| `crux ps` | List running agents. `--json` for machine output. |
| `crux logs <agent>` | Show recent output. `-n N`, `--buffer`, `--full`, `--json`; `-f` follows when using `--server`. |
| `crux kick <agent> <message \| ->` | Send work to an agent. `-` reads the message from stdin. |
| `crux stop <agent>` | Stop an agent. |
| `crux serve` | Serve the runtime over HTTP+JSON. `--socket`, `--listen`, `--token`, `--hive-callback`. |
| `crux agy-turn` | Internal. The runtime types this into a pane itself; do not run it by hand. |
| `crux --version` | Print the version. |

Global flags: `--workdir`, `--defs` (same as `--config`), `--socket`,
`--local`, `--server`, `--token`. Environment variables that stand in for
them: `CRUX_DEFS`, `CRUX_SOCKET`, `CRUX_SERVER`, `CRUX_TOKEN`.

## Status

Current release: v0.1.0. This is early software.

What works today: the `crux` CLI (`run`, `ps`, `logs`, `kick`, `stop`),
`crux serve` with its HTTP+JSON API and Go client, remote mode with
`--server`, and the release train (archives, container image, cosign
signatures).

What is not there yet:

- Hive does not use the sidecar by default. In-process is still the
  default until the remaining stages prove parity.
- Credential callbacks are partial. The goal is that Crux never holds a
  long-lived GitHub key and asks Hive for short, scoped tokens instead.
- The per-task sandbox is opt-in and only exists as a rootless Podman
  container or a Kubernetes Job. Stronger sandboxes are under evaluation.
- No tenancy, quotas or multi-user auth. One runtime, one owner.
- Standalone `crux run` does not set up the proxy, tool approval or
  sandbox for you.

Progress is tracked in
[hivecommons/hive#14138](https://github.com/hivecommons/hive/issues/14138).
The design record is
[`src/docs/design/crux.md`](https://github.com/hivecommons/hive/blob/v5/src/docs/design/crux.md).

## Contributing

The Go code in this repository is not edited here. It is a copy of
[`src/crux`](https://github.com/hivecommons/hive/tree/v5/src/crux) in
hivecommons/hive, pushed by Hive's
[`crux-sync`](https://github.com/hivecommons/hive/blob/v5/.github/workflows/crux-sync.yml)
workflow on every change. `.hive-sync` names the exact Hive commit this
tree came from, and a `Sync guard` check rejects pull requests here that
touch Go files. Only the scaffolding is maintained in this repository:
`.github/`, `.goreleaser.yaml`, `Dockerfile`, this README and `LICENSE`.
The module's own README is synced to [`docs/MODULE.md`](docs/MODULE.md).

So: file issues and code changes in
[hivecommons/hive](https://github.com/hivecommons/hive). Releases are cut
by tagging Hive `crux/vX.Y.Z`. How the publish works is in
[`src/docs/crux-publish.md`](https://github.com/hivecommons/hive/blob/v5/src/docs/crux-publish.md).

## Licence

Apache-2.0. Open source under Hive Commons.
