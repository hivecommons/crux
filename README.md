# Crux

**A fully governed AI agent platform.** Trust, productivity, non-rogue.

Crux is the agent runtime inside [Hive](https://github.com/hivecommons/hive), split out as a reusable open-source component. It runs AI agents from definitions and makes four promises about every one of them:

| Promise | What it means | How Crux keeps it |
|---|---|---|
| **Productive** | Agents ship real work on real repos, continuously, without a human babysitting each run. | Short-lived agents with a clean context, external context injected per run, stall and crash-loop recovery, kicks and nudges, seven engines behind one interface. |
| **Non-rogue** | An agent cannot act outside the scope it was given, even if the model wants to. | Limits enforced in code at the tool boundary: a MITM proxy in front of every write, tool approval, per-agent identity and credentials, container and Kubernetes isolation. |
| **Tamper-evident** | If prompt injection, a hostile repo or a bad dependency does bend an agent, it leaves a trace and hits a boundary that can refuse it. Nothing happens off the record. | No agent self-report is trusted. Every write passes a boundary that logs it and can refuse it; policy lives outside the model; sandboxed execution; scrubbed logs; signed, scoped credentials that expire. |
| **Governed** | A human owns the record of what happened and why, and can stop it. | A gate before anything lands, trust levels that decide how much runs unattended, an audit log and telemetry via [pluk](https://github.com/hivecommons/pluk), and evidence a reviewer can check. |

These promises are backed by code, not by a prompt. Hive's [security model](https://github.com/hivecommons/hive/blob/v5/src/docs/security-model.md) is the inventory: 38 controls that protect maintainers from the agents they run, each one tied to a file path, config key or ADR, with a section on [what is not done yet](https://github.com/hivecommons/hive/blob/v5/src/docs/security-model.md#11-what-hive-does-not-do-yet) and [how to audit a running hive](https://github.com/hivecommons/hive/blob/v5/src/docs/security-model.md#12-how-to-audit-a-running-hive). The agent-runtime controls in that list are the ones that move into Crux.

Hive is the first consumer. It has run this runtime in the open on 27 hives and their production repositories (October 2026): 4,349 agent writes to GitHub in one five-day window, every one through the proxy, 7 refused and on record. Anything that needs a governed agent can be the next consumer.

## Why "Crux"

It is the crux of the matter. Models are good enough now; the failure mode that matters is an agent doing the wrong thing with the right skills. Crux is the point everything turns on: the layer where trust, productivity and non-rogue behaviour are decided in code, not in a prompt.

## Status

The code is being carved out of the hive repo in stages. The RFC that defined the stages, [hivecommons/hive#13536](https://github.com/hivecommons/hive/issues/13536), is closed; progress on later stages is recorded in the design record: [`src/docs/design/crux.md`](https://github.com/hivecommons/hive/blob/v5/src/docs/design/crux.md) in hive.

1. **In-repo boundary inside hive** (shipped, October 2026): `crux.Runtime` interface, inbound and outbound architecture ratchet tests, tmux funnel, agent-runtime config struct, CI path filters.
2. **Nested Go module** in hive with its own tags and a `crux` binary: `run`, `ps`, `logs`, `kick`, `stop`. Not started: blocked on cutting the remaining package edges listed in the design record.
3. **`crux serve`**: an API, auth and quotas; the code moves here and Hive becomes a client. Multi-tenancy when there is a second tenant.

## What is in scope

- Run an agent from a definition: engine, model, prompt, tools, limits.
- Lifecycle: start, observe, nudge, stall and crash-loop recovery, stop.
- Engines: Claude, Copilot, Gemini, Goose, Codex, Aider, Bob; any OpenAI-compatible model through the gateway.
- Policy enforcement at the tool boundary: MITM proxy, tool approval.
- Isolation: container sandbox, Kubernetes job.
- Identity, credentials, entitlements.
- Telemetry and audit via pluk.

Staying in Hive: governor, GitHub and forge integration, review swarm, evidence, dashboard, hub.

## What else could run on Crux

Any system that wants agents to do work without trusting the agent: an enterprise agent service, a policy proxy in front of a harness you did not write, a model gateway with entitlements, ops and SRE runbooks, documentation upkeep, security response, research pipelines, a local runner on a laptop.

## License

Apache-2.0. Open source under Hive Commons; anyone may productize on top.
