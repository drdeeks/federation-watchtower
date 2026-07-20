#!/usr/bin/env python3
"""
Deep analysis of an existing skill.
Checks frontmatter, content, redundancy, agnostic compliance, and source verification.
"""

import os
import sys
sys.dont_write_bytecode = True  # keep __pycache__ out of skill trees
import json
import re
from pathlib import Path
from typing import Dict, List, Tuple, Optional
from datetime import datetime

try:
    import yaml
except ModuleNotFoundError:
    yaml = None

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from skill_root import find_skill_root, nested_skill_mds


def extract_frontmatter(content: str) -> Tuple[Optional[str], str]:
    """Extract YAML frontmatter and body."""
    lines = content.splitlines()
    if not lines or lines[0].strip() != '---':
        return None, content
    
    for i in range(1, len(lines)):
        if lines[i].strip() == '---':
            frontmatter = '\n'.join(lines[1:i])
            body = '\n'.join(lines[i+1:])
            return frontmatter, body
    
    return None, content

def analyze_frontmatter(frontmatter_text: str) -> Dict:
    """Analyze frontmatter quality."""
    result = {
        'valid': False,
        'issues': [],
        'warnings': [],
        'score': 0
    }
    
    if yaml is not None:
        try:
            frontmatter = yaml.safe_load(frontmatter_text)
            if not isinstance(frontmatter, dict):
                result['issues'].append('Frontmatter must be a YAML dictionary')
                return result
        except yaml.YAMLError as e:
            result['issues'].append(f'Invalid YAML: {e}')
            return result
    else:
        frontmatter = {}
        for line in frontmatter_text.splitlines():
            if ':' in line:
                key, value = line.split(':', 1)
                frontmatter[key.strip()] = value.strip()
    
    # Check required keys
    if 'name' not in frontmatter:
        result['issues'].append("Missing 'name' in frontmatter")
    else:
        name = frontmatter['name']
        if not re.match(r'^[a-z0-9-]+$', str(name)):
            result['issues'].append(f"Name '{name}' should be hyphen-case")
        if len(str(name)) > 64:
            result['issues'].append(f"Name too long ({len(str(name))} chars)")
    
    if 'description' not in frontmatter:
        result['issues'].append("Missing 'description' in frontmatter")
    else:
        desc = str(frontmatter['description'])
        if len(desc) > 1024:
            result['issues'].append(f"Description too long ({len(desc)} chars)")
        if '<' in desc or '>' in desc:
            result['issues'].append("Description contains angle brackets")
    
    # Check allowed keys (kept in sync with validate.py ALLOWED_PROPERTIES)
    allowed = {'name', 'description', 'license', 'metadata', 'allowed-tools', 'version'}
    unexpected = set(frontmatter.keys()) - allowed
    if unexpected:
        result['warnings'].append(f"Unexpected keys: {', '.join(sorted(unexpected))}")
    if 'version' not in frontmatter:
        result['issues'].append("Missing 'version' — versioning is mandatory")
    
    # Calculate score
    checks = [
        'name' in frontmatter,
        'description' in frontmatter,
        not unexpected,
        all(k in frontmatter for k in ['name', 'description'])
    ]
    result['score'] = sum(checks) / len(checks) * 100
    result['valid'] = len(result['issues']) == 0
    
    return result

def analyze_content(body: str) -> Dict:
    """Analyze content quality."""
    result = {
        'score': 0,
        'issues': [],
        'warnings': [],
        'metrics': {
            'length': len(body),
            'sections': 0,
            'code_blocks': 0,
            'links': 0,
            'todos': 0
        }
    }
    
    # Basic metrics
    result['metrics']['sections'] = len(re.findall(r'^##\s+', body, re.MULTILINE))
    result['metrics']['code_blocks'] = len(re.findall(r'```', body)) // 2
    result['metrics']['links'] = len(re.findall(r'\[([^\]]+)\]\(([^)]+)\)', body))
    result['metrics']['todos'] = len(re.findall(r'TODO|FIXME|HACK|XXX', body, re.IGNORECASE))
    
    # Quality checks
    if result['metrics']['length'] < 100:
        result['issues'].append('Content too short (< 100 chars)')
    
    if result['metrics']['sections'] == 0:
        result['warnings'].append('No sections found')
    
    if result['metrics']['todos'] > 0:
        result['warnings'].append(f'Contains {result["metrics"]["todos"]} TODO/FIXME markers')
    
    # Check for empty sections
    sections = re.findall(r'^##\s+(.+)$', body, re.MULTILINE)
    for section in sections:
        section_pattern = f'^## {re.escape(section)}$'
        section_match = re.search(section_pattern, body, re.MULTILINE)
        if section_match:
            start = section_match.end()
            next_section = re.search(r'^##\s+', body[start:], re.MULTILINE)
            if next_section:
                section_content = body[start:start + next_section.start()].strip()
            else:
                section_content = body[start:].strip()
            
            if len(section_content) < 20:
                result['warnings'].append(f"Section '{section}' is sparse")
    
    # Calculate score
    checks = [
        result['metrics']['length'] >= 100,
        result['metrics']['sections'] > 0,
        result['metrics']['todos'] == 0,
        result['metrics']['links'] > 0
    ]
    result['score'] = sum(checks) / len(checks) * 100
    
    return result

