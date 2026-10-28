# Edit transcript lines

Decision: reject whitespace-only edits and preserve the text exactly as entered otherwise. For summaries lacking a generation timestamp, show the stale-summary notice after any transcript edit; this avoids presenting an older summary as current.

Finished meetings and uploads only (`ready`) allow inline edits. Return saves; Escape cancels. Edited lines show Edited and offer Revert to original. The original Whisper text remains in `text`; `editedText` and `editedAt` are optional, and `displayText` selects the edit. Reverting clears the edit and timestamp. An edit clears the old translation and schedules translation again when Show English is enabled. Empty edits are rejected.

Display, search, export, summary and action-item generation, Ask indexing and citations, MCP and Scratchpad use displayText. Segment identity, timing, speaker and audio do not change. Re-index after edits. A summary older than the newest edit displays “Transcript edited after this summary”. Generation writes its own fields into the latest manifest, so edits survive generation finishing. Edits are included in backups because the manifest is included.

Original text remains necessary while constructing and deduplicating transcription results before any editing is possible; the live transcript is read-only and consists of unedited segments. Input from speech engines is likewise original. All finished-meeting consumers use displayText.

Owner check: fix a name in a finished meeting; verify export and Ask use the fix, then Revert and verify the original returns.
