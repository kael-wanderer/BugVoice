# BugVoice: Read Me First

## 1. Install

Drag BugVoice into Applications.

## 2. Open BugVoice

BugVoice is not signed with an Apple Developer ID, so macOS blocks the first open. You will see this message:

![BugVoice Not Opened](screenshots/not-opened.png)

You only do this once. Use one of these two ways.

### Way A: System Settings (easiest)

1. Click **Done** on the message. Do not click Move to Trash.
2. Open System Settings › Privacy & Security.
3. Scroll down and click **Open Anyway** next to BugVoice.

   ![Open Anyway in Privacy & Security](screenshots/open-anyway.png)

4. Enter your Mac password.

### Way B: Terminal

1. Open Terminal.
2. Paste this and press Return:

   `xattr -cr /Applications/BugVoice.app`

3. Open BugVoice again.

Updates through Check for Updates need the same step. The update note in Settings › General repeats both ways.
