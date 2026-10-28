# Per-field destination check

Decision: if either accessibility element is unavailable, treat the comparison as unknown and retain the existing paste behavior. This protects apps without stable accessibility focus.

Capture the focused accessibility element at the start of ordinary dictation. At insertion, secure focus at start or finish takes precedence and copies; a different app copies with the existing focus-changed outcome. Within the same app, a known different element copies with `copiedFieldChanged`; the same or an unknown element pastes. Do not move focus. Notes are unaffected. History and Insights count the new outcome as copied focus change. The HUD says “Copied — press ⌘V” and “the cursor moved to another field”.

Owner checks, away from the keyboard: stay in the same field in Ghostty, VS Code, Chrome, Notion and Slack and verify paste. Switch Slack channel before the result and verify copy and warning. Try switching terminal split panes and record the behavior; paste is acceptable if no element is available.
