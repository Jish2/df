---
name: clean-pr-comments
description: >
  Strip comment slop from the current PR or diff. Use when the user
  invokes /clean-pr-comments, or asks to remove AI comments, banners,
  commented-out code, or restated-code comments before merge.
---

# Clean PR comments

Scope: the current PR diff against the base branch, plus uncommitted
changes in those files. If the user names files, use those instead.

Prefer a fresh subagent so it is not loyal to comments written earlier
in the session. Pass scope only.

Touch comments only. No refactors, renames, or extra files.

## Kill

- Comments that restate the next line or the identifier
- Narration, banners, section headers in code
- Commented-out code
- Workaround sermons and unproven `IMPORTANT` / `fine for now` / `too risky`

When unsure, delete the comment. Do not rewrite it shorter.

## Keep

- License / legal headers
- Non-obvious behavior forced by an external dependency, platform,
  vendor, or protocol this repo cannot change
- Formatter ignores such as `// prettier-ignore`
- Style-only or broken-rule lint suppressions
- Doc comments that are the public API contract
- Issue or RFC links that state a constraint code cannot express

Leave correctness/safety suppressions (`@ts-expect-error`,
`eslint-disable` for real rules, etc.) alone unless the user asked
to deal with them.

## Output

Apply the deletions. Report files touched, deletion count, and any
keeps with the keep-rule they matched.
