# Codex prompt — Dictionary, Snippets and Style

Paste everything below the line into Codex, started in
`/Users/cong.bui/Kael/19-AppBuild/BugVoice`.

---

You are implementing the Dictionary, Snippets and Style feature for BugVoice, a macOS menu-bar dictation app (Swift package, SwiftUI + AppKit).

## Read first, in this order

1. `AGENTS.md` — project rules. They override anything below if they conflict.
2. `docs/superpowers/specs/2026-10-15-dictionary-style-design.md` — what to build and why.
3. `docs/superpowers/plans/2026-10-15-dictionary-style.md` — the implementation plan: 9 tasks with exact files, code and tests. Follow it task by task.
4. `docs/design/proposal-dictionary-style.html` — the approved mockup (open it in a browser if you can).

## Set up a worktree

Work in a separate git worktree, not in the main checkout (another agent may be using it):

```bash
cd /Users/cong.bui/Kael/19-AppBuild/BugVoice
git worktree add ../BugVoice-dictionary-style -b feat/dictionary-style main
cd ../BugVoice-dictionary-style
```

Run every command below from `/Users/cong.bui/Kael/19-AppBuild/BugVoice-dictionary-style`. The first `swift build` there resolves WhisperKit again; that is expected. `Scripts/build-app.sh` builds `build/BugVoice.app` inside the worktree.

## How to work

- Do the tasks in order, 1 to 9. Each task's checkbox steps are the procedure: write the failing test, run it and see it fail, implement, run it and see it pass, then commit.
- Tasks 1–6 are `VoiceCore` (Foundation only) and strictly test-first. Do not write implementation code before its test has been seen failing.
- Tasks 7–8 are app code with no unit-test target; verify with `swift build`, `swift test`, and `Scripts/build-app.sh`. Task 9 is docs.
- Run `swift test` before every commit; it must pass (currently 278 VoiceCore + 60 BugVoiceMac tests, plus the ones you add).
- Commit after each task with the message given in the plan, ending with the `Co-Authored-By` line shown there. Commit only the files the task names, by path (`git commit -m … -- <paths>`); never `git add -A`.
- Build the app only with `Scripts/build-app.sh`. Never change signing.
- No new dependencies.
- The plan's code is a strong starting point, not gospel: if it does not compile or a test is wrong, fix it in the smallest way that keeps the spec's behaviour, and note the deviation in your final report. If a deviation would change behaviour the spec describes, stop and report instead of guessing.
- Snippet text must never reach the text model. A secure-field dictation still never goes to history.
- UI copy: plain English, no hedging words, no emoji. Use the copy in the spec and plan exactly.

## Watch these (from the plan's Review Focus)

1. `await loadDictionary()` must run before `startDictation()` in `AppModel.bootstrap()`.
2. When the model drops, repeats, rewrites or invents a `⟦S…⟧` placeholder, the cleaned text is discarded (`rawReason == .placeholderLost`) and the snippet is still filled exactly.
3. Old `settings.json` and `history.jsonl` data with the `chat` style must load without losing anything.
4. Migration writes `dictionary.json` before renaming `vocabulary.txt`, and never overwrites an existing `dictionary.json`.
5. Two quick Dictionary edits both persist (memory first, then a save with a revision; the store skips older revisions).

## When you finish

- Do not merge, push, or remove the worktree. Leave `feat/dictionary-style` in `../BugVoice-dictionary-style` for review.
- Reply with:
  - the list of commits (`git log --oneline main..feat/dictionary-style`)
  - the final `swift test` summary lines
  - any deviation from the plan and why
  - anything you could not verify (for example the visual checks in Tasks 7–8 if you cannot see the screen)
