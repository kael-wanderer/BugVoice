# Codex prompt — Insights

Paste everything below the line into Codex, started in
`/Users/cong.bui/Kael/19-AppBuild/BugVoice`.

---

You are implementing the Insights feature for BugVoice, a macOS menu-bar dictation app (Swift package, SwiftUI + AppKit).

## Read first, in this order

1. `AGENTS.md` — project rules. They override anything below if they conflict.
2. `docs/superpowers/specs/2026-10-15-insights-design.md` — what to build and why.
3. `docs/superpowers/plans/2026-10-15-insights.md` — the implementation plan: 8 tasks with exact files, code and tests. Follow it task by task.
4. `docs/design/proposal-insights-page.html` — the approved page mockup (open it in a browser if you can).

## How to work

- Create and work on a branch: `git switch -c feat/insights` from `main`.
- Do the tasks in order, 1 to 8. Each task's checkbox steps are the procedure: write the failing test, run it and see it fail, implement, run it and see it pass, then commit.
- Tasks 1–4 are `VoiceCore` (Foundation only) and strictly test-first. Do not write implementation code before its test has been seen failing.
- Tasks 5–8 are app code with no unit-test target; verify with `swift build`, `swift test`, and `Scripts/build-app.sh`.
- Run `swift test` before every commit; it must pass (currently 229 VoiceCore + 60 BugVoiceMac tests, plus the ones you add).
- Commit after each task with the message given in the plan, ending with the `Co-Authored-By` line shown there. Commit only the files the task names, by path (`git commit -m … <paths>`); never `git add -A`.
- Build the app only with `Scripts/build-app.sh`. Never change signing.
- No new dependencies.
- The plan's code is a strong starting point, not gospel: if it does not compile or a test is wrong, fix it in the smallest way that keeps the spec's behaviour, and note the deviation in your final report. If a deviation would change behaviour the spec describes, stop and report instead of guessing.
- `insights.json` must never contain dictated text. A secure-field dictation adds nothing.
- UI copy: plain English, no hedging words, no emoji. Use the copy in the spec and plan exactly.

## Watch these (from the plan's Review Focus)

1. `await loadInsights()` must run before `startDictation()` in `AppModel.bootstrap()`, and before `applyRetention()` prunes history, or the backfill double-counts or misses entries.
2. Dictations are filed under the day of `result.startedAt`, not the time they finish.
3. Day keys use the Mac's current calendar and time zone.
4. Missing or empty app names count as "Unknown".
5. Cleanup changes that only touch case or punctuation count as 0 fixes.

## When you finish

- Do not merge or push. Leave `feat/insights` for review.
- Reply with:
  - the list of commits (`git log --oneline main..feat/insights`)
  - the final `swift test` summary lines
  - any deviation from the plan and why
  - anything you could not verify (for example the visual checks in Tasks 6–8 if you cannot see the screen)
