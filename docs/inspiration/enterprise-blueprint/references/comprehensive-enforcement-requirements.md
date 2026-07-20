# Comprehensive Enforcement Requirements (v2.0)

> Externalized from SKILL.md to reduce bloat. Originally written as the "Comprehensive Enforcement Requirements (v2.0)" section of the enterprise-blueprint skill body. Referenced as a generic checklist template that applies to most enterprise projects.

---

Every project MUST include ALL of the following:

## 1. Application Functionality
- [ ] Core business logic implemented and tested
- [ ] All features from specification working end-to-end
- [ ] Error handling with user-facing messages
- [ ] Input validation and sanitization
- [ ] Graceful degradation when services unavailable
- [ ] No placeholder or dummy implementations

## 2. API Layer
- [ ] REST/GraphQL API endpoints documented
- [ ] Request/response schemas defined
- [ ] Authentication and authorization implemented
- [ ] Rate limiting configured
- [ ] API versioning strategy
- [ ] OpenAPI/Swagger documentation

## 3. Frontend (if applicable)
- [ ] User interface implemented
- [ ] Responsive design for all screen sizes
- [ ] Accessibility (WCAG 2.1 AA compliance)
- [ ] Cross-browser testing
- [ ] State management
- [ ] Error boundaries and fallback UI

## 4. Database & Storage
- [ ] Schema defined with migrations
- [ ] Indexes for query performance
- [ ] Backup and recovery procedures
- [ ] Data validation at database level
- [ ] Connection pooling
- [ ] Seed data for development

## 5. Testing (All Tiers)
- [ ] Unit tests (80%+ coverage)
- [ ] Integration tests for API endpoints
- [ ] E2E tests for critical workflows
- [ ] Performance/load testing
- [ ] Security testing (OWASP Top 10)
- [ ] Accessibility testing

## 6. Deployment & Operations
- [ ] Dockerfile with multi-stage build
- [ ] docker-compose.yml for local development
- [ ] CI/CD pipeline configuration
- [ ] Environment variable documentation
- [ ] Health check endpoints (/health, /ready)
- [ ] Graceful shutdown handling

## 7. Monitoring & Logging
- [ ] Structured logging (JSON format)
- [ ] Log levels configured (ERROR, WARN, INFO, DEBUG)
- [ ] Metrics collection (Prometheus/DataDog)
- [ ] Alerting thresholds defined
- [ ] Audit trail for critical operations
- [ ] Distributed tracing (if microservices)

## 8. Security
- [ ] Authentication (JWT/OAuth/API keys)
- [ ] Authorization (RBAC/ABAC)
- [ ] Input validation and sanitization
- [ ] SQL injection prevention
- [ ] XSS protection
- [ ] CORS configuration
- [ ] Secrets management (not in code)
- [ ] Dependency vulnerability scanning

## 9. Documentation
- [ ] README.md with setup instructions
- [ ] API.md with endpoint documentation
- [ ] ARCHITECTURE.md with system design
- [ ] CONTRIBUTING.md for developers
- [ ] CHANGELOG.md with version history
- [ ] LICENSE file

## 10. Code Quality
- [ ] Linting configured (ESLint/Prettier/Black)
- [ ] Code formatting consistent
- [ ] No hardcoded secrets or credentials
- [ ] No commented-out code blocks
- [ ] Meaningful variable/function names

## 11. Performance
- [ ] Response time benchmarks defined
- [ ] Memory usage profiling
- [ ] Database query optimization
- [ ] Caching strategy implemented
- [ ] CDN configuration (if static assets)
- [ ] Load testing results documented

## 12. Dependency Management
- [ ] package.json / requirements.txt / Cargo.toml
- [ ] Lock files committed (package-lock.json, etc.)
- [ ] No unnecessary dependencies
- [ ] Dependency versions pinned
- [ ] Security audit of dependencies
- [ ] License compatibility checked
