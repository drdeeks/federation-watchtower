!/bin/bash
# =============================================================================
# Documentation Indexer - Cursor-like Codebase Knowledge System
#
# Indexes documentation links and builds a searchable knowledge base
# for the entire codebase, similar to Cursor's codebase indexing.
#
# Features:
#   - Index documentation links from multiple sources
#   - Build searchable knowledge base
#   - Support for manual and scheduled indexing
#   - Incremental updates
#   - Full-text search capability
#
# Usage:
#   ./scripts/docs-indexer.sh [command] [options]
#
# Commands:
#   index       Index all documentation links (default)
#   index-file  <file> Index a specific file
#   search      <query> Search the knowledge base
#   update      Update existing index (incremental)
#   rebuild     Rebuild entire index from scratch
#   list        List all indexed documents
#   add-link    <url> <title> [category] Add a documentation link
#   remove-link <url> Remove a documentation link
#   status      Show indexing status
#
# Examples:
#   ./scripts/docs-indexer.sh index
#   ./scripts/docs-indexer.sh search "agent management"
#   ./scripts/docs-indexer.sh add-link "https://github.com/drdeeks/skills" "Hemlock Skills Repo" core
#   ./scripts/docs-indexer.sh --schedule daily
#
# Configuration:
#   Create docs/knowledge-base/config.json to customize indexing behavior
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCS_DIR="$RUNTIME_ROOT/docs"
REFERENCES_DIR="$DOCS_DIR/references"
KNOWLEDGE_BASE_DIR="$DOCS_DIR/knowledge-base"
LOG_DIR="$RUNTIME_ROOT/logs"
CONFIG_FILE="$KNOWLEDGE_BASE_DIR/config.json"
INDEX_FILE="$KNOWLEDGE_BASE_DIR/index.json"
LINKS_FILE="$REFERENCES_DIR/links.json"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[PASS]${NC} $1"; }
error() { echo -e "${RED}[FAIL]${NC} $1" >&2; exit 1; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Ensure directories exist
ensure_dirs() {
    mkdir -p "$REFERENCES_DIR" "$KNOWLEDGE_BASE_DIR" "$LOG_DIR"
}

# Initialize default configuration
init_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" <<'EOF'
{
  "version": "1.0.0",
  "indexing": {
    "enabled": true,
    "schedule": "manual",
    "auto_update": false,
    "interval_hours": 24
  },
  "sources": {
    "markdown": true,
    "text": true,
    "json": true,
    "yaml": true,
    "python": true,
    "bash": true,
    "links": true
  },
  "excludes": [
    "node_modules",
    "__pycache__",
    ".git",
    "*.log",
    "*.tmp",
    "*~"
  ],
  "search": {
    "min_word_length": 3,
    "max_results": 20,
    "fuzzy_search": true
  }
}
EOF
        log "Created default configuration: $CONFIG_FILE"
    fi
}

# Initialize links file
init_links() {
    if [[ ! -f "$LINKS_FILE" ]]; then
        cat > "$LINKS_FILE" <<'EOF'
{
  "links": [],
  "categories": {},
  "last_updated": null
}
EOF
        log "Created default links file: $LINKS_FILE"
    fi
}

# Initialize index file
init_index() {
    if [[ ! -f "$INDEX_FILE" ]]; then
        cat > "$INDEX_FILE" <<'EOF'
{
  "version": "1.0.0",
  "last_indexed": null,
  "document_count": 0,
  "documents": {},
  "keywords": {},
  "categories": {}
}
EOF
        log "Created default index file: $INDEX_FILE"
    fi
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        python3 -c "import json; print(json.dumps(json.load(open('$CONFIG_FILE')), indent=2))" 2>/dev/null
    fi
}

# Add a documentation link
add_link() {
    local url="$1"
    local title="$2"
    local category="$3"
    
    if [[ -z "$url" ]]; then
        error "URL is required. Usage: add-link <url> <title> [category]"
    fi
    
    # Load existing links
    local links_data="{}"
    if [[ -f "$LINKS_FILE" ]]; then
        links_data=$(cat "$LINKS_FILE")
    fi
    
    # Add new link using python
    python3 <<EOF
import json
import sys
from datetime import datetime

links_file = "$LINKS_FILE"
url = "$url"
title = "$title"
category = "$category" if "$category" else "general"

# Load existing data
with open(links_file, 'r') as f:
    data = json.load(f)

# Add link
new_link = {
    "url": url,
    "title": title,
    "category": category,
    "added_at": datetime.now().isoformat(),
    "last_accessed": None,
    "indexed": False
}

data["links"].append(new_link)

# Update categories
data["categories"][category] = data["categories"].get(category, 0) + 1

data["last_updated"] = datetime.now().isoformat()

# Save
with open(links_file, 'w') as f:
    json.dump(data, f, indent=2)

print(f"Added link: {title} ({url})")
EOF
    
    success "Added documentation link: $title"
}

