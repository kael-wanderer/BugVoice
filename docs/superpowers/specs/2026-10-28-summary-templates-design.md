# Summary templates

Decision: preserve General's existing prompt byte for byte, including its existing factuality instruction; the other templates explicitly prohibit invented owners and deadlines. This resolves the plan's request for both unchanged General and an explicit no-invention rule.

Templates use stable ids and version 1: general, technical-design, stand-up, interview. General remains the default and old meetings read as General. Store the id and version used to generate a summary on the manifest; choosing a template does not regenerate until Generate or Regenerate is pressed.

For summaries other than General append these exact instructions to the existing summary instruction:

- Technical design: “Use Markdown sections: decisions, options considered, open questions, and risks. Do not invent owners or deadlines; leave missing owners and deadlines unspecified.”
- Stand-up: “Use Markdown sections per person: done, next, and blocked. Do not invent owners or deadlines; leave missing owners and deadlines unspecified.”
- Interview: “Use Markdown sections: candidate, topics, strengths, concerns, and follow-ups. Do not invent owners or deadlines; leave missing owners and deadlines unspecified.”

For My notes, retain the existing instruction: “Follow the user's notes: keep their headings and order; fill in details from the transcript.” The notes lead, and the template shapes sections around them. Apply the template to part and merge prompts without changing chunk budgets or cancellation. Action items remain unchanged.

Owner check: regenerate a real meeting with each template; confirm facts match the transcript and no owners or dates were invented.
