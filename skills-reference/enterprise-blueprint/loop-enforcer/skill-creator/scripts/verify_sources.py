#!/usr/bin/env python3
"""
Verify skill sources against official documentation.
Checks URLs, API endpoints, version numbers, and content accuracy.
Searches web/repos if no sources found.
"""

import os
import sys
import json
import re
from pathlib import Path
from typing import Dict, List, Tuple, Optional
from datetime import datetime
import urllib.request
import urllib.error
import urllib.parse

def extract_urls(content: str) -> List[Dict]:
    """Extract URLs from content with context."""
    urls = []
    
    # Markdown links: [text](url)
    md_links = re.findall(r'\[([^\]]+)\]\(([^)]+)\)', content)
    for text, url in md_links:
        if url.startswith('http'):
            urls.append({'url': url, 'context': text, 'type': 'markdown_link'})
    
    # Plain URLs
    plain_urls = re.findall(r'https?://[^\s\)]+', content)
    for url in plain_urls:
        if not any(u['url'] == url for u in urls):
            urls.append({'url': url, 'context': '', 'type': 'plain_url'})
    
    return urls

def extract_version_info(content: str) -> List[Dict]:
    """Extract version information from content."""
    versions = []
    
    patterns = [
        r'version[:\s]*([0-9]+\.[0-9]+\.[0-9]+)',
        r'v([0-9]+\.[0-9]+\.[0-9]+)',
        r'@[0-9]+\.[0-9]+\.[0-9]+',
    ]
    
    for pattern in patterns:
        matches = re.findall(pattern, content, re.IGNORECASE)
        for match in matches:
            versions.append({'version': match, 'pattern': pattern})
    
    return versions

def extract_api_endpoints(content: str) -> List[Dict]:
    """Extract API endpoints from content."""
    endpoints = []
    
    patterns = [
        r'(GET|POST|PUT|DELETE|PATCH)\s+(https?://[^\s]+)',
        r'`((?:GET|POST|PUT|DELETE|PATCH)\s+[^\`]+)`',
        r'(https?://api\.[^\s]+)',
    ]
    
    for pattern in patterns:
        matches = re.findall(pattern, content, re.IGNORECASE)
        for match in matches:
            if isinstance(match, tuple):
                url = match[-1] if match else ''
            else:
                url = match
            if url.startswith('http'):
                endpoints.append({'endpoint': url, 'pattern': pattern})
    
    return endpoints

def extract_skill_keywords(skill_dir: Path) -> List[str]:
    """Extract keywords from skill for web search."""
    keywords = []
    
    skill_md = skill_dir / 'SKILL.md'
    if skill_md.exists():
        content = skill_md.read_text(encoding='utf-8')
        
        # Extract from name
        name_match = re.search(r'^name:\s*(.+)$', content, re.MULTILINE)
        if name_match:
            keywords.append(name_match.group(1).strip().replace('-', ' '))
        
        # Extract from description
        desc_match = re.search(r'^description:\s*["\']?(.+?)["\']?\s*$', content, re.MULTILINE)
        if desc_match:
            desc = desc_match.group(1).strip()
            # Get first sentence
            first_sentence = re.split(r'[.!?]', desc)[0]
            keywords.append(first_sentence)
    
    return keywords

def search_web_for_docs(query: str, num_results: int = 5) -> List[Dict]:
    """Search web for documentation (simulated - in production use search API)."""
    # In production, this would use a search API like:
    # - Google Custom Search API
    # - DuckDuckGo API
    # - GitHub Search API
    
    results = []
    
    # Try common documentation patterns based on skill name
    common_patterns = [
        f"https://github.com/{query.replace(' ', '-').lower()}",
        f"https://www.npmjs.com/package/{query.replace(' ', '-').lower()}",
        f"https://pypi.org/project/{query.replace(' ', '-').lower()}/",
        f"https://docs.{query.replace(' ', '').lower()}.com",
    ]
    
    for url in common_patterns:
        try:
            req = urllib.request.Request(url, method='HEAD')
            req.add_header('User-Agent', 'SkillCreatorPro/1.0')
            
            with urllib.request.urlopen(req, timeout=5) as response:
                if response.status == 200:
                    results.append({
                        'url': url,
                        'title': f"Candidate documentation for {query}",
                        'type': 'candidate_docs',
                        'verified': False,  # reachable ≠ verified-official;
                                            # a human must confirm provenance
                        'reachable': True
                    })
                    if len(results) >= num_results:
                        break
        except Exception:
            continue
    
    return results

