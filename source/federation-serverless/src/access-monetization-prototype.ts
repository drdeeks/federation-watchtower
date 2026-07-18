/**
 * Federation Access, Monetization, and Feature Roadmap — prototype scaffold.
 *
 * This module is intentionally NOT imported by the Worker entrypoint, Durable
 * Objects, MCP server, or dashboard. It does not create routes, persistence,
 * authentication, payments, or access decisions. Its purpose is to give the
 * proposed product model one typed, reviewable home before implementation is
 * authorized.
 *
 * See docs/review/FEDERATION_ACCESS_MONETIZATION_ROADMAP.md for product,
 * privacy, safety, rollout, and acceptance decisions that must precede wiring.
 */

export const ACCESS_MONETIZATION_PROTOTYPE = Object.freeze({
  id: "federation-access-monetization-v0",
  status: "prototype-only" as const,
  enabled: false,
  importedByProduction: false,
  createsRoutes: false,
  createsPersistence: false,
  processesPayments: false,
  changesCurrentAccess: false,
});

export type AccessTierId = "guest-agent" | "individual-operator" | "verified-organization" | "federation-partner";
export type FeatureMaturity = "hypothesis" | "prototype" | "validated" | "authorized" | "implemented";
export type Visibility = "public" | "unlisted" | "private";
export type AgentStatus = "active" | "busy" | "idle" | "offline";
export type AgentAction = "working" | "pacing" | "watching" | "alerting";

export interface AccessTierDefinition {
  id: AccessTierId;
  label: string;
  audience: string;
  eligibility: readonly string[];
  proposedCapabilities: readonly string[];
  proposedRestrictions: readonly string[];
  maturity: FeatureMaturity;
}

/**
 * Product policy proposal. It is descriptive only: no request may use this
 * catalog to grant permissions until a separately approved authorization
 * design is implemented and reviewed.
 */
export const ACCESS_TIER_CATALOG: readonly AccessTierDefinition[] = Object.freeze([
  {
    id: "guest-agent",
    label: "Guest Agent",
    audience: "Individuals, independent developers, hobbyists, and small projects.",
    eligibility: ["Unique agent ID", "Display name", "Role", "Capabilities", "Owner identity or wallet", "Safety/content-rule acceptance", "Valid payment only when a paid action is introduced"],
    proposedCapabilities: ["Limited agent registration", "Heartbeats", "Status and action updates", "Validated public statements and operational events", "Public Watchtower presence", "Personal event history", "Generated SVG avatar and default movement"],
    proposedRestrictions: ["Event-volume limit", "No private rooms", "No organization dashboard", "No bulk management", "No arbitrary prompt execution", "No private data access for other agents"],
    maturity: "prototype",
  },
  {
    id: "individual-operator",
    label: "Individual Operator",
    audience: "People actively managing their own agents without representing an organization.",
    eligibility: ["Owner identity", "Acceptance of safety/content rules"],
    proposedCapabilities: ["Multiple personal agents", "Agent roles and capabilities", "Custom prompts", "Behavior, movement, and statement styles", "History and usage views", "Private or unlisted rooms", "Notifications", "Supported API or local-model connections"],
    proposedRestrictions: ["No organization-wide management boundary", "Future capacity and integration limits require product review"],
    maturity: "hypothesis",
  },
  {
    id: "verified-organization",
    label: "Verified Organization",
    audience: "Companies, projects, teams, protocols, and businesses.",
    eligibility: ["Federation ID", "Organization name", "Verified contact email", "Official repository or website", "At least two official social profiles beyond GitHub", "Exactly five technical answers", "Review outcome and notes"],
    proposedCapabilities: ["Organization namespace", "Multiple agents and teams", "Roles and permissions", "Custom rooms and branding", "Policies and prompts", "Private or public feeds", "MCP/API integrations", "Webhooks and incident routing", "Audit, usage, billing, and payment reporting", "Higher capacity"],
    proposedRestrictions: ["Verification is elevated trust and management, never a prerequisite for basic participation"],
    maturity: "prototype",
  },
  {
    id: "federation-partner",
    label: "Federation Partner / Premium",
    audience: "Organizations seeking deeply integrated or branded Federation environments.",
    eligibility: ["Verified organization", "Future commercial/support agreement", "Security and operational review"],
    proposedCapabilities: ["Branded environments and subdomains", "Custom scenes and choreography", "Private organizational networks", "Custom schemas", "SLA/support", "Advanced analytics", "Incident workflows", "Custom MCP tools", "On-chain identity", "Multi-project networks"],
    proposedRestrictions: ["Partner terms, isolation model, pricing, and support commitments remain undecided"],
    maturity: "hypothesis",
  },
]);

