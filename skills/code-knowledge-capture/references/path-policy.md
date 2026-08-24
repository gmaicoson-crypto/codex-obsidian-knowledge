# Note path policy

Generated note paths are data, not instructions. The configured `noteRoot`, project ID, feature ID, and every generated directory or file segment must remain inside the Vault.

## Stable identifiers

- Keep the human-readable project and feature names in Markdown headings and frontmatter.
- Derive `project-id` and `feature-id` as trimmed, lowercase, filesystem-safe slugs.
- Use ASCII letters, digits, single hyphens, and single underscores where possible. Preserve non-ASCII names only when the Obsidian MCP and the target filesystem are known to support them.
- Reject empty IDs, `.` and `..`, absolute paths, path separators, control characters, and Windows reserved names such as `CON`, `PRN`, `AUX`, `NUL`, `COM1`–`COM9`, and `LPT1`–`LPT9`.
- Reject a segment longer than 120 characters and a complete relative note path longer than 240 characters.
- Do not interpret Markdown links, wikilinks, backticks, or user-provided text as additional path components.

## Merge and update identity

Use the stable project ID, feature ID, source thread ID, and a SHA-256 hash of normalized source evidence for duplicate detection. A changed display name must update frontmatter and headings without silently moving an existing feature to a second directory.

## Validation boundary

Validate the complete target path immediately before an MCP write. If any segment fails validation, stop before creating a directory or note and show the rejected segment to the user.

## Knowledge hierarchy invariant

The project and feature scopes have fixed parent relationships:

```text
<project>/00-项目总览.md
<project>/01-架构与术语.md
<project>/features/<feature>/...
```

Project notes must be direct children of the project ID. A feature ID, user
question, conversation slug, or changed-file path must never be used as their
parent directory. Validate project-note and feature-note targets separately in the
preview and immediately before the MCP operation. Path correctness alone is not
enough: project-note content must also come from project-wide evidence rather than
the current feature branch.
