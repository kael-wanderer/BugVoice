#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ALLOW=''
PENDING='Sources/BugVoice/HUD/HUDView.swift
Sources/BugVoice/MeetingDetectionController.swift
Sources/BugVoice/UI/Components/PillTabs.swift
Sources/BugVoice/UI/DictationHistoryView.swift
Sources/BugVoice/UI/Dictionary/DictionaryPage.swift
Sources/BugVoice/UI/Dictionary/DictionaryWordsView.swift
Sources/BugVoice/UI/Dictionary/HeroCard.swift
Sources/BugVoice/UI/Dictionary/SnippetEditorSheet.swift
Sources/BugVoice/UI/Dictionary/SnippetsView.swift
Sources/BugVoice/UI/Insights/ActivityHeatmap.swift
Sources/BugVoice/UI/Insights/BreakdownBars.swift
Sources/BugVoice/UI/Insights/InsightsPage.swift
Sources/BugVoice/UI/Insights/StatCard.swift
Sources/BugVoice/UI/Library/FolderControls.swift
Sources/BugVoice/UI/Library/LabelsBox.swift
Sources/BugVoice/UI/Library/ManageFoldersSheet.swift
Sources/BugVoice/UI/Library/TagField.swift
Sources/BugVoice/UI/MainWindow.swift
Sources/BugVoice/UI/MeetingPlayer.swift
Sources/BugVoice/UI/MeetingSpeakersRow.swift
Sources/BugVoice/UI/MeetingWindow/MeetingTranscriptView.swift
Sources/BugVoice/UI/MeetingWindow/MeetingWindowView.swift
Sources/BugVoice/UI/MeetingsPage.swift
Sources/BugVoice/UI/NotesPage.swift
Sources/BugVoice/UI/PermissionsView.swift
Sources/BugVoice/UI/Scratchpad/AIBar.swift
Sources/BugVoice/UI/Scratchpad/AskAnswerView.swift
Sources/BugVoice/UI/Scratchpad/CitationPanel.swift
Sources/BugVoice/UI/Scratchpad/CitationPlayer.swift
Sources/BugVoice/UI/Scratchpad/MarkdownDocView.swift
Sources/BugVoice/UI/Scratchpad/MarkdownTextStyler.swift
Sources/BugVoice/UI/Scratchpad/MarkdownToolbar.swift
Sources/BugVoice/UI/Scratchpad/ScratchpadNoteEditor.swift
Sources/BugVoice/UI/Scratchpad/ScratchpadTabBar.swift
Sources/BugVoice/UI/Scratchpad/ScratchpadWindowView.swift
Sources/BugVoice/UI/Settings/AgentsSettings.swift
Sources/BugVoice/UI/Settings/GeneralTab.swift
Sources/BugVoice/UI/Settings/MeetingsTab.swift
Sources/BugVoice/UI/Settings/Models/CLIsCard.swift
Sources/BugVoice/UI/Settings/Models/ConnectionSheet.swift
Sources/BugVoice/UI/Settings/Models/ConnectionsCard.swift
Sources/BugVoice/UI/Settings/Models/ModelsTab.swift
Sources/BugVoice/UI/Settings/Models/SearchCard.swift
Sources/BugVoice/UI/Settings/Models/UseForCard.swift
Sources/BugVoice/UI/Settings/SettingsComponents.swift
Sources/BugVoice/UI/Settings/SettingsView.swift
Sources/BugVoice/UI/Settings/SpeechTab.swift
Sources/BugVoice/UI/Settings/StorageTab.swift
Sources/BugVoice/UI/Style/StyleDetailView.swift
Sources/BugVoice/UI/Style/StylePage.swift
Sources/BugVoice/UI/UploadPage.swift'

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
