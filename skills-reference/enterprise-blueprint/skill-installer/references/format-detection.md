# Skill Format Detection Reference

## Table of Contents

- [Supported Formats](#supported-formats)
- [Detection Logic](#detection-logic)
- [Format-Specific Handling](#format-specific-handling)
- [Edge Cases](#edge-cases)

## Supported Formats

| Format | Extension | Description | Detection Method |
|--------|-----------|-------------|------------------|
| .skill Archive | `.skill` | Zip archive with skill structure | File extension + zip magic bytes |
| Zip Archive | `.zip` | Generic zip containing skills | File extension + zip magic bytes |
| Skill Directory | Directory | Directory with SKILL.md | Directory + SKILL.md exists |
| Package Directory | Directory | Directory containing multiple skills | Directory + multiple SKILL.md files |
| Remote URL | URL | HTTP/HTTPS or git URL | URL pattern matching |
| Git Repository | `git@...` or `https://...git` | Git repository with skills | URL pattern matching |

## Detection Logic

### 1. File-Based Detection

```python
def detect_file_format(path: Path) -> str:
    if path.is_file():
        if path.suffix == '.skill':
            return "skill-zip"
        elif path.suffix == '.zip':
            # Check if it contains .skill files
            with zipfile.ZipFile(path, 'r') as z:
                if any(f.endswith('.skill') for f in z.namelist()):
                    return "skill-zip"
                else:
                    return "zip"
    return "unknown"
```

### 2. Directory-Based Detection

```python
def detect_directory_format(path: Path) -> str:
    if path.is_dir():
        skill_md = path / "SKILL.md"
        if skill_md.exists():
            return "directory"
        else:
            # Count SKILL.md files in subdirectories
            skill_md_files = list(path.rglob("SKILL.md"))
            if len(skill_md_files) > 0:
                return "package"
    return "unknown"
```

### 3. Remote Detection

```python
def detect_remote_format(url: str) -> str:
    if url.startswith(('http://', 'https://')):
        if url.endswith('.skill'):
            return "remote-skill-zip"
        elif url.endswith('.zip'):
            return "remote-zip"
        else:
            return "remote-web"
    elif url.startswith('git@') or url.endswith('.git'):
        return "remote-git"
    return "unknown"
```

## Format-Specific Handling

### .skill Archives

.skill files are zip archives containing the full skill directory structure:

```
my-skill.skill
├── my-skill/
│   ├── SKILL.md
│   ├── scripts/
│   │   └── main.py
│   ├── references/
│   │   └── overview.md
│   └── assets/
│       └── template.txt
```

**Extraction Process:**
1. Verify zip integrity
2. Extract to temporary directory
3. Locate SKILL.md
4. Identify skill root directory
5. Copy to target location

### Skill Directories

Standard skill directory structure:

```
my-skill/
├── SKILL.md
├── scripts/
├── references/
└── assets/
```

**Installation Process:**
1. Validate SKILL.md exists
2. Check structure compliance
3. Validate content
4. Copy to target location

### Package Directories

Directories containing multiple skills:

```
skill-package/
├── skill-a/
│   ├── SKILL.md
│   └── scripts/
├── skill-b/
│   ├── SKILL.md
│   └── references/
└── skill-c.skill
```

**Installation Process:**
1. Scan for all skills
2. Detect format for each
3. Install each skill
4. Generate batch report

## Edge Cases

### Nested Archives

Some packages contain nested .skill files:

```
package.zip
├── skill-a.skill
├── skill-b/
│   └── SKILL.md
└── sub-package/
    └── skill-c.skill
```

**Handling:**
1. Extract outer archive
2. Scan for inner .skill files
3. Extract and install each

### Mixed Formats

Packages may contain both directories and archives:

```
mixed-package/
├── skill-dir/
│   └── SKILL.md
├── skill-zip.skill
└── skill-zip2.zip
```

**Handling:**
1. Scan all items
2. Detect format for each
3. Handle appropriately

### Large Archives

Some skill packages are very large (>100MB):

**Handling:**
1. Stream extraction (don't load entire archive)
2. Progress reporting
3. Timeout handling

### Corrupted Archives

**Handling:**
1. Verify zip integrity before extraction
2. Graceful error reporting
3. Skip corrupted items, continue with others

## Validation Integration

All format detection includes validation:

1. **Format Detection**: Identify skill format
2. **Extraction**: Extract if needed
3. **Structure Validation**: Check SKILL.md, directories
4. **Content Validation**: Check frontmatter, content quality
5. **Compatibility Check**: Ensure compliance via skill-creator's validate.py (delegated)

## References

- **Skill Anatomy**: [skill-anatomy.md](skill-anatomy.md)
- **Validation Rules**: [validation-rules.md](validation-rules.md)
- **Installation Guide**: [installation-guide.md](installation-guide.md)