# Index a file
index_file() {
    local file_path="$1"
    local relative_path="${file_path#$RUNTIME_ROOT/}"
    
    if [[ ! -f "$file_path" ]]; then
        warn "File not found: $file_path"
        return
    fi
    
    # Get file extension
    local ext="${file_path##*.}"
    local filename="$(basename "$file_path")"
    
    # Pass file path to Python, let Python handle reading and exclusions
    python3 -c "
import json
import hashlib
import re
import sys
from datetime import datetime

file_path = sys.argv[1]
runtime_root = sys.argv[2]
index_file = sys.argv[3]
config_file = sys.argv[4]

# Load exclusion patterns from config
try:
    with open(config_file, 'r') as f:
        config = json.load(f)
    exclude_patterns = config.get('excludes', [])
except:
    exclude_patterns = ['node_modules', '__pycache__', '.git', '.secrets', '.hermes', '.archive', '.backups', '*.log', '*.tmp', '*~', '*.enc', '*.key', '*.pem', '*secret*', '*password*', '*token*', '*api*key*']

relative_path = file_path.replace(runtime_root + '/', '')

# Don't process if in excluded directory or matches excluded pattern
for pattern in exclude_patterns:
    if pattern in relative_path or relative_path.endswith('/' + pattern.lstrip('*')):
        # Silent exit for excluded files
        import sys
        sys.exit(1)  # Exit with non-zero to indicate exclusion

# Load existing index
try:
    with open(index_file, 'r') as f:
        index = json.load(f)
except:
    index = {
        'version': '1.0.0',
        'last_indexed': datetime.now().isoformat(),
        'document_count': 0,
        'documents': {},
        'keywords': {},
        'categories': {}
    }

# Get file type from extension
import os
_, ext = os.path.splitext(file_path)
ext = ext.lstrip('.').lower()

if ext in ['md', 'markdown', 'txt', 'rst']:
    file_type = 'markdown'
elif ext == 'json':
    file_type = 'json'
elif ext in ['yaml', 'yml']:
    file_type = 'yaml'
elif ext == 'py':
    file_type = 'python'
elif ext == 'sh':
    file_type = 'bash'
else:
    file_type = 'text'

# Read file content safely
try:
    with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
except:
    with open(file_path, 'r', errors='ignore') as f:
        content = f.read()

# Check if content is empty or too short
if len(content) < 50:
    sys.exit(0)

# Compute file hash (based on file path)
doc_id = hashlib.md5(file_path.encode()).hexdigest()

# Compute content hash for version tracking
content_hash = hashlib.md5(content.encode('utf-8', errors='replace')).hexdigest()

# Extract keywords safely
try:
    # Use simpler regex - match word characters (letters, numbers, underscores)
    # This handles both ASCII and unicode
    words = re.findall(r'[a-zA-Z\u00c0-\uffff]{4,}', content.lower())
    keywords = list(set(words))
except:
    keywords = []

# Create document entry with version management
doc_entry = {
    'id': doc_id,
    'path': relative_path,
    'type': file_type,
    'size': len(content),
    'last_modified': datetime.now().isoformat(),
    'content_hash': content_hash,
    'keywords': keywords,
    'preview': content[:500],
    'version': '1.0'
}

# Store document
index['documents'][doc_id] = doc_entry

# Update keywords
for kw in keywords:
    if kw not in index['keywords']:
        index['keywords'][kw] = []
    if doc_id not in index['keywords'][kw]:
        index['keywords'][kw].append(doc_id)

# Update metadata
index['last_indexed'] = datetime.now().isoformat()
index['document_count'] = len(index['documents'])

# Save index
with open(index_file, 'w') as f:
    json.dump(index, f, indent=2)

print(f'Indexed: {relative_path} ({len(keywords)} keywords)')
" "$file_path" "$RUNTIME_ROOT" "$INDEX_FILE" "$CONFIG_FILE" 2>&1
    
    # Exit code 1 means excluded, don't log
    if [[ $? -eq 0 ]]; then
        log "Indexed: $relative_path"
    elif [[ $? -eq 1 ]]; then
        # File excluded - silent
        :
    else
        warn "Error indexing file: $relative_path"
    fi
}

