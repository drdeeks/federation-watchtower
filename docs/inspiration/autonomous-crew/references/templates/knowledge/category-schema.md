# Crew Knowledge Category Schema

## Category Taxonomy

```yaml
categories:
  architecture:
    description: "System architecture, design decisions, data models"
    subcategories:
      - system-design
      - data-model
      - api-design
      - infra-design
      - boundaries
    typical_doctypes:
      - decision
      - spec
      - learning
    tags: ["architecture", "design", "system", "boundaries"]

  api:
    description: "API contracts, interfaces, integration patterns"
    subcategories:
      - rest
      - graphql
      - grpc
      - webhooks
      - auth
      - versioning
    typical_doctypes:
      - spec
      - decision
      - communication
    tags: ["api", "interface", "contract", "integration"]

  ui:
    description: "User interface, components, design systems"
    subcategories:
      - components
      - design-system
      - accessibility
      - state-management
      - styling
      - testing
    typical_doctypes:
      - spec
      - learning
      - decision
    tags: ["ui", "frontend", "components", "design"]

  infra:
    description: "Infrastructure, deployment, operations"
    subcategories:
      - deployment
      - monitoring
      - scaling
      - ci-cd
      - security
      - networking
    typical_doctypes:
      - decision
      - spec
      - learning
    tags: ["infra", "devops", "deployment", "ops"]

  process:
    description: "Team processes, workflows, coordination"
    subcategories:
      - workflow
      - communication
      - review
      - planning
      - retro
      - onboarding
    typical_doctypes:
      - learning
      - communication
      - sync
    tags: ["process", "workflow", "team", "coordination"]

  debugging:
    description: "Root cause analysis, performance, errors"
    subcategories:
      - root-cause
      - performance
      - errors
      - testing
      - profiling
      - regression
    typical_doctypes:
      - reasoning
      - learning
      - decision
    tags: ["debugging", "bug", "performance", "root-cause"]

  research:
    description: "Exploration, spikes, evaluation, comparison"
    subcategories:
      - exploration
      - spike
      - evaluation
      - comparison
      - feasibility
      - poc
    typical_doctypes:
      - learning
      - spec
      - reasoning
    tags: ["research", "spike", "evaluation", "poc"]
```

## Tag Vocabulary Guidelines

### Required Tags
- At least 1 category-aligned tag per document
- Max 5 tags per document
- Use lowercase, hyphen-separated

### Standard Tags by Category

#### Architecture
`architecture`, `design`, `system-design`, `data-model`, `boundaries`, `patterns`, `tradeoffs`

#### API
`api`, `rest`, `graphql`, `grpc`, `webhooks`, `auth`, `oauth`, `versioning`, `contract`, `schema`

#### UI
`ui`, `frontend`, `components`, `design-system`, `accessibility`, `state-management`, `styling`, `testing`

#### Infra
`infra`, `devops`, `deployment`, `monitoring`, `scaling`, `ci-cd`, `security`, `networking`, `kubernetes`, `docker`

#### Process
`process`, `workflow`, `communication`, `review`, `planning`, `retro`, `onboarding`, `coordination`

#### Debugging
`debugging`, `bug`, `performance`, `root-cause`, `error`, `profiling`, `testing`, `regression`

#### Research
`research`, `spike`, `evaluation`, `comparison`, `feasibility`, `poc`, `exploration`

## Tagging Rules

1. **Always include category tag** - e.g., `architecture`, `api`, `ui`
2. **Add subcategory if applicable** - e.g., `oauth`, `rest`, `components`
3. **Add cross-cutting concern** - e.g., `security`, `testing`, `performance`
4. **Max 5 tags total** - prioritize specificity
5. **Consistent vocabulary** - use established tags, don't invent new ones without discussion

## Example Tag Combinations

| Document | Tags |
|----------|------|
| OAuth2 decision | `architecture`, `auth`, `oauth`, `security`, `tradeoffs` |
| User profile API spec | `api`, `rest`, `versioning`, `schema`, `contract` |
| Button component spec | `ui`, `components`, `design-system`, `accessibility` |
| Deployment pipeline decision | `infra`, `deployment`, `ci-cd`, `monitoring` |
| Sprint retro learning | `process`, `retro`, `workflow`, `coordination` |
| Memory leak root cause | `debugging`, `root-cause`, `performance`, `memory` |
| Database comparison spike | `research`, `spike`, `evaluation`, `comparison` |

## Anti-Patterns to Avoid

- ❌ `authentication` + `auth` (pick one: `auth`)
- ❌ `ui-design`, `frontend-design`, `design` (pick one: `design`)
- ❌ More than 5 tags
- ❌ Inventing new tags without crew discussion
- ❌ Missing category tag