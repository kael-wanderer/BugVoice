# Crash recovery of an in-flight dictation

Decision: if recovery cannot validate the recording or save it, do not expose it as a failed dictation. Preserve the marker on a save error so recovery can be attempted again; discard invalid or expired markers.

Before finishNow writes or deletes last.wav, remove any existing marker. At recovery, the decoded recording duration must match the marker within 0.1 seconds; otherwise discard the marker. This prevents stale markers from being paired with a later recording.

When an eligible ordinary dictation begins processing after writing last.wav, persist an owner-only inflight.json containing its id, start time, application name and bundle ID, and duration. Eligibility matches failed-recording retention: history enabled, non-secure at start, not a note or meeting note, and not a retry of a kept recording. Remove the marker on every completed outcome, including cancellation and failure.

Before loading failed recordings at launch, recover a valid, unexpired marker and decodable last.wav into the existing failed-recording store. Preserve its metadata and use the reason “BugVoice quit before this dictation finished.” The store enforces its existing age and count limits. Remove a missing, damaged or expired marker silently. Recovery never copies or pastes. The existing Needs attention UI and Retry action apply; no mockup is needed.

Owner check: dictate with a slow cleanup model, quit BugVoice from Activity Monitor during Cleaning, and relaunch. Verify the recording appears under Needs attention with the quit reason and Retry copies it.
