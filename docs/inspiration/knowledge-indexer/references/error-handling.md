# Error Handling Reference
## Table of Contents

- [Common Errors](#common-errors)
- [Debugging](#debugging)
- [Recovery Procedures](#recovery-procedures)
- [Prevention](#prevention)


## Common Errors

### 1. Knowledge Base Not Indexed

**Error**: `ERROR: Knowledge base not indexed yet. Run 'index' command first.`

**Cause**: The index file doesn't exist or is empty.

**Solution**:
```bash
bash scripts/knowledge-indexer.sh index
```

### 2. File Not Found

**Error**: `File not found: /path/to/file`

**Cause**: The specified file doesn't exist.

**Solution**:
- Verify the file path is correct
- Check if the file was moved or deleted

### 3. Python Not Found

**Error**: `python3: command not found`

**Cause**: Python 3.6+ is not installed.

**Solution**:
```bash
# On Ubuntu/Debian
sudo apt-get install python3

# On macOS
brew install python3
```

### 4. Permission Denied

**Error**: `Permission denied: /path/to/directory`

**Cause**: Insufficient permissions to read/write the directory.

**Solution**:
```bash
chmod 755 /path/to/directory
```

### 5. JSON Parse Error

**Error**: `json.decoder.JSONDecodeError`

**Cause**: Corrupted JSON file.

**Solution**:
```bash
# Rebuild the index
bash scripts/knowledge-indexer.sh rebuild
```

## Debugging

### Enable Verbose Output

```bash
# Run with bash debug mode
bash -x scripts/knowledge-indexer.sh index
```

### Check Index Status

```bash
bash scripts/knowledge-indexer.sh status
```

### Verify Configuration

```bash
cat docs/knowledge-base/config.json
```

## Recovery Procedures

### Corrupted Index

If the index file is corrupted:

```bash
# Backup corrupted index
mv docs/knowledge-base/index.json docs/knowledge-base/index.json.bak

# Rebuild from scratch
bash scripts/knowledge-indexer.sh rebuild
```

### Missing Links File

If the links file is missing:

```bash
# Create empty links file
cat > docs/references/links.json << 'EOF'
{
  "links": [],
  "categories": {},
  "last_updated": null
}
EOF
```

## Prevention

1. **Regular Backups**: Backup the knowledge base directory periodically
2. **Atomic Writes**: The indexer uses atomic writes to prevent corruption
3. **Exclusion Patterns**: Properly configure exclusions to avoid indexing sensitive files
