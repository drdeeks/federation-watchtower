# Source Verification Guide

## Table of Contents

- [Why Verify Sources?](#why-verify-sources)
- [Verification Types](#verification-types)
- [Search Strategies](#search-strategies)
- [Source Documentation Format](#source-documentation-format)
- [Handling Unverifiable Sources](#handling-unverifiable-sources)
- [Automated Verification Schedule](#automated-verification-schedule)
- [Verification Report Template](#verification-report-template)

## Why Verify Sources?

- Ensure accuracy of technical information
- Detect outdated documentation
- Validate API endpoints are active
- Confirm version numbers are current
- Build trust in skill reliability

## Verification Types

### 1. URL Verification
Check if documentation URLs are accessible and current.

```python
# Check URL accessibility
def check_url(url):
    try:
        response = requests.head(url, timeout=10)
        return response.status_code == 200
    except:
        return False
```

**Best Practices:**
- Check HEAD request first (faster)
- Verify content type is appropriate
- Look for redirect chains
- Check SSL certificate validity

### 2. API Endpoint Verification
Confirm API endpoints are active and returning expected data.

```python
# Check API endpoint
def check_api(endpoint):
    response = requests.get(endpoint)
    return response.status_code == 200
```

**What to Check:**
- Response status code
- Response time (should be reasonable)
- Content-Type header
- Basic response structure

### 3. Version Verification
Ensure version numbers are current and accurate.

**Sources for Version Info:**
- Package registries (npm, PyPI, crates.io)
- GitHub releases
- Official documentation
- Changelog files

### 4. Content Verification
Validate technical accuracy of claims.

**Methods:**
- Cross-reference with official docs
- Test code examples
- Verify command syntax
- Check parameter names/types

### 5. License Verification
Confirm license compatibility.

**Steps:**
- Check license file exists
- Verify license type matches claims
- Ensure dependencies are compatible
- Document license in frontmatter

## Search Strategies

### When No Sources Found

1. **GitHub Search**
   - Search for official repository
   - Check stars, activity, maintainers
   - Verify README matches skill description

2. **Package Registry Search**
   - npm: `https://www.npmjs.com/package/{name}`
   - PyPI: `https://pypi.org/project/{name}/`
   - crates.io: `https://crates.io/crates/{name}`

3. **Documentation Search**
   - Official docs sites
   - API references
   - Tutorials and guides

### Search Query Patterns

```
# GitHub
"{skill-name}" language:python stars:>100
"{skill-name}" official repository

# General
"{skill-name}" documentation
"{skill-name}" API reference
"{skill-name}" getting started
```

## Source Documentation Format

```markdown
## Sources

| Source | URL | Last Verified | Status |
|--------|-----|---------------|--------|
| Official Docs | https://... | 2026-06-05 | Active |
| API Reference | https://... | 2026-06-05 | Active |
| GitHub Repo | https://... | 2026-06-05 | Active |

### Verification Quick Check
- Docs URL responds with 200: ✓
- API endpoint returns valid JSON: ✓
- GitHub repo has recent commits: ✓
- Version matches registry: ✓
```

## Handling Unverifiable Sources

If a source cannot be verified:

1. **Mark as unverified** in documentation
2. **Add warning** in skill description
3. **Request manual verification** from user
4. **Remove if critical** - don't include unverifiable critical claims

## Automated Verification Schedule

| Frequency | Check Type |
|-----------|------------|
| Daily | URL accessibility |
| Weekly | API endpoint responses |
| Monthly | Version numbers |
| Quarterly | Content accuracy |

## Verification Report Template

```markdown
# Source Verification Report

## Summary
- Skills verified: X
- Total URLs: X
- Accessible: X
- Broken: X
- Versions checked: X

## Broken URLs
- [Skill] URL: reason

## Outdated Versions
- [Skill] Current: X, Latest: Y

## Recommendations
- [Action needed]
```
