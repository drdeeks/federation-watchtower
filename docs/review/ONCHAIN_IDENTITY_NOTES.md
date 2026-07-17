# On-chain Identity Notes

## Current finding

The reviewed material contains two related but different concepts:

1. ERC-8004 agent identity / registration
   - Appears as a planned or stubbed directory/concept in enterprise organization references.
   - Mentions `erc8004/`, agent registrations, on-chain operations.
   - Not found as a complete working implementation in the extracted Federation packages.

2. ERC-8021 builder-code attribution
   - More concretely documented in Hemlock integration references.
   - Includes builder code, hex suffix, owner, framework detection, transaction suffix attribution.
   - Intended for Base/Base Sepolia verification.

## Recommended submission wording

Use:

> The system is designed for on-chain agent identity and includes builder-code attribution hooks. ERC-8004-style identity registration is part of the planned identity layer; the current demo focuses on verified federation membership, MCP access, and operational telemetry.

Avoid unless implemented:

> Fully implements ERC-8004.

## Possible implementation path

If time allows:

- Add `onchain_identity` object to verified federation and agent records.
- Add fields:
  - `chain`
  - `contract`
  - `tokenId` or `agentId`
  - `walletAddress`
  - `attestationUrl`
  - `builderCode`
  - `builderCodeHex`

- Add `GET /api/agents/:id/identity`.
- Add widget badge: `ONCHAIN VERIFIED`.
- Add README section explaining this as optional identity metadata.

