"""Source of the BugVoice product page copy.

Run `python3 site-content/build_page.py` to check every field against the page
builder's limits and write BugVoice-page.md and BugVoice-sections.json.
Exits non-zero when a field is too long or a screenshot is missing.
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SHOTS = os.path.join(HERE, "screenshots")
BANNED = ["revolutionary", "seamless", "supercharge"]

CATALOG = {
    "name": "BugVoice",
    "pronunciation": "BUG-voice",
    "summary": "Hold a key, speak, and clean text appears at your cursor. A local-first Mac dictation and meeting notes app for English, Vietnamese and Spanish.",
    "details": (
        "BugVoice lives in the menu bar. Hold Right Control, speak, release, and the cleaned text is pasted "
        "into whatever app you are in: a terminal, an email, a chat. Speech-to-text runs on your Mac with "
        "WhisperKit, and cleanup uses a local text model you choose or Apple Intelligence. It also records "
        "meetings from your mic and the call, then writes the transcript, summary and action items. "
        "Your notes, meetings and history stay on your Mac."
    ),
    "category": "Productivity",
    "tags": "dictation, speech to text, meeting notes, local-first, macOS, Vietnamese",
    "platform": "macOS",
    "license": "TBD (see questions for owner)",
    "requirements": "macOS 15 Sequoia or later · Apple Silicon (M1 or later)",
    "accent": "#D42F4A",
}

SCREENSHOTS = [
    ("01-hero.png", "Dictation history with cleaned text from each app"),
    ("02-meeting-transcript.png", "Meeting transcript with named speakers"),
    ("03-meeting-summary-dark.png", "Meeting summary in dark mode"),
    ("04-meeting-translation.png", "Vietnamese meeting with English under each line"),
    ("05-action-items.png", "Action items from every meeting in one list"),
    ("06-insights.png", "Insights: words, streaks and time saved"),
    ("07-scratchpad.png", "Scratchpad notes with folders and tags"),
    ("08-dictionary.png", "Dictionary words and what they get misheard as"),
    ("09-styles.png", "Styles set the tone for each group of apps"),
    ("10-languages.png", "Speech settings: languages and on-device model"),
]

FEATURES = [
    {"background": "plain", "kicker": "Dictation for every app",
     "title": "Speak instead of type, in any text field on your Mac",
     "description": "Hold Right Control, talk, let go. BugVoice turns your speech into text on your Mac, "
                    "removes filler words and false starts, and pastes the result where your cursor is. "
                    "It works in terminals, code editors, mail, chat and browsers.",
     "layout": "split", "side": "right",
     "bullets": [
         "Hold-to-talk on Right Control, or double-tap it for hands-free dictation (10-minute limit by default)",
         "Cleans up \"um\", repeats and self-corrections like \"Friday, no, Thursday\"",
         "Paste raw text instead, or redo the last dictation in the other language, with one shortcut",
         "Command key: select text, hold Right Option and say how to change it",
         "Live preview shows your last words under the recording indicator while you speak",
     ],
     "media": {"pictures": ["01-hero.png"]}},
    {"background": "tint", "kicker": "Meetings",
     "title": "Record a call and get the transcript, summary and to-dos",
     "description": "BugVoice records your microphone and the call audio on your Mac. It tells the voices "
                    "apart, writes a transcript you can click to replay, then a summary and action items "
                    "with owners. Uploaded audio and video files get the same treatment.",
     "layout": "showcase",
     "tiles": [
         {"title": "Transcript with speakers", "caption": "Voices are split on your Mac. Name a speaker once and BugVoice can suggest them next time.", "picture": "02-meeting-transcript.png"},
         {"title": "Summary and decisions", "caption": "A short summary from your chosen text model. Regenerate it or send it to the Scratchpad.", "picture": "03-meeting-summary-dark.png"},
         {"title": "English under each line", "caption": "Turn on Show English to read a translation under every Vietnamese or Spanish line.", "picture": "04-meeting-translation.png"},
         {"title": "One list of action items", "caption": "Open items from all meetings, filtered by owner and date. Tick them off or copy the open ones.", "picture": "05-action-items.png"},
     ]},
    {"background": "plain", "kicker": "Writes the way you do",
     "title": "Your words, your tone, your languages",
     "description": "Each app belongs to a style, so a Slack message stays short and an email keeps its "
                    "greeting. Teach BugVoice the names it gets wrong. Speak English, Vietnamese, Spanish "
                    "or a mix, and set a language per app.",
     "layout": "split", "side": "left",
     "bullets": [
         "Six styles (personal, work, email, document, terminal, other) with a tone you can edit",
         "Dictionary words with \"heard as\" fixes, plus snippets that expand a spoken phrase",
         "Suggests new Dictionary words when you correct a pasted word by hand",
         "Reads file and symbol names from your code folders so coding prompts get them right",
         "Keeps English technical words inside Vietnamese and Spanish sentences",
     ],
     "media": {"pictures": ["09-styles.png", "08-dictionary.png"]}},
    {"background": "tint", "kicker": "Your library",
     "title": "Notes, history and stats in one window",
     "description": "Everything you dictate, record or write is kept in a searchable library with folders "
                    "and tags. Ask a question across your notes and meetings and get an answer with links "
                    "to the exact passage.",
     "layout": "showcase",
     "tiles": [
         {"title": "Scratchpad", "caption": "A floating note window you can dictate into, with Polish, More concise and More professional rewrites.", "picture": "07-scratchpad.png"},
         {"title": "Insights", "caption": "Words spoken, words per minute, streaks and an estimate of time saved against typing.", "picture": "06-insights.png"},
         {"title": "Languages and models", "caption": "Pick the speech model and the languages you speak. Each language shows up in the menu switch.", "picture": "10-languages.png"},
     ]},
    {"background": "dark", "kicker": "How it works",
     "title": "From your voice to text in about two seconds",
     "description": "Four steps run every time you release the key. Speech recognition happens on your Mac; "
                    "cleanup goes to the text model you picked.",
     "layout": "cards", "numbered": True,
     "cards": [
         {"title": "Hold and speak", "text": "Hold Right Control in any app. BugVoice notes which app you are in and picks its style and language."},
         {"title": "Transcribe on device", "text": "WhisperKit turns the audio into text on your Mac, using your Dictionary words as hints."},
         {"title": "Clean up", "text": "Your text model removes fillers and applies the app's tone. If it is slow or off, the raw text is used."},
         {"title": "Paste at the cursor", "text": "The text is pasted where you were typing and your clipboard is put back. Secure fields are never filled."},
     ]},
    {"background": "plain", "kicker": "Local-first",
     "title": "Built to keep your voice on your Mac",
     "description": "BugVoice has no account and no BugVoice server. What leaves your Mac depends only on the "
                    "connections you set up yourself.",
     "layout": "cards", "numbered": False,
     "cards": [
         {"title": "On-device speech", "text": "Speech-to-text and speaker separation run locally with Core ML models downloaded once from Hugging Face."},
         {"title": "Your choice of text model", "text": "Use a local server (oMLX, LM Studio, Ollama, MLX), Apple Intelligence, or a cloud API key if you add one."},
         {"title": "Plain files you own", "text": "Notes are Markdown files and history is JSON, in a folder on your Mac. Back up to any folder, daily or weekly."},
         {"title": "Works with your tools", "text": "Apple Shortcuts actions, and an optional MCP server so coding agents can read and add notes. Off by default."},
     ]},
]

FAQ = [
    ("What is BugVoice?",
     "BugVoice is a menu bar app for macOS that turns speech into clean text. Hold Right Control, speak and release; the text is pasted at your cursor in any app. It also records and transcribes meetings, keeps notes in a floating Scratchpad, and shows stats about how much you dictate."),
    ("Who is it for?",
     "People who write all day on a Mac and would rather talk: developers prompting coding agents in a terminal, people answering email and chat, and anyone who takes meeting notes. It handles English, Vietnamese and Spanish, including sentences that mix English technical words into Vietnamese or Spanish."),
    ("What do I need to run it?",
     "A Mac with Apple Silicon (M1 or later) running macOS 15 Sequoia or later. The default speech model is a 1.6 GB download on first use; a 0.5 GB model is available for smaller Macs. For text cleanup you need a local model server such as oMLX, LM Studio or Ollama, Apple Intelligence, or an API key for a cloud model. Without one, BugVoice pastes the raw transcript."),
    ("How much does it cost?",
     "PRICE AND LICENCE: to be confirmed by the owner before publishing."),
    ("Where is my data stored? Does anything go to the cloud?",
     "Everything is stored in ~/Library/Application Support/BugVoice on your Mac: settings, history, notes (Markdown files), meetings and their audio. Speech recognition runs on your Mac. Text is sent only to the text model you configure; if that is a local server, nothing leaves your Mac. API keys are kept in a file only your user can read. The app downloads speech models from Hugging Face once."),
    ("Does it sync between Macs or work offline?",
     "There is no sync and no account. With a local text model, dictation and meetings work fully offline once the speech model is downloaded. To move your library, use Settings, Storage, Backup to write an archive to any folder, then Restore it on the other Mac."),
    ("How do I install and update it?",
     "Download the DMG and drag BugVoice to Applications. The app is not notarized by Apple, so the first time macOS blocks it: open System Settings, Privacy & Security, and click Open Anyway. BugVoice then asks for Microphone, Accessibility and Input Monitoring so it can hear you, paste text and see the hotkey. To update, replace the app with the new version; your library stays where it is."),
    ("Can I import audio or export my meetings and notes?",
     "Yes. The Upload page transcribes MP3, WAV, M4A, AIFF, CAF, MP4, MOV and M4V files into a meeting with timestamps. Each meeting can be exported as Markdown, SubRip captions or audio. Notes are plain Markdown files you can open in any editor."),
    ("How is it different from macOS Dictation?",
     "macOS Dictation types what you say. BugVoice also cleans up fillers and self-corrections, adapts the tone to each app, learns your words, keeps a searchable history, and adds meeting recording with summaries and action items. You choose the speech and text models."),
    ("Can coding agents use it?",
     "BugVoice can run an MCP server that lets agents such as Claude Code read and search your notes and meetings, create notes and upload recordings. It is off by default; turn it on in Settings, Agents, where you also choose whether agents may edit notes or upload files."),
    ("How do I report a bug?",
     "BUG REPORT CHANNEL: to be confirmed by the owner. Settings, Storage, Copy diagnostics copies the app version, model names and this session's log (never your dictated text) so you can paste it into a report."),
]

RELEASE = {
    "version": "0.1.0 (build 306)",
    "whats_new": [
        "Spanish dictation alongside English and Vietnamese, with Spanish cleanup rules",
        "Live preview shows your words under the recording indicator while you speak",
        "Apple Shortcuts actions: record meetings, transcribe files, rewrite text, new note",
        "Action items page collects to-dos from every meeting, with owners and filters",
        "Learns from corrections: fix a pasted word and BugVoice offers to add it",
        "Backup and restore of the whole library, by hand or daily and weekly",
    ],
}

QUESTIONS = [
    "Price: free, paid, or pay-what-you-want? The FAQ price answer is a placeholder.",
    "Licence: open source (which licence) or closed? The repo has no LICENSE file.",
    "Distribution: where will the DMG be hosted, and is the FAQ right that builds are not notarized (signed only with the local \"Bugler Local Dev\" identity)?",
    "Updates: is there any update check, or only manual replacement? I found no updater in the code.",
    "Bug reports: email, GitHub issues or a form? The FAQ bug answer is a placeholder.",
    "Version: is 0.1.0 (build 306) the number to publish? Is Spanish in the public build?",
    "Apple Silicon only? build-app.sh builds arm64 only; confirm there is no Intel build.",
    "Should the page name third-party products (oMLX, LM Studio, Ollama, Claude Code, macOS Dictation)?",
    "Pronunciation \"BUG-voice\" is my guess.",
]

# ---------- limits ----------
problems = []
def check(label, text, limit, minimum=0):
    n = len(text)
    if n > limit or n < minimum: problems.append(f"{label}: {n} chars (allowed {minimum}-{limit})")
    for w in BANNED:
        if w in text.lower(): problems.append(f"{label}: banned word '{w}'")
    return n

check("summary", CATALOG["summary"], 200)
check("details", CATALOG["details"], 600, 300)
check("requirements", CATALOG["requirements"], 80)
tags = [t.strip() for t in CATALOG["tags"].split(",")]
if not 3 <= len(tags) <= 6: problems.append(f"tags: {len(tags)} (allowed 3-6)")
for f, lab in SCREENSHOTS:
    check(f"label {f}", lab, 60)
    p = os.path.join(SHOTS, f)
    if not os.path.exists(p): problems.append(f"missing screenshot {f}")
    elif os.path.getsize(p) > 12 * 1024 * 1024: problems.append(f"{f} over 12 MB")
if not 3 <= len(FEATURES) <= 6: problems.append("features: need 3-6 sections")
names = {f for f, _ in SCREENSHOTS}
for i, s in enumerate(FEATURES, 1):
    k = f"section {i}"
    check(f"{k} kicker", s["kicker"], 40); check(f"{k} title", s["title"], 70); check(f"{k} description", s["description"], 320)
    if s["layout"] == "split":
        if len(s["bullets"]) > 5: problems.append(f"{k}: more than 5 bullets")
        for j, b in enumerate(s["bullets"], 1): check(f"{k} bullet {j}", b, 120)
        pics = s["media"]["pictures"]
        if not 1 <= len(pics) <= 2: problems.append(f"{k}: needs 1-2 pictures")
        for p in pics:
            if p not in names: problems.append(f"{k}: unknown picture {p}")
    elif s["layout"] == "showcase":
        if not 2 <= len(s["tiles"]) <= 4: problems.append(f"{k}: needs 2-4 tiles")
        for j, t in enumerate(s["tiles"], 1):
            check(f"{k} tile {j} title", t["title"], 40); check(f"{k} tile {j} caption", t["caption"], 120)
            if t["picture"] not in names: problems.append(f"{k}: unknown picture {t['picture']}")
    elif s["layout"] == "cards":
        if not 2 <= len(s["cards"]) <= 6: problems.append(f"{k}: needs 2-6 cards")
        for j, c in enumerate(s["cards"], 1):
            check(f"{k} card {j} title", c["title"], 40); check(f"{k} card {j} text", c["text"], 200)
for a, b in zip(FEATURES, FEATURES[1:]):
    if a["background"] == b["background"]: problems.append(f"backgrounds repeat: {a['kicker']} / {b['kicker']}")
if not 6 <= len(FAQ) <= 12: problems.append("faq: need 6-12 items")
for i, (q, a) in enumerate(FAQ, 1):
    check(f"faq {i} question", q, 120); check(f"faq {i} answer", a, 600)
if not 3 <= len(RELEASE["whats_new"]) <= 6: problems.append("release: need 3-6 bullets")

# ---------- outputs ----------
def c(text, limit=None): return f"`{len(text)}{'/' + str(limit) if limit else ''}`"

md = [f"# {CATALOG['name']} — product page copy", "",
      "Generated by `build_page.py`; edit the script, not this file. Counts are characters / limit.", "",
      "## Catalog fields", "",
      f"- **Name:** {CATALOG['name']}",
      f"- **Pronunciation:** {CATALOG['pronunciation']} (unconfirmed)",
      f"- **Summary / tagline** {c(CATALOG['summary'], 200)}: {CATALOG['summary']}",
      f"- **Details** {c(CATALOG['details'], 600)}: {CATALOG['details']}",
      f"- **Category:** {CATALOG['category']}",
      f"- **Tags** ({len(tags)}): {CATALOG['tags']}",
      f"- **Platform / OS:** {CATALOG['platform']}",
      f"- **License:** {CATALOG['license']}",
      f"- **Requirements** {c(CATALOG['requirements'], 80)}: {CATALOG['requirements']}",
      f"- **Accent colour:** `{CATALOG['accent']}` (red of the app icon, `App/Icon/AppIcon.svg`)", "",
      "## Screenshots", "",
      "Window-only captures, 2880 × 1800 px (1440 × 900 pt at 2x), PNG, no shadow, fictional demo library.", ""]
for f, lab in SCREENSHOTS:
    md.append(f"- `screenshots/{f}` {c(lab, 60)}: {lab}")
md += ["", "No clip: recording the core workflow needs a real hotkey dictation that pastes into the frontmost app, which I did not run while you were at the Mac.", "",
       "## Feature sections", ""]
for i, s in enumerate(FEATURES, 1):
    md += [f"### {i}. {s['kicker']}", "",
           f"- **Layout:** {s['layout']}" + (" (numbered)" if s.get("numbered") else "") + f" · **Background:** {s['background']}" + (f" · **Side:** {s['side']}" if "side" in s else ""),
           f"- **Kicker** {c(s['kicker'], 40)}: {s['kicker']}",
           f"- **Title** {c(s['title'], 70)}: {s['title']}",
           f"- **Description** {c(s['description'], 320)}: {s['description']}"]
    if s["layout"] == "split":
        md.append("- **Bullets:**")
        md += [f"  - {c(b, 120)} {b}" for b in s["bullets"]]
        md.append(f"- **Media:** {', '.join(s['media']['pictures'])}")
    elif s["layout"] == "showcase":
        md.append("- **Tiles:**")
        md += [f"  - **{t['title']}** {c(t['title'], 40)} — {t['caption']} {c(t['caption'], 120)} — `{t['picture']}`" for t in s["tiles"]]
    else:
        md.append(f"- **Cards** (numbered: {'yes' if s['numbered'] else 'no'}):")
        md += [f"  - **{x['title']}** {c(x['title'], 40)} — {x['text']} {c(x['text'], 200)}" for x in s["cards"]]
    md.append("")
md += ["## FAQ", ""]
for i, (q, a) in enumerate(FAQ, 1):
    md += [f"**{i}. {q}** {c(q, 120)}", "", f"{a} {c(a, 600)}", ""]
md += ["## Release note", "", f"**Version {RELEASE['version']}**", "", "What's new:", ""]
md += [f"- {b}" for b in RELEASE["whats_new"]]
md += ["", "## Questions for owner", ""] + [f"- {q}" for q in QUESTIONS] + [""]

with open(os.path.join(HERE, "BugVoice-page.md"), "w") as f: f.write("\n".join(md))
with open(os.path.join(HERE, "BugVoice-sections.json"), "w") as f:
    json.dump({"requirements": CATALOG["requirements"], "features": FEATURES,
               "faq": [{"question": q, "answer": a} for q, a in FAQ]}, f, indent=2, ensure_ascii=False)
    f.write("\n")

if problems:
    print("LIMIT PROBLEMS:"); [print(" -", p) for p in problems]; sys.exit(1)
print(f"OK: {len(FEATURES)} sections, {len(FAQ)} FAQ, {len(SCREENSHOTS)} screenshots, all limits pass")
