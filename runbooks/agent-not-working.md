# Agent not working

Use this when `crux serve` is down, `/v1/health` fails, the hive callback is
unreachable, or an agent is stuck.

## 1. Is the server up?

```sh
crux --version
curl --unix-socket "$CRUX_SERVER" http://crux/v1/health   # unix socket
curl -H "Authorization: Bearer $CRUX_TOKEN" "$CRUX_SERVER/v1/health"   # --listen address
```

`/v1/health` returns the version and the capabilities the hive has configured.
No answer means the server is not serving: check the process, then the socket
path (`crux serve --socket`, or `CRUX_SOCKET`) and that `CRUX_SERVER` points at
the same path. A server on `--listen` refuses to start without a token; set
`CRUX_TOKEN`.

## 2. Is the hive callback reachable?

`/v1/health` reports the hive callback state. If capabilities are missing,
the server was started without `--hive-callback`, or the hive did not answer.
Restart `crux serve` with the correct `--hive-callback` and confirm the
capabilities reappear in `/v1/health`.

## 3. Is the agent running?

```sh
crux ps                  # add --json for machine output
crux logs -n 100 <agent> # add -f with --server to follow
```

- Not listed: start it with `crux run <definition.yaml | agent>`, and check
  `CRUX_DEFS` points at the definitions directory.
- Listed but silent: read the logs, then send a nudge with
  `crux kick <agent> "<message>"`.
- Still stuck: `crux stop <agent>`, then `crux run` it again.

## 4. Escalate

If the server crashes on start or the same agent wedges twice, open an
incident from [incident-template.md](incident-template.md) and attach the
`crux --version` output, the `/v1/health` body and the last logs.
