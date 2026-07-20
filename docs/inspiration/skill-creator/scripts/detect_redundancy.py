#!/usr/bin/env python3
"""
Redundancy detection for skills.
Scans existing skills for overlapping functionality and suggests consolidation.
"""

import os
import sys
sys.dont_write_bytecode = True  # keep __pycache__ out of skill trees
import json
import re
from pathlib import Path
from typing import Dict, List, Set, Tuple
from datetime import datetime
from collections import Counter

try:
    import yaml
except ModuleNotFoundError:
    yaml = None

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from skill_root import find_skills


def extract_keywords(content: str) -> Set[str]:
    """Extract meaningful keywords from skill content."""
    # Remove frontmatter
    lines = content.splitlines()
    body_start = 0
    in_frontmatter = False
    for i, line in enumerate(lines):
        if line.strip() == '---':
            if not in_frontmatter:
                in_frontmatter = True
            else:
                body_start = i + 1
                break
    
    body = '\n'.join(lines[body_start:])
    
    # Extract words
    words = re.findall(r'\b[a-z]{3,}\b', body.lower())
    
    # Filter common words
    stop_words = {'the', 'and', 'for', 'are', 'but', 'not', 'you', 'all', 'can', 'had', 'her', 'was', 'one', 'our', 'out', 'has', 'his', 'how', 'its', 'may', 'new', 'now', 'old', 'see', 'way', 'who', 'did', 'get', 'let', 'say', 'she', 'too', 'use', 'this', 'that', 'with', 'have', 'from', 'they', 'been', 'said', 'each', 'which', 'their', 'will', 'other', 'about', 'many', 'then', 'them', 'would', 'make', 'like', 'into', 'time', 'very', 'when', 'come', 'could', 'more', 'than', 'also'}
    
    return set(w for w in words if w not in stop_words)

def extract_functionality(content: str) -> List[str]:
    """Extract functionality descriptions from skill content."""
    functionalities = []
    
    # Look for feature lists, capabilities, what-it-does sections
    patterns = [
        r'(?:features|capabilities|what it does|functionality)[:\s]*\n((?:[-*].*\n)+)',
        r'(?:use when|triggers?)[:\s]*\n((?:[-*].*\n)+)',
        r'(?:covers?|includes?)[:\s]*((?:[-*].*\n)+)',
    ]
    
    for pattern in patterns:
        matches = re.findall(pattern, content, re.IGNORECASE)
        for match in matches:
            items = re.findall(r'[-*]\s*(.*)', match)
            functionalities.extend(items)
    
    return functionalities

def calculate_similarity(keywords1: Set[str], keywords2: Set[str]) -> float:
    """Calculate Jaccard similarity between two keyword sets."""
    if not keywords1 or not keywords2:
        return 0.0
    intersection = keywords1 & keywords2
    union = keywords1 | keywords2
    return len(intersection) / len(union) if union else 0.0

def calculate_functionality_overlap(func1: List[str], func2: List[str]) -> float:
    """Calculate overlap between functionality descriptions."""
    if not func1 or not func2:
        return 0.0
    
    # Convert to sets of normalized words
    words1 = set()
    words2 = set()
    
    for f in func1:
        words1.update(re.findall(r'\b[a-z]{3,}\b', f.lower()))
    for f in func2:
        words2.update(re.findall(r'\b[a-z]{3,}\b', f.lower()))
    
    if not words1 or not words2:
        return 0.0
    
    intersection = words1 & words2
    union = words1 | words2
    return len(intersection) / len(union) if union else 0.0

def analyze_skill(skill_path: Path) -> Dict:
    """Analyze a single skill for redundancy detection."""
    skill_md = skill_path / 'SKILL.md'
    if not skill_md.exists():
        return {'name': skill_path.name, 'keywords': set(), 'functionality': []}
    
    content = skill_md.read_text(encoding='utf-8')
    
    return {
        'name': skill_path.name,
        'keywords': extract_keywords(content),
        'functionality': extract_functionality(content),
        'content_length': len(content),
        'has_scripts': (skill_path / 'scripts').exists(),
        'has_references': (skill_path / 'references').exists(),
    }

