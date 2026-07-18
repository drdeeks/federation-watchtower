#!/usr/bin/env python3
"""Small stdlib-only Loop Enforcer adapter for Federation Watchtower.

It obtains, validates, and records a renewable work lease before a protected
step. A nonzero exit from ``lease``, ``validate``, ``gate``, or ``authorize``
means the caller must not start the next side effect. The adapter deliberately
does not execute tools or shell commands.
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
from typing import Any


class WatchtowerClient:
    def __init__(self, gateway: str, secret: str, producer: str) -> None:
        self.gateway = gateway.rstrip("/")
        self.secret = secret.encode()
        self.producer = producer

    def request(self, method: str, path: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
        body = b"" if payload is None else json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
        timestamp = str(int(time.time()))
        signature = hmac.new(self.secret, timestamp.encode() + b"." + body, hashlib.sha256).hexdigest()
        headers = {
            "X-Watchtower-Timestamp": timestamp,
            "X-Watchtower-Signature": f"sha256={signature}",
            "X-Watchtower-Producer": self.producer,
        }
        if payload is not None:
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(f"{self.gateway}{path}", data=body if payload is not None else None, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                return json.loads(response.read().decode())
        except urllib.error.HTTPError as error:
            detail = error.read(1024).decode(errors="replace").replace("\n", " ")
            raise RuntimeError(f"Watchtower returned HTTP {error.code}: {detail}") from error
        except urllib.error.URLError as error:
            raise RuntimeError(f"Watchtower is unreachable: {error.reason}") from error


def print_result(result: dict[str, Any]) -> None:
    print(json.dumps(result, sort_keys=True))


def command_lease(client: WatchtowerClient, args: argparse.Namespace) -> int:
    result = client.request("POST", f"/api/v1/projects/{args.project}/leases", {
        "projectId": args.project, "agentId": args.agent, "runId": args.run,
        "ttlSeconds": args.ttl, "scopes": args.scope,
    })
    print_result(result)
    return 0 if result.get("status") == "active" else 3


def command_validate(client: WatchtowerClient, args: argparse.Namespace) -> int:
    result = client.request("POST", f"/api/v1/projects/{args.project}/leases/{args.lease}/validate", {"agentId": args.agent})
    print_result(result)
    return 0 if result.get("status") == "active" else 3


def command_gate(client: WatchtowerClient, args: argparse.Namespace) -> int:
    try:
        metadata = json.loads(args.metadata)
    except json.JSONDecodeError as error:
        raise RuntimeError("--metadata must be a JSON object") from error
    if not isinstance(metadata, dict):
        raise RuntimeError("--metadata must be a JSON object")
    result = client.request("POST", f"/api/v1/projects/{args.project}/validation-gates", {
        "projectId": args.project, "agentId": args.agent, "runId": args.run,
        "leaseId": args.lease, "gateId": args.gate_id,
        "requestId": args.request_id or f"gate-{uuid.uuid4()}",
        "passed": args.passed, "statement": args.statement, "metadata": metadata,
    })
    print_result(result)
    return 0 if result.get("allowed") is True else 3


def command_authorize(client: WatchtowerClient, args: argparse.Namespace) -> int:
    result = client.request("POST", f"/api/v1/projects/{args.project}/tools/authorize", {
        "projectId": args.project, "agentId": args.agent, "leaseId": args.lease,
        "toolName": args.tool, "action": args.action,
        "requestId": args.request_id or f"tool-{uuid.uuid4()}", "inputDigest": args.input_digest.lower(),
    })
    print_result(result)
    return 0 if result.get("status") == "authorized" else 3


def command_heartbeat(client: WatchtowerClient, args: argparse.Namespace) -> int:
    timestamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    event = {
        "schemaVersion": "2026-07-17", "eventId": f"evt-{uuid.uuid4()}",
        "idempotencyKey": f"heartbeat-{args.agent}-{int(time.time())}",
        "projectId": args.project, "agentId": args.agent, "eventType": "heartbeat",
        "severity": "info", "occurredAt": timestamp,
        "statement": "Watchtower heartbeat received.",
        "metadata": {"expectedHeartbeatSeconds": args.expected_heartbeat_seconds},
    }
    print_result(client.request("POST", "/api/v1/events", event))
    return 0


def command_event(client: WatchtowerClient, args: argparse.Namespace) -> int:
    try:
        metadata = json.loads(args.metadata)
    except json.JSONDecodeError as error:
        raise RuntimeError("--metadata must be a JSON object") from error
    if not isinstance(metadata, dict):
        raise RuntimeError("--metadata must be a JSON object")
    event = {
        "schemaVersion": "2026-07-17", "eventId": args.event_id or f"evt-{uuid.uuid4()}",
        "idempotencyKey": args.idempotency_key or f"{args.event_type}-{uuid.uuid4()}",
        "projectId": args.project, "agentId": args.agent, "eventType": args.event_type,
        "severity": args.severity,
        "occurredAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "statement": args.statement, "metadata": metadata,
    }
    for source, target in ((args.run, "runId"), (args.parent_run, "parentRunId"), (args.chain_key, "chainKey")):
        if source:
            event[target] = source
    print_result(client.request("POST", "/api/v1/events", event))
    return 0


def command_commands(client: WatchtowerClient, args: argparse.Namespace) -> int:
    print_result(client.request("GET", f"/api/v1/projects/{args.project}/agents/{args.agent}/commands"))
    return 0


def command_ack(client: WatchtowerClient, args: argparse.Namespace) -> int:
    payload = {"commandId": args.command, "agentId": args.agent, "outcome": args.outcome}
    if args.note:
        payload["note"] = args.note
    print_result(client.request("POST", f"/api/v1/projects/{args.project}/commands/acknowledge", payload))
    return 0


def parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Federation Watchtower cooperative Loop Enforcer adapter")
    parser.add_argument("--gateway", default=os.getenv("FEDERATION_GATEWAY", "https://fapi.drdeeks.xyz"))
    parser.add_argument("--secret", default=os.getenv("WATCHTOWER_INGESTION_SECRET"), help="Defaults to WATCHTOWER_INGESTION_SECRET")
    parser.add_argument("--producer", default=os.getenv("WATCHTOWER_PRODUCER"), help="Defaults to the --agent value")
    parser.add_argument("--project", required=True)
    parser.add_argument("--agent", required=True)
    commands = parser.add_subparsers(dest="command", required=True)

    lease = commands.add_parser("lease", help="Acquire or renew a lease before a protected step")
    lease.add_argument("--run", required=True)
    lease.add_argument("--ttl", type=int, default=120)
    lease.add_argument("--scope", action="append", default=[])
    lease.set_defaults(handler=command_lease)

    validate = commands.add_parser("validate", help="Check a lease immediately before the next side effect")
    validate.add_argument("--lease", required=True)
    validate.set_defaults(handler=command_validate)

    gate = commands.add_parser("gate", help="Record a pass/fail validation gate before a controlled step")
    gate.add_argument("--run", required=True)
    gate.add_argument("--lease", required=True)
    gate.add_argument("--gate-id", required=True)
    gate.add_argument("--passed", action="store_true", help="Mark the validation gate as passed; omit to deny it")
    gate.add_argument("--statement", required=True)
    gate.add_argument("--metadata", default="{}")
    gate.add_argument("--request-id")
    gate.set_defaults(handler=command_gate)

    authorize = commands.add_parser("authorize", help="Require an active scoped lease before an external controlled action")
    authorize.add_argument("--lease", required=True)
    authorize.add_argument("--tool", required=True)
    authorize.add_argument("--action", required=True)
    authorize.add_argument("--input-digest", required=True, help="SHA-256 hex digest of the external tool input, never the raw input")
    authorize.add_argument("--request-id")
    authorize.set_defaults(handler=command_authorize)

    heartbeat = commands.add_parser("heartbeat", help="Record a heartbeat and arm the per-agent watchdog")
    heartbeat.add_argument("--expected-heartbeat-seconds", type=int, default=120)
    heartbeat.set_defaults(handler=command_heartbeat)

    event = commands.add_parser("event", help="Emit a signed run, validation, or policy event")
    event.add_argument("--type", dest="event_type", required=True)
    event.add_argument("--severity", choices=("info", "success", "warning", "error", "critical"), required=True)
    event.add_argument("--statement", required=True)
    event.add_argument("--run")
    event.add_argument("--parent-run")
    event.add_argument("--chain-key")
    event.add_argument("--metadata", default="{}")
    event.add_argument("--event-id")
    event.add_argument("--idempotency-key")
    event.set_defaults(handler=command_event)

    commands.add_parser("commands", help="Read still-blocking containment commands").set_defaults(handler=command_commands)
    acknowledge = commands.add_parser("ack", help="Record a containment outcome")
    acknowledge.add_argument("--command", required=True)
    acknowledge.add_argument("--outcome", choices=("contained", "rejected", "failed"), required=True)
    acknowledge.add_argument("--note")
    acknowledge.set_defaults(handler=command_ack)
    return parser


def main() -> int:
    args = parser().parse_args()
    if not args.secret:
        print("WATCHTOWER_INGESTION_SECRET is required", file=sys.stderr)
        return 2
    client = WatchtowerClient(args.gateway, args.secret, args.producer or args.agent)
    try:
        return args.handler(client, args)
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