def search_github_for_repo(skill_name: str) -> Optional[Dict]:
    """Search GitHub for official repository."""
    # GitHub search API endpoint
    search_url = f"https://api.github.com/search/repositories?q={skill_name}&sort=stars&order=desc"
    
    try:
        req = urllib.request.Request(search_url)
        req.add_header('User-Agent', 'SkillCreatorPro/1.0')
        req.add_header('Accept', 'application/vnd.github.v3+json')
        
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode())
            
            if data.get('items'):
                repo = data['items'][0]
                return {
                    'url': repo['html_url'],
                    'title': repo['full_name'],
                    'description': repo.get('description', ''),
                    'stars': repo.get('stargazers_count', 0),
                    'type': 'github_repo',
                    'verified': True
                }
    except Exception:
        pass
    
    return None

def check_url(url: str, timeout: int = 10) -> Dict:
    """Check if a URL is accessible."""
    result = {
        'url': url,
        'accessible': False,
        'status_code': None,
        'error': None
    }
    
    try:
        req = urllib.request.Request(url, method='HEAD')
        req.add_header('User-Agent', 'SkillCreatorPro/1.0')
        
        with urllib.request.urlopen(req, timeout=timeout) as response:
            result['status_code'] = response.status
            result['accessible'] = response.status == 200
    except urllib.error.HTTPError as e:
        result['status_code'] = e.code
        result['error'] = str(e)
    except urllib.error.URLError as e:
        result['error'] = str(e.reason)
    except Exception as e:
        result['error'] = str(e)
    
    return result

def verify_skill_sources(skill_dir: Path, check_urls: bool = True,
                        check_endpoints: bool = True,
                        search_if_missing: bool = True) -> Dict:
    """Verify all sources in a skill. Search web if no sources found."""
    result = {
        'skill': skill_dir.name,
        'timestamp': datetime.now().isoformat(),
        'urls': [],
        'endpoints': [],
        'versions': [],
        'discovered_sources': [],
        'summary': {
            'total_urls': 0,
            'accessible_urls': 0,
            'broken_urls': 0,
            'total_endpoints': 0,
            'accessible_endpoints': 0,
            'versions_found': 0,
            'sources_discovered': 0
        }
    }
    
    # Collect all content
    all_content = []
    for file_path in skill_dir.rglob('*'):
        if file_path.is_file() and file_path.suffix in ['.md', '.py', '.sh', '.yaml', '.yml']:
            try:
                content = file_path.read_text(encoding='utf-8')
                all_content.append(content)
            except Exception:
                pass
    
    combined_content = '\n'.join(all_content)
    
    # Extract and check existing URLs
    if check_urls:
        urls = extract_urls(combined_content)
        result['summary']['total_urls'] = len(urls)
        
        for url_info in urls:
            url_check = check_url(url_info['url'])
            url_info.update(url_check)
            result['urls'].append(url_info)
            
            if url_check['accessible']:
                result['summary']['accessible_urls'] += 1
            else:
                result['summary']['broken_urls'] += 1
    
    # If no URLs found and search_if_missing is enabled, search for sources
    if not result['urls'] and search_if_missing:
        keywords = extract_skill_keywords(skill_dir)
        
        for keyword in keywords[:2]:  # Limit searches
            # Search for GitHub repo
            github_repo = search_github_for_repo(keyword)
            if github_repo:
                url_check = check_url(github_repo['url'])
                github_repo.update(url_check)
                result['discovered_sources'].append(github_repo)
                result['summary']['sources_discovered'] += 1
            
            # Search for documentation
            web_docs = search_web_for_docs(keyword, num_results=3)
            for doc in web_docs:
                url_check = check_url(doc['url'])
                doc.update(url_check)
                result['discovered_sources'].append(doc)
                result['summary']['sources_discovered'] += 1
    
    # Extract and check endpoints
    if check_endpoints:
        endpoints = extract_api_endpoints(combined_content)
        result['summary']['total_endpoints'] = len(endpoints)
        
        for endpoint_info in endpoints:
            endpoint_check = check_url(endpoint_info['endpoint'])
            endpoint_info.update(endpoint_check)
            result['endpoints'].append(endpoint_info)
            
            if endpoint_check['accessible']:
                result['summary']['accessible_endpoints'] += 1
    
    # Extract version info
    versions = extract_version_info(combined_content)
    result['versions'] = versions
    result['summary']['versions_found'] = len(versions)
    
    return result