def detect_redundancy(target_dir: str, skill_name: str = None,
                      threshold: float = 0.3) -> Dict:
    """Detect redundancy among skills in target directory."""
    target_path = Path(target_dir)

    results = {
        'timestamp': datetime.now().isoformat(),
        'target': target_dir,
        'threshold': threshold,
        'skills_analyzed': 0,
        'redundancy_pairs': [],
        'consolidation_candidates': [],
        'summary': {
            'total_skills': 0,
            'redundant_pairs': 0,
            'consolidation_needed': 0
        }
    }

    # Discover skills at any depth (skill-root aware — never descends INTO a
    # skill, so nested SKILL.mds don't produce phantom entries)
    skills = {}
    for skill_dir in find_skills(target_path):
        analysis = analyze_skill(skill_dir)
        key = skill_dir.name
        if key in skills:
            # Same-name dupe found at different paths — rank by version,
            # then file count, then content hash difference
            key = str(skill_dir.relative_to(Path(target_dir).resolve()))
        skills[key] = analysis
        results['skills_analyzed'] += 1
    
    results['summary']['total_skills'] = len(skills)
    
    # Compare all pairs
    skill_names = list(skills.keys())
    for i in range(len(skill_names)):
        for j in range(i + 1, len(skill_names)):
            name1 = skill_names[i]
            name2 = skill_names[j]
            
            skill1 = skills[name1]
            skill2 = skills[name2]
            
            # Calculate similarity scores
            keyword_sim = calculate_similarity(skill1['keywords'], skill2['keywords'])
            func_sim = calculate_functionality_overlap(skill1['functionality'], skill2['functionality'])
            
            # Combined score (weighted)
            combined_score = (keyword_sim * 0.4) + (func_sim * 0.6)
            
            if combined_score > threshold:  # Threshold for reporting
                pair = {
                    'skill1': name1,
                    'skill2': name2,
                    'keyword_similarity': round(keyword_sim, 3),
                    'functionality_similarity': round(func_sim, 3),
                    'combined_score': round(combined_score, 3),
                    'recommendation': ''
                }
                
                if combined_score > 0.7:
                    pair['recommendation'] = 'MERGE REQUIRED - Major overlap detected'
                elif combined_score > 0.5:
                    pair['recommendation'] = 'CONSOLIDATE - Significant overlap'
                elif combined_score > 0.3:
                    pair['recommendation'] = 'REVIEW - Minor overlap'
                
                results['redundancy_pairs'].append(pair)
                results['summary']['redundant_pairs'] += 1
    
    # Sort by combined score
    results['redundancy_pairs'].sort(key=lambda x: x['combined_score'], reverse=True)
    
    # Identify consolidation candidates
    merged_skills = set()
    for pair in results['redundancy_pairs']:
        if pair['combined_score'] > 0.5:
            if pair['skill1'] not in merged_skills and pair['skill2'] not in merged_skills:
                results['consolidation_candidates'].append({
                    'primary': pair['skill1'],
                    'secondary': pair['skill2'],
                    'score': pair['combined_score'],
                    'reason': pair['recommendation']
                })
                merged_skills.add(pair['skill2'])
                results['summary']['consolidation_needed'] += 1
    
    # If specific skill requested, filter results
    if skill_name:
        filtered_pairs = [p for p in results['redundancy_pairs'] 
                         if p['skill1'] == skill_name or p['skill2'] == skill_name]
        results['redundancy_pairs'] = filtered_pairs
        results['summary']['redundant_pairs'] = len(filtered_pairs)
    
    return results

def main():
    import argparse
    parser = argparse.ArgumentParser(description='Detect skill redundancy')
    parser.add_argument('--target', required=True, help='Target skills directory')
    parser.add_argument('--skill-name', help='Check specific skill against others')
    parser.add_argument('--json', action='store_true', help='Output as JSON')
    parser.add_argument('--threshold', type=float, default=0.3, help='Similarity threshold')
    args = parser.parse_args()
    
    results = detect_redundancy(args.target, args.skill_name, args.threshold)
    
    if args.json:
        print(json.dumps(results, indent=2))
    else:
        print(f"=== Redundancy Detection Report ===")
        print(f"Target: {results['target']}")
        print(f"Skills analyzed: {results['skills_analyzed']}")
        print(f"Redundant pairs found: {results['summary']['redundant_pairs']}")
        print(f"Consolidation needed: {results['summary']['consolidation_needed']}")
        print()
        
        if results['redundancy_pairs']:
            print("Redundancy Pairs:")
            for pair in results['redundancy_pairs'][:10]:
                print(f"  {pair['skill1']} <-> {pair['skill2']}")
                print(f"    Score: {pair['combined_score']}")
                print(f"    {pair['recommendation']}")
                print()
        
        if results['consolidation_candidates']:
            print("Consolidation Candidates:")
            for cand in results['consolidation_candidates']:
                print(f"  Merge: {cand['primary']} + {cand['secondary']}")
                print(f"    Score: {cand['score']}")
                print()

if __name__ == '__main__':
    main()