# Index all files in a directory
index_directory() {
    local dir="$1"
    
    find "$dir" -type f 2>/dev/null | while read -r file; do
        index_file "$file"
    done
}

# Main index command
index_all() {
    log "Starting documentation indexing..."
    
    # Index README files
    log "Indexing README files..."
    find "$RUNTIME_ROOT" -name "README.md" -o -name "README.txt" 2>/dev/null | while read -r file; do
        index_file "$file"
    done
    
    # Index markdown files
    log "Indexing markdown files..."
    find "$RUNTIME_ROOT" -name "*.md" 2>/dev/null | while read -r file; do
        index_file "$file"
    done
    
    # Index text files
    log "Indexing text files..."
    find "$RUNTIME_ROOT" -name "*.txt" 2>/dev/null | while read -r file; do
        index_file "$file"
    done
    
    # Index scripts
    log "Indexing scripts..."
    find "$RUNTIME_ROOT/scripts" -name "*.sh" 2>/dev/null | while read -r file; do
        index_file "$file"
    done
    
    # Index configuration files
    log "Indexing configuration files..."
    find "$RUNTIME_ROOT" \( -name "*.json" -o -name "*.yaml" -o -name "*.yml" \) 2>/dev/null | while read -r file; do
        index_file "$file"
    done
    
    # Index agent files
    log "Indexing agent files..."
    if [[ -d "$RUNTIME_ROOT/agents" ]]; then
        for agent_dir in "$RUNTIME_ROOT/agents"/*/; do
            if [[ -d "$agent_dir" ]]; then
                find "$agent_dir" -maxdepth 2 -type f \( -name "*.md" -o -name "*.txt" -o -name "*.json" -o -name "*.yaml" \) 2>/dev/null | while read -r file; do
                    index_file "$file"
                done
            fi
        done
    fi
    
    # Index documentation links
    index_links
    
    success "Documentation indexing complete!"
}

# Index documentation links
index_links() {
    if [[ ! -f "$LINKS_FILE" ]]; then
        return
    fi
    
    log "Indexing documentation links..."
    
    python3 <<EOF
import json
import hashlib
import requests
from datetime import datetime
from urllib.parse import urlparse

links_file = "$LINKS_FILE"
index_file = "$INDEX_FILE"

# Load links
with open(links_file, 'r') as f:
    links_data = json.load(f)

# Load index
try:
    with open(index_file, 'r') as f:
        index = json.load(f)
except:
    index = {
        "version": "1.0.0",
        "last_indexed": datetime.now().isoformat(),
        "document_count": 0,
        "documents": {},
        "keywords": {},
        "categories": {}
    }

# Process each link
for link in links_data.get("links", []):
    url = link.get("url", "")
    title = link.get("title", "Unknown")
    category = link.get("category", "general")
    
    # Create document ID from URL
    doc_id = "link_" + hashlib.md5(url.encode()).hexdigest()
    
    # Parse URL
    parsed = urlparse(url)
    domain = parsed.netloc
    
    # Extract keywords from title and URL
    keywords = []
    for word in title.lower().split():
        if len(word) >= 4 and word.isalpha():
            keywords.append(word)
    
    # Add domain as keyword
    if domain:
        keywords.append(domain.replace(".", "").replace("-", ""))
    
    # Create document entry
    doc_entry = {
        "id": doc_id,
        "path": url,
        "type": "link",
        "title": title,
        "category": category,
        "source": "documentation_link",
        "domain": domain,
        "last_accessed": datetime.now().isoformat(),
        "keywords": list(set(keywords)),
        "preview": title[:500]
    }
    
    # Store document
    index["documents"][doc_id] = doc_entry
    
    # Update keywords
    for kw in doc_entry["keywords"]:
        if kw not in index["keywords"]:
            index["keywords"][kw] = []
        if doc_id not in index["keywords"][kw]:
            index["keywords"][kw].append(doc_id)
    
    # Update categories
    if category not in index["categories"]:
        index["categories"][category] = []
    if doc_id not in index["categories"][category]:
        index["categories"][category].append(doc_id)
    
    # Mark as indexed
    link["indexed"] = True
    link["last_indexed"] = datetime.now().isoformat()

# Update metadata
index["last_indexed"] = datetime.now().isoformat()
index["document_count"] = len(index["documents"])

# Save index
with open(index_file, 'w') as f:
    json.dump(index, f, indent=2)

# Save updated links
with open(links_file, 'w') as f:
    json.dump(links_data, f, indent=2)

print(f"Indexed {len(links_data.get('links', []))} documentation links")
EOF
    
    log "Documentation links indexed"
}

# Search the knowledge base
search() {
    local query="$1"
    
    if [[ -z "$query" ]]; then
        error "Search query is required. Usage: search <query>"
    fi
    
    log "Searching knowledge base for: $query..."
    
    python3 <<EOF
import json
import re
import sys
from datetime import datetime

index_file = "$INDEX_FILE"
query = "$query"

# Load index
try:
    with open(index_file, 'r') as f:
        index = json.load(f)
except:
    print("ERROR: Knowledge base not indexed yet. Run 'index' command first.")
    sys.exit(1)

# Tokenize query
query_words = [w.lower() for w in re.findall(r'\b[a-zA-Z]{3,}\b', query)]

# Search documents
results = []
for doc_id, doc in index.get("documents", {}).items():
    doc_keywords = set(doc.get("keywords", []))
    query_set = set(query_words)
    
    # Check if any query word matches document keywords
    matches = query_set.intersection(doc_keywords)
    
    if len(matches) > 0:
        score = len(matches)
        results.append((score, doc, matches))

# Sort by score
results.sort(key=lambda x: x[0], reverse=True)

# Display results
if not results:
    print(f"No results found for: {query}")
else:
    print(f"\nSearch Results (showing top {min(len(results), 20)}):")
    print("=" * 80)
    for i, (score, doc, matches) in enumerate(results[:20]):
        print(f"\n{i+1}. [{doc.get('type', 'text')}] {doc.get('path', 'N/A')}")
        print(f"   Score: {score}, Keywords: {', '.join(sorted(matches))}")
        print(f"   Preview: {doc.get('preview', '')[:200]}...")
        if doc.get('title'):
            print(f"   Title: {doc.get('title')}")
        if doc.get('category'):
            print(f"   Category: {doc.get('category')}")

print(f"\nTotal results: {len(results)}")
EOF
    
    success "Search complete"
}

# List all indexed documents
list_documents() {
    log "Listing all indexed documents..."
    
    python3 <<EOF
import json
from datetime import datetime

index_file = "$INDEX_FILE"

with open(index_file, 'r') as f:
    index = json.load(f)

print(f"\n${GREEN}Indexed Documents ({index.get('document_count', 0)} total):${NC}")
print("=" * 80)

for i, (doc_id, doc) in enumerate(index.get("documents", {}).items(), 1):
    print(f"\n{i}. [{doc.get('type', 'text')}] {doc.get('path', 'N/A')}")
    if doc.get('title'):
        print(f"   Title: {doc.get('title')}")
    if doc.get('category'):
        print(f"   Category: {doc.get('category')}")
    print(f"   Keywords: {', '.join(doc.get('keywords', [])[:10])}")
    print(f"   Size: {doc.get('size', 0)} chars")

print(f"\n${BLUE}Last indexed: {index.get('last_indexed', 'Never')}${NC}")
EOF
    
    success "Listed ${index.get('document_count', 0)} documents"
}

# Show status
show_status() {
    log "Knowledge Base Status:"
    
    python3 <<EOF
import json
import os

index_file = "$INDEX_FILE"
links_file = "$LINKS_FILE"
config_file = "$CONFIG_FILE"

print(f"\n${GREEN}Configuration:${NC}")
if os.path.exists(config_file):
    with open(config_file, 'r') as f:
        config = json.load(f)
    print(f"  Version: {config.get('version', 'N/A')}")
    print(f"  Indexing enabled: {config.get('indexing', {}).get('enabled', False)}")
    print(f"  Schedule: {config.get('indexing', {}).get('schedule', 'N/A')}")
else:
    print("  Not configured")

print(f"\n${GREEN}Index:${NC}")
if os.path.exists(index_file):
    with open(index_file, 'r') as f:
        index = json.load(f)
    print(f"  Document count: {index.get('document_count', 0)}")
    print(f"  Last indexed: {index.get('last_indexed', 'Never')}")
    print(f"  Categories: {len(index.get('categories', {}))}")
    print(f"  Keywords: {len(index.get('keywords', {}))}")
else:
    print("  Not created yet")

print(f"\n${GREEN}Links:${NC}")
if os.path.exists(links_file):
    with open(links_file, 'r') as f:
        links = json.load(f)
    print(f"  Total links: {len(links.get('links', []))}")
    print(f"  Categories: {len(links.get('categories', {}))}")
    print(f"  Last updated: {links.get('last_updated', 'Never')}")
else:
    print("  No links yet")

print(f"\n${GREEN}Directories:${NC}")
print(f"  References: $REFERENCES_DIR")
print(f"  Knowledge Base: $KNOWLEDGE_BASE_DIR")
EOF
}

# Remove a link
remove_link() {
    local url="$1"
    
    if [[ -z "$url" ]]; then
        error "URL is required. Usage: remove-link <url>"
    fi
    
    python3 <<EOF
import json

links_file = "$LINKS_FILE"
url = "$url"

with open(links_file, 'r') as f:
    data = json.load(f)

# Find and remove link
new_links = [l for l in data.get("links", []) if l.get("url") != url]

# Update categories
categories = {}
for link in new_links:
    cat = link.get("category", "general")
    categories[cat] = categories.get(cat, 0) + 1

data["links"] = new_links
data["categories"] = categories

with open(links_file, 'w') as f:
    json.dump(data, f, indent=2)

print(f"Removed link: {url}")
EOF
    
    success "Removed link: $url"
    
    # Re-index
    index_links
}

# Rebuild entire index
rebuild_index() {
    log "Rebuilding index from scratch..."
    
    # Remove old index
    rm -f "$INDEX_FILE"
    init_index
    
    # Re-index everything
    index_all
    
    success "Index rebuilt"
}

# Main argument parsing
COMMAND=""

while [[ $# -gt 0 ]]; do
    case $1 in
        index|index-all)
            COMMAND="index"
            shift
            ;;
        index-file)
            COMMAND="index-file"
            shift
            ;;
        search)
            COMMAND="search"
            shift
            ;;
        update)
            COMMAND="update"
            shift
            ;;
        rebuild)
            COMMAND="rebuild"
            shift
            ;;
        list)
            COMMAND="list"
            shift
            ;;
        add-link)
            COMMAND="add-link"
            shift
            ;;
        remove-link)
            COMMAND="remove-link"
            shift
            ;;
        status)
            COMMAND="status"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  index              Index all documentation"
            echo "  index-file <file>  Index a specific file"
            echo "  search <query>     Search the knowledge base"
            echo "  update             Update existing index"
            echo "  rebuild            Rebuild entire index"
            echo "  list               List all indexed documents"
            echo "  add-link <url> <title> [category]  Add a documentation link"
            echo "  remove-link <url>  Remove a documentation link"
            echo "  status             Show indexing status"
            echo ""
            echo "Examples:"
            echo "  $0 index"
            echo "  $0 search 'agent management'"
            echo "  $0 add-link 'https://github.com/drdeeks/skills' 'Hemlock Skills Repo' core"
            exit 0
            ;;
        *)
            # Positional arguments for commands
            break
            ;;
    esac
done

# Require positional args for some commands
if [[ -z "$COMMAND" ]]; then
    COMMAND="index"
fi

# Initialize
ensure_dirs
init_config
init_links
init_index

# Execute command
case "$COMMAND" in
    index|index-all)
        index_all "$@"
        ;;
    index-file)
        if [[ $# -lt 1 ]]; then
            error "File path required. Usage: $0 index-file <file>"
        fi
        index_file "$1"
        ;;
    search)
        if [[ $# -lt 1 ]]; then
            error "Search query required. Usage: $0 search <query>"
        fi
        search "$*"
        ;;
    update)
        index_all
        ;;
    rebuild)
        rebuild_index
        ;;
    list)
        list_documents
        ;;
    add-link)
        if [[ $# -lt 2 ]]; then
            error "URL and title required. Usage: $0 add-link <url> <title> [category]"
        fi
        add_link "$1" "$2" "${3:-general}"
        ;;
    remove-link)
        if [[ $# -lt 1 ]]; then
            error "URL required. Usage: $0 remove-link <url>"
        fi
        remove_link "$1"
        ;;
    status)
        show_status
        ;;
    *)
        error "Unknown command: $COMMAND"
        ;;
esac

exit 0
