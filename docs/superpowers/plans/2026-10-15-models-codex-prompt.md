# Codex prompt — Models per feature

Paste everything below the line into Codex, started in
`/Users/cong.bui/Kael/19-AppBuild/BugVoice`.

---

You are implementing Models per feature for BugVoice, a macOS menu-bar dictation app (Swift package, SwiftUI + AppKit).

## Read first, in this order

1. `AGENTS.md` — project rules. They override anything below if they conflict.
2. `docs/superpowers/specs/2026-10-15-models-design.md` — what to build and why.
3. `docs/superpowers/plans/2026-10-15-models.md` — the implementation plan: 8 tasks with exact files, code and tests. Follow it task by task.
4. `docs/design/proposal-models.html` — the approved mockup (open it in a browser if you can).

## Set up a worktree

Work in a separate git worktree, not in the main checkout (another agent may be using it):

```bash
cd /Users/cong.bui/Kael/19-AppBuild/BugVoice
git worktree add ../BugVoice-models -b feat/models main
cd ../BugVoice-models
```

Run every command below from `/Users/cong.bui/Kael/19-AppBuild/BugVoice-models`. The first `swift build` there resolves WhisperKit again; that is expected. `Scripts/build-app.sh` builds `build/BugVoice.app` inside the worktree.

## How to work

- Do the tasks in order, 1 to 8. Each task's checkbox steps are the procedure: write the failing test, run it and see it fail, implement, run it and see it pass, then commit.
- Tasks 1–5 are `VoiceCore` (Foundation only) and strictly test-first. Do not write implementation code before its test has been seen failing.
- Task 6 changes VoiceCore and app code together; its VoiceCore tests come first. Task 7 is app UI with no unit-test target; verify with `swift build`, `swift test`, and `Scripts/build-app.sh`. Task 8 is docs.
- Run `swift test` before every commit; it must pass (currently 331 VoiceCore + 60 BugVoiceMac tests, plus the ones you add).
- Commit after each task with the message given in the plan, ending with the `Co-Authored-By` line shown there. Commit only the files the task names, by path (`git commit -m … -- <paths>`); never `git add -A`. New files need `git add <paths>` first.
- Build the app only with `Scripts/build-app.sh`. Never change signing.
- No new dependencies. No Gemini, API or CLI.
- The plan's code is a strong starting point, not gospel: if it does not compile or a test is wrong, fix it in the smallest way that keeps the spec's behaviour, and note the deviation in your final report. If a deviation would change behaviour the spec describes, stop and report instead of guessing.
- API keys only in Keychain (account `connection-<id>`), never in `settings.json`. A key never goes to plain `http://` on another host, never follows a redirect, and is never echoed in an error.
- UI copy: plain English, no hedging words, no emoji. Use the copy in the spec and plan exactly.
- Task 5 Step 6 runs `claude`, `codex` and `pi` once each with a one-word prompt. Do it from a temporary folder. If a CLI is signed out or a flag is rejected, report it; do not sign in for the user.

## Watch these (from the plan's Review Focus)

1. An old `settings.json` with `textModel` loads as one connection used by Dictation and Meeting notes; the old Keychain key is copied once to `connection-migrated-1`; the next save has no `textModel`.
2. Cancel or timeout stops a CLI subprocess and returns, even with more than a pipe buffer of output. Run the full suite three times to check the process tests are not flaky.
3. Plain `http://` to a LAN host, a URL with user:password, and a 3xx redirect never carry a key.
4. The OpenAI flavor sends `max_completion_tokens` of at least 2048 and no `temperature` or `max_tokens`.
5. A deleted connection that a feature still uses gives raw text with a clear reason, not a crash.

## When you finish

- Do not merge, push, or remove the worktree. Leave `feat/models` in `../BugVoice-models` for review.
- Reply with:
  - the list of commits (`git log --oneline main..feat/models`)
  - the final `swift test` summary lines
  - the result of each CLI in Task 5 Step 6
  - any deviation from the plan and why
  - anything you could not verify (for example the visual checks in Task 7 if you cannot see the screen)
