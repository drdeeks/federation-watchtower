#!/usr/bin/env bash
# CL-040: pre-commit hook (skills-specific example template).
# Refuses commits touching skill dirs that fail validate.py --basic.
# Bypass with `git commit --no-verify` if you genuinely mean it.
#
# This is an example hook installed into a repo's .git/hooks/pre-commit.
# When git runs it, it takes no arguments. It also answers --help/--dry-run so
# it can be inspected as a standalone template.
case "${1:-}" in
    -h|--help)
        echo "usage: pre-commit-hook.sh            (invoked by git as .git/hooks/pre-commit)"
        echo "       pre-commit-hook.sh --dry-run   report which staged skill dirs would be checked"
        echo ""
        echo "Refuses a commit if any staged skill directory fails validate.py --basic."
        echo "Install the generalized guardrail hooks with: python3 install_hooks.py --repo <path>"
        exit 0
        ;;
esac
DRY_RUN=0
[[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]] && DRY_RUN=1
set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
VALIDATE="$REPO_ROOT/skill-creator/scripts/validate.py"

if [[ ! -x "$VALIDATE" && ! -f "$VALIDATE" ]]; then
    # No validator available; allow (fresh clone case)
    exit 0
fi

# Collect unique top-level skill dirs from staged paths.
# A "skill dir" here = any directory under {curated,basic,in-progress}/ OR
# a root-level toolchain skill (skill-*, autowatch, etc.) whose SKILL.md
# is present.
declare -A skill_dirs=()
while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    # Determine skill dir:
    #   curated/foo/... -> curated/foo
    #   basic/foo/...   -> basic/foo
    #   in-progress/foo/... -> in-progress/foo
    #   skill-creator/... -> skill-creator
    #   autowatch/... -> autowatch (if it lives at root; also handled via tier)
    if [[ "$path" =~ ^(curated|basic|in-progress)/([^/]+)/ ]]; then
        skill_dirs["${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"]=1
    elif [[ "$path" =~ ^([^/]+)/SKILL\.md$ ]] || [[ "$path" =~ ^([^/]+)/(scripts|references|__init__\.py) ]]; then
        top="${BASH_REMATCH[1]}"
        if [[ -f "$REPO_ROOT/$top/SKILL.md" ]]; then
            skill_dirs["$top"]=1
        fi
    fi
done < <(git diff --cached --name-only)

if [[ ${#skill_dirs[@]} -eq 0 ]]; then
    exit 0
fi

failed=0
for d in "${!skill_dirs[@]}"; do
    full="$REPO_ROOT/$d"
    [[ ! -d "$full" ]] && continue
    # Run validate.py --basic; failure blocks the commit
    if ! python3 "$VALIDATE" "$full" --basic >/dev/null 2>&1; then
        echo "  ✗ pre-commit: $d fails validate.py --basic" >&2
        failed=$((failed + 1))
    fi
done

if [[ $failed -gt 0 ]]; then
    echo "" >&2
    echo "CL-040 pre-commit hook: $failed skill(s) fail validate.py --basic." >&2
    echo "Run through skill_enhance.py to apply structural fixes, OR" >&2
    echo "bypass with:  git commit --no-verify  (do NOT do this casually)" >&2
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "(--dry-run: would have rejected the commit)" >&2
        exit 0
    fi
    exit 1
fi

exit 0
