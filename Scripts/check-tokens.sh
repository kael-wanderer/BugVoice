#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ALLOW=''
PENDING=''

is_exempt() {
    local path="$1"
    case "$path" in
        Sources/BugVoice/UI/Theme/*) return 0 ;;
    esac

    local entry allowed
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        allowed="${entry%%  #*}"
        if [[ "$path" == "$allowed" || "$path" == "$allowed/"* ]]; then return 0; fi
    done <<< "$ALLOW"

    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        if [[ "$path" == "$entry" || "$path" == "$entry/"* ]]; then return 0; fi
    done <<< "$PENDING"

    return 1
}

check_rule() {
    local label="$1"
    local pattern="$2"
    local hit path line
    while IFS= read -r hit; do
        [[ -z "$hit" ]] && continue
        path="${hit%%:*}"
        line="${hit#*:}"
        line="${line%%:*}"
        if ! is_exempt "$path"; then
            printf '%s:%s: %s\n' "$path" "$line" "$label"
            violations=$((violations + 1))
        fi
    done < <(rg -n --no-heading --color never "$pattern" Sources/BugVoice || true)
}

violations=0
check_rule '.font(.system(size:' '\.font\(\.system\(size:'
check_rule 'SwiftUI text style font' '\.font\(\.(caption2?|body|headline|subheadline|title[23]?|largeTitle|callout|footnote)\b'
check_rule 'Color system style' 'Color\.(secondary|primary|accentColor)'
check_rule 'foregroundStyle system style' '\.foregroundStyle\(\.(secondary|tertiary|primary)\)'
check_rule 'Color(red: literal)' 'Color\(red:'
check_rule 'NSColor literal' 'NSColor\([[:space:]]*(red|white|calibratedRed|srgbRed)'
check_rule 'hex color string' '"[^"[:cntrl:]]*#[0-9a-fA-F]{6}\b'

if (( violations > 0 )); then exit 1; fi
