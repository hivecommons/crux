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
docker run --rm ghcr.io/hivecommons/crux:0.2.0 --help
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
# from the v0.2.0 release page, download these three files first
cosign verify-blob checksums.txt \
  --bundle checksums.txt.sigstore.json \
  --certificate-identity-regexp '^https://github\.com/hivecommons/crux/\.github/workflows/release\.yml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
sha256sum -c checksums.txt --ignore-missing
tar xzf crux_0.2.0_linux_amd64.tar.gz
./crux --version
```

That archive example is for Linux on amd64. On macOS choose `darwin_arm64`
for Apple Silicon or `darwin_amd64` for Intel from the same release. Keep the
signature-verification command unchanged. macOS includes `shasum`, so verify
the selected archive against its signed checksum before extracting it:

```sh
# Apple Silicon example; use darwin_amd64 in both places on Intel
grep 'crux_0.2.0_darwin_arm64.tar.gz$' checksums.txt | shasum -a 256 -c -
tar xzf crux_0.2.0_darwin_arm64.tar.gz
./crux --version
```

The container image is signed the same way:

```sh
cosign verify ghcr.io/hivecommons/crux:0.2.0 \
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
crux logs -n 50 scout               # the last 50 lines of its screen
crux kick scout "look at issue 42"  # send it work
crux stop scout                     # stop it
```

While `crux run` is still active, `crux ps` should list `scout`; `crux logs
scout -n 50` should show the agent's startup or prompt. Output varies by
backend. If startup fails, check `command -v tmux` and `command -v copilot`,
then run and authenticate the agent CLI directly before retrying. Do not send
the example issue task until you have a repository and task you intend it to work on.

Agent files live under `--workdir` (default `$HIVE_WORK_DIR`, then
`$HOME/.crux`). While `crux run` is in the foreground it opens a small
control socket in that folder, and `ps`, `logs`, `kick` and `stop` use it
to reach the live agent.

## Run it as a service

`crux serve` keeps the runtime up and exposes it over HTTP+JSON, so other
programs (or you, from another shell) can drive it:

The example assumes `/run/crux` already exists and is writable by the service
user; it is not normally writable by an ordinary macOS or Linux user.
For a local trial, use a socket path in a private directory you own instead
and set `CRUX_SERVER` to that same path. Do not make a shared socket world-writable.

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

When a running service misbehaves (`/v1/health` fails, an agent is stuck,
a release has to be withdrawn), start from the
[runbooks index](runbooks/README.md).

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
them: `CRUX_DEFS`, `CRUX_SERVER`, `CRUX_TOKEN`. (`CRUX_SOCKET` is not used for
the global `--socket`; it sets the listening socket for `crux serve --socket`.)

## Status

Current release: v0.2.0. This is early software.

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

## What crux exposes

**Go integrator reference starts here.** If you only want to operate agents,
the [commands](#commands), [service setup](#run-it-as-a-service), and
[runbooks](runbooks/README.md) are enough. The remaining interfaces and routes
are for programs embedding or calling Crux.

<details>
<summary>Advanced: Go interfaces, HTTP routes, host callbacks, and packages</summary>

Crux has three layers you can build on. Each one is a Go package in this
repository. The first is the Go interface. The second is the same thing
over HTTP. The third is what crux asks the host for in return.

### 1. `crux.Runtime`, the Go interface

`crux.Runtime` lives in [`runtime.go`](runtime.go). Today it runs in the
same process as the host. After stage 5 of the sidecar work it can also be
backed by the API in layer 2, with no change to the caller. It is made of
eleven smaller interfaces, one per job:

| Role | Methods |
|---|---|
| `Lifecycle` | `Start`, `Stop`, `Restart`, `RestartWithBootstrap`, `Pause`, `PauseBy`, `Resume`, `IsPaused`, `ResetRestartCount` |
| `Observer` | `GetStatus`, `GetStatusFast`, `AllStatuses`, `ResolveAgent`, `GetOutput`, `GetBufferOutput`, `CaptureFullLog`, `FullLogHeader` |
| `Kicker` | `SendKick`, `SendKickAsync`, `ValidateKick`, `KickDispatchState`, `ListKickLogs`, `ReadKickLog`, `SetKickObserver` |
| `Definitions` | `AddAgent`, `RemoveAgent`, `UpdateConfig`, `ReconcileAgents`, `SetModelOverride`, `SetBackendOverride`, `PinCLI`, `PinModel`, `UnpinCLI`, `UnpinModel`, `ClearModeOverrides`, `SyncModeFiles`, `RefreshInferenceRoutes` |
| `Fleet` | `BreakerState`, `EngageBreaker`, `ReleaseBreaker`, `SetACMMLevel`, `GetACMMLevel` (the fleet trust level), `RelaunchBobAgentsAwaitingKey`, `SharedDevUID` |
| `Credentials` | `SubmitLoginCode`, `CopilotToken`, `CopilotTokenSource`, `SetCopilotToken`, `ActivateCopilotToken`, `ReloadClaudeToken`, `ClaudeCredentialCandidatePaths` |
| `Resumer` | `ResumeHandle`, `SendResumeKick`, `SessionID`, `SessionMissing` |
| `Supervisor` | `GovernorMayStart`, `MarkStartupLaunchQueued`, `CheckAndRestartCrashedAgents`, `ConsentWedgedAgents`, `RefreshAgentTokens`, `RefreshAgentTokenFor`, `AgentCredentialRefreshable`, `AgentHasValidCredential`, `AgentCapabilities`, `EffectiveBackend`, `InvocationMetadata`, `RestartTelemetry`, `StartFailureState`, `ProviderErrorBackoffRemaining`, `PauseByCause`, `ArchiveAllKickLogs`, `CountAgentsWithModel`, `CrashOOMSuspected`, `BackendAuthAvailable`, `AgentAuthAvailable`, `SendGitHubAPIBudgetNudge`, `RecordAudit`, `TrajectoryAgents` |
| `Restorer` | `SeedPauseState`, `SeedRestartTelemetry`, `SeedTurnLoss`, `SeedLastKick`, `SeedKickHistory`, `RestoreBreaker` |
| `Background` | `StartAgentTokenRefresh`, `StartCredentialWatchdog`, `StartCopilotSessionRefresh`, `StartTranscriptActivityRefresh` |
| `Authorizer` | `AuthorizePROpen`, `AuthorizePushBranch`, `AuthorizeIssueOpen`, `AuthorizeMerge`, `AuthorizeReviewRequest` |

In short: `Lifecycle` starts and stops agents. `Observer` reads their state
and screen. `Kicker` sends them work. `Definitions` edits what they are.
`Fleet` acts on all of them at once. `Credentials` handles logins.
`Resumer` picks a past session back up. `Supervisor` is the crash, OOM and
token-refresh loop, plus the telemetry and audit the host reads.
`Restorer` reloads saved state after a restart. `Background` starts the
long-running refresh loops. `Authorizer` says yes or no before an agent
opens a PR, pushes, opens an issue, merges, or asks for review.

You get one from `agent.AsRuntime(agent.NewManager(...))`. See
[`docs/MODULE.md`](docs/MODULE.md) for a full example.

### 2. The wire API

`crux serve` puts the same runtime behind HTTP+JSON under `/v1`, on a unix
socket by default. The contract is in [`api/api.go`](api/api.go) and
[`api/runtime.go`](api/runtime.go). [`api/wire.go`](api/wire.go) holds the
address forms. [`api/runtime.go`](api/runtime.go) also has
`api.RuntimeRoutes`, a table that maps every `crux.Runtime` method to its
route. The server itself is in [`serve/`](serve/).

Routes that mirror a CLI verb:

| Route | Verb | What it does |
|---|---|---|
| `/v1/health` | GET | Server is up. Agent count, uptime, hive callback state. |
| `/v1/agents` | GET | List agents (`crux ps`). |
| `/v1/agents` | POST | Add a definition and start it (`crux run`). |
| `/v1/agents/{name}` | GET | One agent's status. |
| `/v1/agents/{name}` | DELETE | Forget an agent's definition. |
| `/v1/agents/{name}/logs` | GET | Recent output. `?source=pane\|buffer\|full`, `?n=`, `?follow=1` streams. |
| `/v1/agents/{name}/kick` | POST | Send work (`crux kick`). |
| `/v1/agents/{name}/kick` | GET | State of the last async kick. |
| `/v1/agents/{name}/stop` | POST | Stop it (`crux stop`). |
| `/v1/events` | GET | Runtime events as a stream. |

Per-agent routes for the rest of the runtime:

| Route | Verb | What it does |
|---|---|---|
| `/v1/agents/{name}/start` | POST | Start a defined agent. |
| `/v1/agents/{name}/restart` | POST | Restart, with an optional bootstrap prompt. |
| `/v1/agents/{name}/pause` | POST | Pause, with a trigger, reason, actor and cause. |
| `/v1/agents/{name}/resume` | POST | Lift a pause. |
| `/v1/agents/{name}/restart-count` | DELETE | Reset the crash-loop counter. |
| `/v1/agents/{name}/snapshot` | GET | Full status snapshot. |
| `/v1/agents/{name}/kick/validate` | POST | Say why a kick would be refused, without sending one. |
| `/v1/agents/{name}/kicklogs` | GET | List archived kick logs. |
| `/v1/agents/{name}/kicklogs/{id}` | GET | Read one kick log. |
| `/v1/agents/{name}/definition` | PUT | Replace the agent's config. |
| `/v1/agents/{name}/overrides` | PUT | Set the model or backend override. |
| `/v1/agents/{name}/pins/{cli\|model}` | PUT, DELETE | Pin or unpin the CLI version or model. |
| `/v1/agents/{name}/login-code` | POST | Type a device-flow login code. |
| `/v1/agents/{name}/session` | GET | Session id and resume handle. |
| `/v1/agents/{name}/session/kick` | POST | Kick a named past session. |
| `/v1/agents/{name}/supervision` | GET | Supervisor reads: capabilities, backend, restart and failure state, auth. |
| `/v1/agents/{name}/tokens/refresh` | POST | Re-mint this agent's GitHub token. |
| `/v1/agents/{name}/nudge` | POST | Send a nudge that does not count as a kick. |
| `/v1/agents/{name}/seed` | POST | Reload saved pause, restart, kick and turn-loss state. |
| `/v1/agents/{name}/watchdog` | GET | Watchdog observation and last production. |
| `/v1/agents/{name}/watchdog/conditions` | PUT | Set the agent's watchdog conditions. |

Fleet-wide routes:

| Route | Verb | What it does |
|---|---|---|
| `/v1/snapshots` | GET | Snapshot of every agent. |
| `/v1/definitions` | POST | Add a definition without starting it. |
| `/v1/definitions/reconcile` | POST | Add any definitions the runtime does not know yet. |
| `/v1/fleet` | GET | Trust level, shared uid, consent-wedged agents, agent counts. |
| `/v1/fleet/breaker` | GET, PUT | Read, or restore, the fleet breaker. |
| `/v1/fleet/breaker/engage` | POST | Pause every running agent. |
| `/v1/fleet/breaker/release` | POST | Resume the agents the breaker paused. |
| `/v1/fleet/acmm` | PUT | Set the fleet trust level. |
| `/v1/fleet/modes/sync` | POST | Rewrite agent mode files for a trust level. |
| `/v1/fleet/modes/clear` | POST | Drop mode overrides for named agents. |
| `/v1/fleet/inference/refresh` | POST | Re-resolve routes for a gateway backend. |
| `/v1/fleet/relaunch-bob` | POST | Relaunch Bob agents parked on a missing key. |
| `/v1/fleet/startup-queued` | POST | Record the host's staggered boot queue. |
| `/v1/fleet/restart-crashed` | POST | Relaunch crashed agents. |
| `/v1/fleet/tokens/refresh` | POST | Re-mint every agent's GitHub token. |
| `/v1/fleet/kicklogs/archive` | POST | Rotate every agent's kick log. |
| `/v1/credentials/copilot` | GET, PUT | Read or set the shared Copilot token. |
| `/v1/credentials/claude` | GET | Where crux looks for Claude credentials. |
| `/v1/credentials/claude/reload` | POST | Re-read the Claude credential store. |
| `/v1/backends/{backend}/auth` | GET | Whether a backend has credentials. |
| `/v1/audit` | POST | Append a host action to the audit trail. |
| `/v1/trajectory` | GET | Running agents with intent and transcript. |
| `/v1/authorize` | POST | Ask before a PR open, push, issue open, merge or review request. |
| `/v1/watchdog/agents` | GET | Agent names the watchdog should observe. |

`api.Client` in [`api/client.go`](api/client.go) wraps the CLI-shaped
routes: `Health`, `List`, `Get`, `Run`, `Logs`, `FollowLogs`, `Kick`,
`Stop`, `Events`, `WaitReady`, `Status` and `Address`. `Do` reaches any
other route. [`api/client`](api/client) goes one step further:
`client.Runtime` is a full `crux.Runtime` over the API, and is what
`runtime.New` returns when `CRUX_MODE=sidecar`.

### 3. The hive callback, what crux asks the host for

This layer runs the other way. Crux never holds a long-lived GitHub key, a
canary list, or any other secret the host owns. It asks the host for each
one when it needs it. The contract is in
[`api/callback/callback.go`](api/callback/callback.go). The host serves
it; crux calls it with `crux serve --hive-callback`. The core set is
`callback.Capabilities`. The rest are optional halves the host may add.
Every call fails closed: if the host is down or says no, crux treats it as
a refusal.

| Method | What the host provides |
|---|---|
| `MintToken` | A short-lived, scoped GitHub token. |
| `MintAgentToken` | A token for one agent at its trust tier. |
| `BobCredential` | The IBM Bob API key and where it came from. |
| `LinearCredential` | The Linear credential to inject. |
| `CreatePR` | Opens a pull request as the host's GitHub App. |
| `RecordREST` | Records one relayed GitHub REST response for accounting. |
| `RateLimit` | The shared GitHub rate-limit bucket snapshot. |
| `RecordUsage` | Records inference token usage. |
| `ScanCanary` | Scans a GitHub write body for planted canaries. |
| `ScanText` | Scans tool payload text. |
| `ReportCondition` | Takes a runtime condition, raised or cleared. |
| `Policy` | One snapshot of the host's policy settings. |
| `RepoAutoMergeEnabled` | Whether one repository allows auto-merge. |
| `SetInferenceRoute` | Tells the host's inference proxy which upstream to use for one agent. |
| `ClearInferenceRoute` | Removes that route. |
| `BeginEffect` | Admits or denies one external write before crux performs it. |
| `EndEffect` | Records how that write turned out. |
| `Configured` | Says whether the host has a given capability at all. |

### Packages shipped with it

- `agent`: the manager. tmux sessions, launch, restarts, kicks. It knows
  nine engines by name in `agent/manager_launch.go`: claude, copilot,
  gemini, agy, pi, goose, bob, codex and omp. `config.CLIBackends` lists
  fifteen; the other six (aider, opencode, kilo, muse, openhands,
  omnigent) launch as a bare binary.
- `proxy`: the GitHub and inference proxy. Policy enforcement at the tool
  boundary: every agent write to GitHub and every model call goes through
  it, with budgets and deny rules.
- `sandbox`: the opt-in per-task rootless Podman container, with no
  credentials inside.
- `kubejob`: the same sandbox as a Kubernetes Job.
- `toolapprove`: the allow list of what an agent may call. It sorts tool
  calls into read-only, GitHub write, PR open and PR merge, and scans
  their text.
- `skillreg`: a local registry of named, versioned agent skills.
- `inference`: works out where an agent's model calls go and how they log
  in.
- `openrouter`: the OpenRouter scan-to-fund flow that gets a scoped key.
- `watsonx`: swaps an IBM Cloud API key for a short-lived IAM token.
- `watchdog`: the per-agent liveness and readiness loop that heals stalls.
- `trajectory`: a second-model check that an agent is still on task.
- `logscrub`: a log handler that masks tokens and other secrets.
- `pushbroker`: the trusted step that pushes a sandboxed agent's work with
  credentials the sandbox never sees.
- `gitidentity`: the git identity each agent commits as.
- `agentmode`: the ladder of GitHub permission tiers, one per trust level.
- `agentparse`: parsers for the tables and lists agents print.
- `agentsmd`: reads a repository's `AGENTS.md` and its inline skills.
- `hivecap`: the runtime-side adapters for the hive callback.
- `serve`, `cli`, `cmd`: the HTTP server, the `crux` command, and the binary.

</details>

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

CI here applies the same gates Hive applies to this code: build, vet,
`go test -short -race`, Hive's per-package coverage floors
([`.github/scripts/coverage-floors.sh`](.github/scripts/coverage-floors.sh)),
golangci-lint, govulncheck, gosec (advisory, as in Hive), action-pin
resolution, a `crux serve` smoke and a goreleaser snapshot. The floors are
copied from Hive's `v2-tests.yml`; change them there first.

So: file issues and code changes in
[hivecommons/hive](https://github.com/hivecommons/hive). Releases are cut
by tagging Hive `crux/vX.Y.Z`. How the publish works is in
[`src/docs/crux-publish.md`](https://github.com/hivecommons/hive/blob/v5/src/docs/crux-publish.md).

## Licence

Apache-2.0. Open source under Hive Commons.
