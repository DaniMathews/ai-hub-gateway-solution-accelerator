# Agent Governance Toolkit (AGT) Integration Guide

This guide explains how to integrate the [Agent Governance Toolkit (AGT)](https://github.com/microsoft/agent-governance-toolkit) with Citadel Governance Hub to add **agent-level governance** on top of gateway-level controls.

- For Citadel deployment, see the [Quick Deployment Guide](./quick-deployment-guide.md).
- For Access Contract setup, see the [Access Contracts README](../bicep/infra/citadel-access-contracts/README.md).
- For the full platform architecture, see [Foundry Citadel Platform](https://aka.ms/foundry-citadel).

---

## Why Integrate AGT with Citadel?

Citadel Governance Hub governs the **infrastructure perimeter**: which models, tools, and agents can be accessed, at what rate, with what safety filters. This is essential, but insufficient for production agent deployments.

AGT governs the **agent behavior itself**: what actions the agent takes, whether it follows its policies, trust relationships between agents, and tamper-evident audit logging. These are complementary enforcement boundaries.

| Concern | Citadel (Gateway) | AGT (Agent Runtime) |
|---------|-------------------|---------------------|
| **Enforcement point** | APIM gateway (centralized) | Agent runtime library (local) |
| **Latency** | Network hop through gateway | Sub-millisecond in-process |
| **Policy granularity** | Rate limits, content filters, quotas | Per-action allow/deny, caller restrictions |
| **Identity** | Entra ID / subscription keys | Ed25519 / SPIFFE cryptographic identity |
| **Trust model** | Binary (authenticated or not) | Continuous scoring (0-1000) |

Together, they provide defense-in-depth: Citadel enforces coarse-grained rules at the perimeter, AGT enforces fine-grained rules at the agent.

---

## How AGT Maps to Citadel's 4 Layers

AGT is not confined to a single Citadel layer. It provides capabilities across the architecture:

### Layer 1: Governance Hub

Citadel Access Contracts can reference **AGT policy bundles** that are injected into agent environments at deployment time. The gateway enforces infrastructure policies (rate limits, content safety, JWT validation). AGT enforces agent-level policies (action restrictions, justification requirements, caller ACLs) inside the runtime.

**Policy precedence**: Gateway rules are evaluated first. AGT rules are evaluated second. Both must pass for an action to proceed.

### Layer 2: AI Control Plane

AGT exports governance telemetry (policy decisions, trust score changes, action interceptions) to Azure Event Hub and Application Insights via the `CitadelAuditExporter`. These events include **correlation IDs** linking AGT decisions to APIM request traces and Foundry execution traces, enabling unified observability dashboards.

### Layer 3: Agent Identity

Entra ID / Agent 365 remains the authoritative source for enterprise agent identity. AGT's Ed25519/SPIFFE identities handle runtime cryptographic credentials. The integration is **federation**: AGT trust scores surface as risk labels in telemetry, not as primary Entra metadata.

### Layer 4: Security Fabric

AGT's `data_classification` labels align with Purview sensitivity labels. AGT trust scores can surface as risk signals in Defender for AI through the telemetry pipeline.

---

## Integration Architecture

```
Agent Runtime (Spoke)                Citadel Hub                    Azure Monitor
┌──────────────────────┐            ┌──────────────────┐          ┌──────────────┐
│                      │            │                  │          │              │
│  Agent Application   │   LLM     │  APIM Gateway    │          │  App Insights│
│  ┌────────────────┐  │  request  │  ┌────────────┐  │          │              │
│  │ AGT Policy     ├──┼──────────►│  │ Rate Limit │──┼────►LLM  │  Event Hub   │
│  │ Engine         │  │           │  │ Content    │  │          │              │
│  │                │  │           │  │ JWT Auth   │  │          │  Log         │
│  │ allow/deny     │  │           │  └────────────┘  │          │  Analytics   │
│  └──────┬─────────┘  │           └──────────────────┘          └──────┬───────┘
│         │            │                                                │
│  ┌──────▼─────────┐  │           ┌──────────────────┐                │
│  │ Citadel Audit  ├──┼──────────►│  Event Hub /      │────────────────┘
│  │ Exporter       │  │  events   │  App Insights     │
│  └────────────────┘  │           └──────────────────┘
└──────────────────────┘
```

---

## Getting Started

### 1. Install AGT in your agent environment

```bash
pip install agent-governance-toolkit
```

### 2. Configure the Citadel audit exporter

Set the following environment variables in your agent spoke:

```bash
# Required for audit export
export CITADEL_EVENTHUB_CONNECTION_STRING="Endpoint=sb://..."
export CITADEL_APPINSIGHTS_CONNECTION_STRING="InstrumentationKey=..."

# Optional
export CITADEL_EVENTHUB_NAME="agt-governance-events"
export CITADEL_EXPORT_BATCH_SIZE="50"
```

### 3. Load a policy bundle

AGT policy bundles define agent-level governance rules. They can be loaded from a file, Azure Key Vault, or a URL:

```python
from agent_os.integrations.citadel import PolicyBundleResolver

resolver = PolicyBundleResolver()

# From a local file (development)
bundle = resolver.resolve_from_file("policies/agent-policy.yaml")

# From Key Vault (production, referenced by Access Contract)
bundle = resolver.resolve_from_keyvault(
    vault_url="https://myvault.vault.azure.net",
    secret_name="agt-policy-bundle-customer-support",
)
```

### 4. Export governance events

```python
from agent_os.exporters import CitadelAuditExporter
from agent_os.exporters.citadel_exporter import (
    GovernanceEvent,
    GovernanceEventType,
    Decision,
    CorrelationContext,
)

exporter = CitadelAuditExporter.from_env()

event = GovernanceEvent(
    event_type=GovernanceEventType.POLICY_DECISION,
    agent_id="customer-support-agent-01",
    action="query_customer_database",
    decision=Decision.ALLOW,
    policy_name="customer-support-policy",
    trust_score=800,
    correlation=CorrelationContext(
        apim_request_id="abc-123",  # From APIM response header
        agt_decision_id="def-456",
    ),
)

exporter.export_event(event)
await exporter.flush()
```

---

## Access Contract Integration

Citadel Access Contracts can reference an AGT policy bundle so that governance policies are automatically provisioned alongside infrastructure access. See the [sample access contract](https://github.com/microsoft/agent-governance-toolkit/tree/main/examples/citadel-governed-agent/sample-access-contract) in the AGT repository for an example.

---

## Coverage Boundaries

Understanding what each system handles avoids duplication:

| Concern | Handled By |
|---------|-----------|
| LLM model access control | Citadel Layer 1 (APIM products/subscriptions) |
| Token rate limiting | Citadel Layer 1 (APIM policies) |
| Content safety filtering | Citadel Layer 1 (Azure Content Safety) |
| PII detection at gateway | Citadel Layer 1 (Azure Language Service) |
| Per-action policy evaluation | AGT Policy Engine |
| Tool call allow/deny | AGT Capability Model |
| Agent-to-agent trust | AGT Trust Layer (Ed25519, SPIFFE) |
| Trust scoring (0-1000) | AGT AgentMesh |
| Tamper-evident audit logs | AGT Audit System |
| Fleet observability | Citadel Layer 2 + AGT Exporter |
| Agent enterprise identity | Citadel Layer 3 (Entra) |
| Threat detection | Citadel Layer 4 (Defender) |
| Data governance labels | Citadel Layer 4 (Purview) + AGT data_classification |

---

## Failure Modes

| Component Unavailable | Behavior |
|----------------------|----------|
| Azure Event Hub / App Insights | AGT continues operating. Events queue locally and retry. |
| Citadel APIM Gateway | Agent cannot reach LLM/tools. AGT policy engine still works locally. |
| AGT Policy Engine | Agent actions proceed ungoverned (configurable fail-open/fail-closed). |

---

## References

- [Agent Governance Toolkit](https://github.com/microsoft/agent-governance-toolkit): Full documentation and source
- [AGT + Citadel Integration Architecture](https://github.com/microsoft/agent-governance-toolkit/blob/main/docs/integrations/citadel-integration.md): Detailed architecture reference
- [End-to-End Example](https://github.com/microsoft/agent-governance-toolkit/tree/main/examples/citadel-governed-agent): Working example with mock mode
- [Foundry Citadel Platform](https://aka.ms/foundry-citadel): Full 4-layer architecture