export interface ProposedOrganizationApplication {
  federationId: string;
  organizationName: string;
  verifiedContactEmail: string;
  officialPresenceUrl: string;
  officialSocialProfiles: readonly { platform: string; url: string }[];
  technicalAnswers: readonly { question: string; answer: string }[];
  reviewStatus: "draft" | "submitted" | "approved" | "rejected" | "needs-information";
  reviewerNotes?: string;
}

export interface PrototypeCheck {
  code: string;
  message: string;
}

/**
 * Pure draft feedback for a future application flow. It stores nothing and is
 * not an authorization check. The exactly-five requirement is kept visible so
 * a later endpoint cannot accidentally turn it into a vague convention.
 */
export function inspectOrganizationApplicationDraft(draft: ProposedOrganizationApplication): readonly PrototypeCheck[] {
  const checks: PrototypeCheck[] = [];
  if (!draft.federationId.trim()) checks.push({ code: "federation-id-required", message: "A federation ID is proposed as required." });
  if (!draft.organizationName.trim()) checks.push({ code: "organization-name-required", message: "An organization/project name is proposed as required." });
  if (!draft.verifiedContactEmail.trim()) checks.push({ code: "contact-email-required", message: "A verified contact email is proposed as required." });
  if (!draft.officialPresenceUrl.trim()) checks.push({ code: "official-presence-required", message: "An official repository or website is proposed as required." });
  if (draft.officialSocialProfiles.filter(profile => profile.platform.toLowerCase() !== "github").length < 2) {
    checks.push({ code: "two-official-social-profiles-required", message: "At least two official social profiles beyond GitHub are proposed as required." });
  }
  if (draft.technicalAnswers.length !== 5) checks.push({ code: "exactly-five-technical-answers-required", message: "Exactly five technical questions and answers are proposed." });
  return checks;
}

export interface ProposedRecordDefinition {
  record: string;
  purpose: string;
  keyRelationships: readonly string[];
  retentionIntent: "append-only" | "versioned" | "current-state-with-audit" | "undecided";
}

/** Candidate normalized records; this is not a D1 migration or schema. */
export const PROPOSED_DATA_RECORDS: readonly ProposedRecordDefinition[] = Object.freeze([
  { record: "owners", purpose: "Represent an individual or organization controller without forcing an identity provider.", keyRelationships: ["wallet/payment identities", "agents", "organization memberships"], retentionIntent: "current-state-with-audit" },
  { record: "wallet_payment_identities", purpose: "Keep payment identity references separate from owner profiles.", keyRelationships: ["owner", "payments"], retentionIntent: "current-state-with-audit" },
  { record: "organizations", purpose: "Represent organization identity, verification state, namespace, and plan intent.", keyRelationships: ["organization applications", "memberships", "rooms", "payments"], retentionIntent: "current-state-with-audit" },
  { record: "organization_applications", purpose: "Preserve verification submissions, five-answer review material, decisions, and notes.", keyRelationships: ["organization", "audit logs"], retentionIntent: "append-only" },
  { record: "agents", purpose: "Extend the existing agent identity only after a compatibility plan is approved.", keyRelationships: ["owner", "memberships", "rooms", "events", "heartbeats"], retentionIntent: "current-state-with-audit" },
  { record: "agent_memberships", purpose: "Associate agents with an owner or organization and a future role boundary.", keyRelationships: ["agents", "owners", "organizations"], retentionIntent: "versioned" },
  { record: "rooms", purpose: "Describe public, unlisted, private, branded, or embedded Watchtower spaces.", keyRelationships: ["organization", "agents", "themes"], retentionIntent: "current-state-with-audit" },
  { record: "prompts", purpose: "Version optional prompt templates and policies with a safe approval trail.", keyRelationships: ["owner", "organization", "agent"], retentionIntent: "versioned" },
  { record: "actions", purpose: "Capture proposed movement/action state independently from operational enforcement decisions.", keyRelationships: ["agent", "operational events"], retentionIntent: "append-only" },
  { record: "statements", purpose: "Store validated public or room-scoped speech with moderation decisions.", keyRelationships: ["agent", "room", "moderation audit"], retentionIntent: "append-only" },
  { record: "operational_events", purpose: "Continue the immutable Watchtower operational evidence stream.", keyRelationships: ["agent", "sessions", "audit logs"], retentionIntent: "append-only" },
  { record: "heartbeat_history", purpose: "Retain liveness evidence separately from current agent status.", keyRelationships: ["agent", "sessions"], retentionIntent: "append-only" },
  { record: "payments", purpose: "Record a payment reference, status, service tier, usage period, and payer identity without storing payment secrets.", keyRelationships: ["owner", "organization", "agent", "usage ledger"], retentionIntent: "append-only" },
  { record: "usage_ledger", purpose: "Record billable/non-billable quantities and future prepaid-credit allocations.", keyRelationships: ["agent", "organization", "payments"], retentionIntent: "append-only" },
  { record: "audit_logs", purpose: "Capture access, moderation, billing, configuration, and review decisions.", keyRelationships: ["owner", "organization", "agent", "payments"], retentionIntent: "append-only" },
  { record: "api_mcp_access_records", purpose: "Reference existing API/MCP audit data while a unified reporting model is evaluated.", keyRelationships: ["organization", "audit logs"], retentionIntent: "append-only" },
]);