def analyze_structure(skill_dir: Path) -> Dict:
    """Analyze skill directory structure."""
    result = {
        'score': 0,
        'issues': [],
        'warnings': [],
        'directories': [],
        'files': []
    }
    
    # Check required files
    required = ['SKILL.md']
    for req in required:
        if not (skill_dir / req).exists():
            result['issues'].append(f'Missing required file: {req}')
    
    # Required directories per the 5-root-item standard
    for req_dir in ['scripts', 'references']:
        if (skill_dir / req_dir).exists():
            result['directories'].append(req_dir)
        else:
            result['issues'].append(f'Missing required directory: {req_dir}/')
    # assets/ is banned anywhere in a skill
    if (skill_dir / 'assets').exists():
        result['issues'].append('assets/ present — banned; redistribute into '
                                'scripts/ or references/')
    if not (skill_dir / '__init__.py').exists():
        result['issues'].append('Missing required file: __init__.py')
    # Nested SKILL.mds are structural violations
    for nested in nested_skill_mds(skill_dir):
        result['issues'].append(f'Nested SKILL.md: {nested.relative_to(skill_dir)}')
    
    # List all files
    for file_path in sorted(skill_dir.rglob('*')):
        if file_path.is_file():
            result['files'].append(str(file_path.relative_to(skill_dir)))
    
    # Check for excessive files
    if len(result['files']) > 50:
        result['warnings'].append(f'Excessive files ({len(result["files"])})')
    
    # Calculate score
    checks = [
        (skill_dir / 'SKILL.md').exists(),
        len(result['directories']) >= 2,
        len(result['files']) <= 50
    ]
    result['score'] = sum(checks) / len(checks) * 100
    
    return result

def analyze_agnostic(skill_dir: Path) -> Dict:
    """Analyze skill for hardcoded paths and platform-specific references."""
    result = {
        'score': 100,
        'issues': [],
        'warnings': [],
        'hardcoded_count': 0
    }
    
    hardcoded_patterns = [
        (r'/home/\w+/', 'Hardcoded home directory'),
        (r'/root/', 'Hardcoded root directory'),
        (r'/opt/\w+/', 'Hardcoded /opt path'),
        (r'~/.openclaw/', 'Hardcoded OpenClaw path'),
        (r'~/.hermes/', 'Hardcoded Hermes path'),
        (r'~/.config/opencode/', 'Hardcoded OpenCode path'),
        (r'/tmp/\w+/', 'Hardcoded temp path'),
    ]
    
    for file_path in skill_dir.rglob('*'):
        if file_path.is_file() and file_path.suffix in ['.md', '.py', '.sh', '.yaml', '.yml', '.json']:
            try:
                content = file_path.read_text(encoding='utf-8')
                lines = content.split('\n')
                
                for line_num, line in enumerate(lines, 1):
                    for pattern, description in hardcoded_patterns:
                        if re.search(pattern, line):
                            result['issues'].append({
                                'file': str(file_path.relative_to(skill_dir)),
                                'line': line_num,
                                'issue': description,
                                'content': line.strip()[:100]
                            })
                            result['hardcoded_count'] += 1
            except Exception:
                pass
    
    # Calculate score
    if result['hardcoded_count'] > 0:
        result['score'] = max(0, 100 - (result['hardcoded_count'] * 10))
    
    return result

