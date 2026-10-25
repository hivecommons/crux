# Crux

**A fully governed AI agent platform.** Trust, productivity, non-rogue.

Crux is the agent runtime inside [Hive](https://github.com/hivecommons/hive), split out as a reusable open-source component. It runs AI agents from definitions and makes four promises about every one of them:

| Promise | What it means | How Crux keeps it |
|---|---|---|
| **Productive** | Agents ship real work on real repos, continuously, without a human babysitting each run. | Short-lived agents with a clean context, external context injected per run, stall and crash-loop recovery, kicks and nudges, seven engines behind one interface. |
| **Non-rogue** | An agent cannot act outside the scope it was given, even if the model wants to. | Limits enforced in code at the tool boundary: a MITM proxy in front of every write, tool approval, per-agent identity and credentials, and an opt-in per-task sandbox (rootless container or Kubernetes Job) behind one launcher seam; see [Isolation](#isolation) for what is default and what is not. |
| **Tamper-evident** | If prompt injection, a hostile repo or a bad dependency does bend an agent, it leaves a trace and hits a boundary that can refuse it. Nothing happens off the record. | No agent self-report is trusted. Every write passes a boundary that logs it and can refuse it; policy lives outside the model; a credential-free workspace when sandboxed; scrubbed logs; signed, scoped credentials that expire. |
| **Governed** | A human owns the record of what happened and why, and can stop it. | A gate before anything lands, trust levels that decide how much runs unattended, an audit log and telemetry via [pluk](https://github.com/hivecommons/pluk), and evidence a reviewer can check. |

These promises are backed by code, not by a prompt. Hive's [security model](https://github.com/hivecommons/hive/blob/v5/src/docs/security-model.md) is the inventory: 38 controls that protect maintainers from the agents they run, each one tied to a file path, config key or ADR, with a section on [what is not done yet](https://github.com/hivecommons/hive/blob/v5/src/docs/security-model.md#11-what-hive-does-not-do-yet) and [how to audit a running hive](https://github.com/hivecommons/hive/blob/v5/src/docs/security-model.md#12-how-to-audit-a-running-hive). The agent-runtime controls in that list are the ones that move into Crux.

Hive is the first consumer. It has run this runtime in the open on 27 hives and their production repositories (October 2026): 4,349 agent writes to GitHub in one five-day window, every one through the proxy, 7 refused and on record. Anything that needs a governed agent can be the next consumer.

## Install

```sh
# Homebrew (macOS, Linux)
brew install hivecommons/hive/crux

# Go
go install github.com/hivecommons/crux/cmd/crux@latest

# Container (ships tmux, which the runtime drives)
docker run --rm ghcr.io/hivecommons/crux:latest --help
```

Release archives for darwin/linux × amd64/arm64, with sha256 checksums signed
by cosign (keyless), are on the [releases page](https://github.com/hivecommons/crux/releases).

## Quick start

```sh
# 1. Serve an (initially empty) runtime on a unix socket.
crux serve --socket /tmp/crux.sock
# serving 0 agent definition(s) on unix:///tmp/crux.sock

# 2. From another shell, drive it.
crux --server /tmp/crux.sock ps

# 3. Run an agent from a definition file (a single-agent YAML definition or
#    the name of an agent the server was configured with).
crux --server /tmp/crux.sock run agent.yaml
crux --server /tmp/crux.sock logs <name>
crux --server /tmp/crux.sock kick <name> "look at issue #12"
crux --server /tmp/crux.sock stop <name>
```

`crux serve --config hive.yaml` serves the enabled agents of a hive
configuration; `--listen 127.0.0.1:PORT --token T` adds a loopback TCP
listener (refused without a token). Set `CRUX_SERVER` / `CRUX_TOKEN` instead
of passing `--server` / `--token` every time. The HTTP+JSON API behind the
CLI is documented in hive's
[`crux serve`](https://github.com/hivecommons/hive/blob/v5/src/docs/crux-serve.md)
and [`crux` CLI](https://github.com/hivecommons/hive/blob/v5/src/docs/crux-cli.md)
pages; the Go client is `github.com/hivecommons/crux/api`.

## How this repository is produced

The Go code here is **not edited in this repository** (see [Status](#status)
for the source of truth). Hive's
[`crux-sync`](https://github.com/hivecommons/hive/blob/v5/.github/workflows/crux-sync.yml)
workflow copies `src/crux` here on every change, rewriting the module path
`github.com/hivecommons/hive/crux` → `github.com/hivecommons/crux`;
`.hive-sync` names the exact hive commit this tree came from, and the
`Sync guard` check refuses pull requests here that touch Go code.

- Releases are cut by tagging hive `crux/vX.Y.Z`; the sync pushes `vX.Y.Z`
  here and the release workflow builds the binaries, image and checksums.
- Only the scaffolding is maintained here: `.github/`, `.goreleaser.yaml`,
  `Dockerfile`, this README, `LICENSE`.
- The module's own README is synced to [`docs/MODULE.md`](docs/MODULE.md).
- How the publish works, and why it is a plain copy rather than a subtree
  split: [`src/docs/crux-publish.md`](https://github.com/hivecommons/hive/blob/v5/src/docs/crux-publish.md)
  in hive.

## Why "Crux"

It is the crux of the matter. Models are good enough now; the failure mode that matters is an agent doing the wrong thing with the right skills. Crux is the point everything turns on: the layer where trust, productivity and non-rogue behaviour are decided in code, not in a prompt.

## Status

Source of truth: [`src/crux`](https://github.com/hivecommons/hive/tree/v5/src/crux) in [hivecommons/hive](https://github.com/hivecommons/hive), the nested Go module `github.com/hivecommons/hive/crux`. This repository is synced from it and published as `github.com/hivecommons/crux`. File issues and PRs in hive. Design record: [`src/docs/design/crux.md`](https://github.com/hivecommons/hive/blob/v5/src/docs/design/crux.md); tracker: [hivecommons/hive#14138](https://github.com/hivecommons/hive/issues/14138) (stage 1 was [#13536](https://github.com/hivecommons/hive/issues/13536), closed).

Shipped:

- In-repo boundary inside hive: `crux.Runtime` interface, inbound and outbound architecture ratchets, tmux funnel, agent-runtime config struct, CI path filters.
- Nested Go module `github.com/hivecommons/hive/crux` at `src/crux`, joined to the hive root module by a Go workspace.
- `crux` CLI: `run`, `ps`, `logs`, `kick`, `stop`.
- `crux serve`: HTTP+JSON over a Unix socket that is `0600` from the moment it is reachable; TCP only behind a bearer token; server-sent events for lifecycle and kick streams. Wire contract in `crux/api`, stdlib-only so a client does not link the runtime.
- Go client (`api.NewClient`) and CLI remote mode (`crux --server ADDR` / `CRUX_SERVER`).
- Inbound coupling from hive down to a single `cmd/hive` row; outbound coupling from the runtime back into hive is zero.

Next, in the order #14138 lists them:

- Hive consuming its own serve API as a staged sidecar (runtime seam first, in-process stays the default until parity is proven).
- Credential callbacks: the runtime never holds the GitHub App key; hive mints scoped tokens through callbacks.
- Sandbox runtime adapters per [ADR-0026](https://github.com/hivecommons/hive/blob/v5/src/docs/adr/0026-sandbox-runtime-selection.md); see [Isolation](#isolation).
- Release train: `crux/vX.Y.Z` tags and `cmd/crux` moving into the nested module.

## What is in scope

- Run an agent from a definition: engine, model, prompt, tools, limits.
- Lifecycle: start, observe, nudge, stall and crash-loop recovery, stop.
- Engines: Claude, Copilot, Gemini, Goose, Codex, Aider, Bob; any OpenAI-compatible model through the gateway.
- Policy enforcement at the tool boundary: MITM proxy, tool approval.
- Isolation: shared container by default; opt-in per-task sandbox (rootless Podman container or Kubernetes Job) behind the `sandbox.Launcher` seam.
- Identity, credentials, entitlements.
- Telemetry and audit via pluk.

Staying in Hive: governor, GitHub and forge integration, review swarm, evidence, dashboard, hub.

## Isolation

What isolation is today, stated plainly:

- **Default: shared container, separated by Unix user.** Agents in one hive run in the same container as the runtime. The boundary around them is the MITM proxy, tool approval, scoped credentials and the audit record, not a kernel-enforced sandbox.
- **Opt-in: a sandbox per task.** With the sandbox enabled, each kick runs in its own rootless Podman container or, with `sandbox.runtime: job`, a Kubernetes Job in the hive's namespace. The workspace is prepared outside the sandbox and is credential-free: no GitHub token enters, and credential-named environment variables are filtered out. Commits are read back after the run and pushed by the push broker, which scans the diff and mints a short-lived scoped token outside the sandbox. GitHub stays mediated by the proxy.
- **One seam.** Both runtimes implement `crux/sandbox.Launcher`, a single method: `Run(ctx, LaunchSpec) (Result, error)`. A stronger runtime is one more adapter behind that interface, not a redesign.
- **Under evaluation.** [ADR-0026](https://github.com/hivecommons/hive/blob/v5/src/docs/adr/0026-sandbox-runtime-selection.md) (Proposed) sets the contract an adapter must satisfy (C1-C6: prepared workspace in, credential-free, broker pushes, proxy mediates GitHub, transcript and exit code out, no privileged pods on hosted spokes) and evaluates NVIDIA OpenShell and AAIF OpenSandbox against it. It recommends OpenShell on paper; the prototype on a hive spoke ([hivecommons/hive#14092](https://github.com/hivecommons/hive/issues/14092)) is pending and no integration exists yet. The default stays shared-container until an adapter is proven on a hosted spoke.

In every mode, no agent self-report is trusted: what an agent did is what the proxy, the broker and the audit log recorded. Details: hive's [sandbox isolation](https://github.com/hivecommons/hive/blob/v5/src/docs/sandbox-isolation.md) (threat model, hub versus contributor paths, remaining gaps) and the [security model](https://github.com/hivecommons/hive/blob/v5/src/docs/security-model.md#3-agent-runtime-isolation).

## What else could run on Crux

Any system that wants agents to do work without trusting the agent: an enterprise agent service, a policy proxy in front of a harness you did not write, a model gateway with entitlements, ops and SRE runbooks, documentation upkeep, security response, research pipelines, a local runner on a laptop.

## License

Apache-2.0. Open source under Hive Commons; anyone may productize on top.
