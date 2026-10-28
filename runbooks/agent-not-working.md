# Runbook: `crux serve` is unhealthy or an agent is not doing work

Use this when `GET /v1/health` fails or reports a problem, `crux ps` shows an
agent that is not making progress, or a harness reports
`hive_callback_unavailable`. For a bad release, use `release-rollback.md`.

Clients below reach the server with `--server ADDR` or `CRUX_SERVER`
(`unix:///path`, a socket path, or `host:port`). Add `--token`/`CRUX_TOKEN`
for a TCP listener.

## 1. Is the server up?

```sh
crux --server "$CRUX_SERVER" ps
curl --unix-socket "$CRUX_SOCKET" http://localhost/v1/health
```

`/v1/health` returns `version`, `agents`, `started_at` and `uptime_seconds`.

| Observation | Meaning | Action |
| --- | --- | --- |
| Connection refused / no socket | `crux serve` is not running | Restart it; check its stderr for a config load error (`crux: ...`) |
| `uptime_seconds` keeps resetting | The supervisor is restart-looping the server | Read the server's stderr; fix the config it reports; do not just keep restarting |
| `agents` lower than expected | The `--config` file defines fewer agents than you think | Check the file and `CRUX_SOCKET`: you may be talking to a different server |
| 401 / 403 | Missing or wrong bearer token | Pass the token the server was started with |

## 2. Is the hive callback reachable?

Only when the server was started with `--hive-callback` (or the callback
socket env var). `/v1/health` then carries a `hive_callback` object.

- `reachable: false`: calls that need hive **fail closed** during the outage;
  `failed_calls` counts them. `last_error` and `since` say what and when.
- Fix the hive side or the socket path/token, not the agents. Once hive
  answers, `reachable` returns to true and `last_success` moves.

## 3. Why is one agent not working?

```sh
crux --server "$CRUX_SERVER" ps
crux --server "$CRUX_SERVER" logs NAME
```

The watchdog classifies each agent pane. `crux ps` does not print the pane
class; it shows state, paused, restart count, busy condition and start
failure class. Read the class from the server log line
`watchdog: liveness transition` (`agent`, `from`, `to`, `reason`) or from the
published watchdog condition events. `unknown` is "cannot tell yet": it
never restarts and never reports healthy.

| Pane class | Meaning | Action |
| --- | --- | --- |
| `ready` | CLI at its ready prompt | Agent is fine; check whether it is paused or busy |
| `auth-required` | Login or credential screen | Re-authenticate the backend. Restarting does not help and is deliberately not done |
| `shell-prompt` | The CLI exited; the pane is a bare shell | Restart the agent; if it repeats, read `logs` for the crash |
| `stuck-overlay` | A modal (onboarding, update prompt) sat unanswered | Dismiss it in the pane, or restart |
| `no-output` | Pane silent past the threshold | Restart; if it repeats, suspect the backend or network |
| `no-session` | The tmux session is gone | Restart the agent |

`watchdog.mode` is `off`, `observe` or `heal`. Only `heal` restarts or
pauses; `observe` raises conditions and alerts only. If a restart loop is
making things worse, set `HIVE_WATCHDOG_PAUSE=1` (also `true`, `yes`, `on`)
on the deployment: heal drops to observe at the next config resolve, with no
redeploy. It can only reduce authority and never turns the watchdog on.

## 4. Stop an agent that is doing harm

```sh
crux --server "$CRUX_SERVER" stop NAME
```

Do not clear a pause or breaker you did not set: a pause that is still
attributed to the fleet breaker is released only by releasing the breaker.

## 5. Verify recovery

- `/v1/health` answers and `uptime_seconds` grows across two checks.
- `crux ps` shows the agent running and not paused, and the latest
  `watchdog: liveness transition` log line for it has `to=ready`.
- With a hive callback, `hive_callback.reachable` is true.

If users were affected, write the postmortem with
`runbooks/postmortem-template.md`.