def analyze_skill_deep(skill_dir: Path) -> Dict:
    """Perform deep analysis of a skill."""
    result = {
        'name': skill_dir.name,
        'path': str(skill_dir),
        'timestamp': datetime.now().isoformat(),
        'analysis': {
            'frontmatter': {},
            'content': {},
            'structure': {},
            'agnostic': {}
        },
        'overall_score': 0,
        'recommendations': []
    }
    
    # Analyze frontmatter
    skill_md = skill_dir / 'SKILL.md'
    if skill_md.exists():
        content = skill_md.read_text(encoding='utf-8')
        frontmatter_text, body = extract_frontmatter(content)
        
        if frontmatter_text:
            result['analysis']['frontmatter'] = analyze_frontmatter(frontmatter_text)
        else:
            result['analysis']['frontmatter'] = {'valid': False, 'issues': ['No frontmatter found'], 'score': 0}
        
        result['analysis']['content'] = analyze_content(body)
    else:
        result['analysis']['frontmatter'] = {'valid': False, 'issues': ['SKILL.md not found'], 'score': 0}
        result['analysis']['content'] = {'score': 0, 'issues': ['No SKILL.md'], 'warnings': [], 'metrics': {}}
    
    # Analyze structure
    result['analysis']['structure'] = analyze_structure(skill_dir)
    
    # Analyze agnostic compliance
    result['analysis']['agnostic'] = analyze_agnostic(skill_dir)
    
    # Calculate overall score
    scores = [
        result['analysis']['frontmatter'].get('score', 0),
        result['analysis']['content'].get('score', 0),
        result['analysis']['structure'].get('score', 0),
        result['analysis']['agnostic'].get('score', 0)
    ]
    result['overall_score'] = sum(scores) / len(scores)
    
    # Generate recommendations
    if result['analysis']['frontmatter'].get('issues'):
        result['recommendations'].append('Fix frontmatter issues')
    if result['analysis']['content'].get('issues'):
        result['recommendations'].append('Improve content quality')
    if result['analysis']['structure'].get('warnings'):
        result['recommendations'].append('Add recommended directories')
    if result['analysis']['agnostic'].get('issues'):
        result['recommendations'].append('Remove hardcoded paths')
    
    return result

def main():
    import argparse
    parser = argparse.ArgumentParser(description='Deep skill analysis')
    parser.add_argument('target', help='Skill directory')
    parser.add_argument('--deep', action='store_true', help='Perform deep analysis')
    parser.add_argument('--json', action='store_true', help='Output as JSON')
    args = parser.parse_args()
    
    target_path = Path(args.target)
    if not target_path.exists():
        print(f'Error: Target not found: {args.target}')
        sys.exit(1)

    # Resolve to the true skill root: given any path inside a skill, travel
    # up to the directory whose root holds SKILL.md.
    root = find_skill_root(target_path)
    if root is None:
        print(f'Error: no SKILL.md found at or above {target_path} — not a skill')
        sys.exit(1)
    if root != target_path.resolve():
        print(f'Note: resolved to skill root {root}')
    target_path = root

    result = analyze_skill_deep(target_path)

    # --deep: embed the authoritative validator result
    if args.deep:
        from validate import validate_skill
        v = validate_skill(str(target_path), basic_mode=False)
        result['validator'] = {
            'status': v['status'],
            'fails': v['fails'],
            'warnings': v['warnings'],
            'fail_details': [c.name for c in v['checks']
                             if not c.passed and c.severity == 'FAIL'],
        }
    
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(f"=== Deep Analysis: {result['name']} ===")
        print(f"Overall Score: {result['overall_score']:.1f}%")
        print()
        
        for section, data in result['analysis'].items():
            score = data.get('score', 0)
            issues = data.get('issues', [])
            warnings = data.get('warnings', [])
            
            print(f"{section.upper()} ({score:.0f}%):")
            if issues:
                for issue in issues:
                    if isinstance(issue, dict):
                        print(f"  ✗ {issue.get('issue', issue)}")
                    else:
                        print(f"  ✗ {issue}")
            if warnings:
                for warning in warnings:
                    print(f"  ⚠ {warning}")
            if not issues and not warnings:
                print(f"  ✓ No issues found")
            print()
        
        if result['recommendations']:
            print("RECOMMENDATIONS:")
            for rec in result['recommendations']:
                print(f"  - {rec}")

if __name__ == '__main__':
    main()
