# Federation Watchtower agent contract

Production gateway: `https://fapi.drdeeks.xyz`; override with
`FEDERATION_GATEWAY`. The public TV wall at `watch.drdeeks.xyz` is static-only
and cannot accept API calls.

Use the included `watchtower_loop.py` adapter to make a runner cooperative:

```bash
export WATCHTOWER_INGESTION_SECRET='set-this-outside-the-repository'
python3 watchtower_loop.py --project autopilot --agent build-01 heartbeat
python3 watchtower_loop.py --project autopilot --agent build-01 lease --run run-42 --scope deployment
python3 watchtower_loop.py --project autopilot --agent build-01 event --type run.started --severity info --statement "Deployment gate opened." --run run-42 --metadata '{"chainDepth":1}'
# Store leaseId from JSON, then check immediately before each external side effect.
python3 watchtower_loop.py --project autopilot --agent build-01 validate --lease lease_example
```

The adapter exits `3` if the lease is not active. Treat that as a hard stop,
poll `commands`, contain the local runner, then acknowledge the command:

```bash
python3 watchtower_loop.py --project autopilot --agent build-01 commands
python3 watchtower_loop.py --project autopilot --agent build-01 ack --command cmd_example --outcome contained
```

Every request is HMAC-signed with `WATCHTOWER_INGESTION_SECRET` using
`<timestamp>.<exact body>`. See
`source/federation-serverless/agents-skill.md` for the complete event and API
contract.