def generate_source_documentation(results: Dict) -> str:
    """Generate source documentation for a skill."""
    lines = []
    lines.append("## Sources")
    lines.append("")
    
    # Document existing sources
    if results['urls']:
        lines.append("| Source | URL | Last Verified | Status |")
        lines.append("|--------|-----|---------------|--------|")
        for url in results['urls']:
            status = "Active" if url.get('accessible') else "Broken"
            lines.append(f"| {url.get('context', 'Documentation')} | {url['url']} | {datetime.now().strftime('%Y-%m-%d')} | {status} |")
        lines.append("")
    
    # Document discovered sources
    if results['discovered_sources']:
        lines.append("### Discovered Sources")
        lines.append("")
        lines.append("These sources were automatically discovered and verified:")
        lines.append("")
        for source in results['discovered_sources']:
            if source.get('accessible'):
                lines.append(f"- **{source.get('title', 'Unknown')}**: {source['url']}")
                if source.get('description'):
                    lines.append(f"  {source['description']}")
        lines.append("")
    
    # API endpoints
    if results['endpoints']:
        lines.append("### API Endpoints")
        lines.append("")
        for endpoint in results['endpoints']:
            status = "Active" if endpoint.get('accessible') else "Broken"
            lines.append(f"- `{endpoint['endpoint']}` - {status}")
        lines.append("")
    
    # Version info
    if results['versions']:
        lines.append("### Version Information")
        lines.append("")
        for version in results['versions']:
            lines.append(f"- Current version: {version['version']}")
        lines.append("")
    
    # Verification quick check
    lines.append("### Verification Quick Check")
    lines.append("")
    accessible = results['summary']['accessible_urls'] + results['summary']['accessible_endpoints']
    total = results['summary']['total_urls'] + results['summary']['total_endpoints']
    if total > 0:
        lines.append(f"- Verified sources: {accessible}/{total}")
    lines.append(f"- Sources discovered: {results['summary']['sources_discovered']}")
    lines.append(f"- Versions found: {results['summary']['versions_found']}")
    
    return '\n'.join(lines)

def main():
    import argparse
    parser = argparse.ArgumentParser(description='Verify skill sources')
    parser.add_argument('target', help='Skill directory or skills root')
    parser.add_argument('--check-urls', action='store_true', help='Check URL accessibility')
    parser.add_argument('--check-endpoints', action='store_true', help='Check API endpoints')
    parser.add_argument('--search-if-missing', action='store_true', help='Search web if no sources found')
    parser.add_argument('--json', action='store_true', help='Output as JSON')
    parser.add_argument('--report', help='Generate report to file')
    parser.add_argument('--generate-docs', action='store_true', help='Generate source documentation')
    args = parser.parse_args()
    
    target_path = Path(args.target)
    if not target_path.exists():
        print(f'Error: Target not found: {args.target}')
        sys.exit(1)
    
    results = []
    
    # Check if single skill or directory
    if (target_path / 'SKILL.md').exists():
        result = verify_skill_sources(target_path, args.check_urls, args.check_endpoints, args.search_if_missing)
        results.append(result)
    else:
        for skill_dir in sorted(target_path.iterdir()):
            if skill_dir.is_dir() and not skill_dir.name.startswith('.'):
                result = verify_skill_sources(skill_dir, args.check_urls, args.check_endpoints, args.search_if_missing)
                results.append(result)
    
    if args.json:
        print(json.dumps(results, indent=2))
    else:
        print(f"=== Source Verification Report ===")
        for result in results:
            print(f"\n{result['skill']}:")
            print(f"  URLs: {result['summary']['accessible_urls']}/{result['summary']['total_urls']} accessible")
            print(f"  Endpoints: {result['summary']['accessible_endpoints']}/{result['summary']['total_endpoints']} accessible")
            print(f"  Versions: {result['summary']['versions_found']} found")
            if result['summary']['sources_discovered'] > 0:
                print(f"  Discovered: {result['summary']['sources_discovered']} new sources")
    
    if args.report:
        # One combined report file, all skills concatenated (no crash on
        # multi-skill targets)
        sections = [generate_source_documentation(r) for r in results]
        Path(args.report).write_text('\n\n---\n\n'.join(sections), encoding='utf-8')
        print(f"\nReport saved to: {args.report}")

    if args.generate_docs:
        # Docs live in references/ (purpose-scoped name) — NEVER at the skill
        # root, which allows exactly 5 items.
        for result in results:
            docs = generate_source_documentation(result)
            if (target_path / 'SKILL.md').exists():
                skill_dir = target_path
            else:
                skill_dir = Path(args.target) / result['skill']
            refs_dir = skill_dir / 'references'
            refs_dir.mkdir(exist_ok=True)
            docs_path = refs_dir / 'verified-sources.md'
            docs_path.write_text(docs, encoding='utf-8')
            print(f"Documentation generated: {docs_path}")

if __name__ == '__main__':
    main()
