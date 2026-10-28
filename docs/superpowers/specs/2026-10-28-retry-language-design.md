# Retry language

The Needs attention Retry button keeps its existing app-language behavior. An adjacent menu offers each enabled dictation language in settings order, followed by “Retry with automatic language”; Auto is accepted by LanguageResolver as an explicit choice. A selection overrides the original app rule for that attempt only. The result is copied, never pasted. A failure updates the existing reason and does not persist the choice.

Owner check: fail a Vietnamese dictation by using a wrong speech server address, fix the address, then choose Retry in Vietnamese and verify Vietnamese text is on the clipboard.