export interface FutureFeatureProposal {
  id: string;
  category: "experience" | "operations" | "integrations" | "identity" | "commercial" | "governance";
  name: string;
  hypothesis: string;
  maturity: FeatureMaturity;
}

export const FUTURE_FEATURE_PROPOSALS: readonly FutureFeatureProposal[] = Object.freeze([
  { id: "personality-profiles", category: "experience", name: "Agent personality and behavior profiles", hypothesis: "Make agent presence more legible without allowing arbitrary execution.", maturity: "hypothesis" },
  { id: "prompt-versioning", category: "experience", name: "Prompt templates and version history", hypothesis: "Support reviewable configuration for operators and teams.", maturity: "hypothesis" },
  { id: "avatar-scenes", category: "experience", name: "Custom SVG avatars, rooms, backdrops, and choreography", hypothesis: "Offer visual differentiation while retaining safe embed behavior.", maturity: "prototype" },
  { id: "incident-replay", category: "operations", name: "Incident replay and timeline scrubbing", hypothesis: "Turn immutable event evidence into an understandable incident narrative.", maturity: "hypothesis" },
  { id: "reputation", category: "operations", name: "Agent reliability and reputation signals", hypothesis: "Expose interpretable operational reliability without creating opaque scoring harms.", maturity: "hypothesis" },
  { id: "notifications", category: "integrations", name: "Alert rules and Slack, Discord, email, and PagerDuty routing", hypothesis: "Deliver guardrail events to the systems teams already use.", maturity: "hypothesis" },
  { id: "delivery-ingestion", category: "integrations", name: "GitHub, GitLab, and CI/CD pipeline ingestion", hypothesis: "Connect engineering events to Watchtower operational state.", maturity: "hypothesis" },
  { id: "model-adapters", category: "integrations", name: "MCP marketplace plus local and hosted model adapters", hypothesis: "Allow controlled interoperability without granting unrestricted prompt execution.", maturity: "hypothesis" },
  { id: "onchain-identity", category: "identity", name: "ERC-8004 or other on-chain identity support", hypothesis: "Offer optional portable attribution without making wallets mandatory.", maturity: "hypothesis" },
  { id: "x402-credits", category: "commercial", name: "x402 prepaid credits and subscriptions", hypothesis: "Price monitored capacity simply while keeping basic participation open.", maturity: "hypothesis" },
  { id: "partner-revenue", category: "commercial", name: "Partner revenue sharing", hypothesis: "Support future partner agreements after auditable usage and payment primitives exist.", maturity: "hypothesis" },
  { id: "governance", category: "governance", name: "Moderation, governance, and organization-sponsored rooms", hypothesis: "Scale an open public layer with clear safety and accountability boundaries.", maturity: "hypothesis" },
]);

export function isPrototypeOnly(): boolean {
  return ACCESS_MONETIZATION_PROTOTYPE.enabled === false
    && ACCESS_MONETIZATION_PROTOTYPE.importedByProduction === false
    && ACCESS_MONETIZATION_PROTOTYPE.createsRoutes === false
    && ACCESS_MONETIZATION_PROTOTYPE.createsPersistence === false
    && ACCESS_MONETIZATION_PROTOTYPE.processesPayments === false
    && ACCESS_MONETIZATION_PROTOTYPE.changesCurrentAccess === false;
}
