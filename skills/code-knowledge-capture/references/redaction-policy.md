# Sensitive-content redaction policy

The preview is not safe merely because it contains `[REDACTED]` in a sentence. Scan the actual candidate Markdown immediately before every write.

## Always remove

- API keys, bearer tokens, OAuth refresh tokens, cookies, session IDs, passwords, private keys, seed phrases, and connection strings.
- Authorization headers and environment-variable values whose names contain `KEY`, `TOKEN`, `SECRET`, `PASSWORD`, `COOKIE`, or `PRIVATE`.
- Personal identifiers that were not explicitly requested for retention.
- Local REST API credentials, even when they are only being recorded as code examples.

Replace the value with `[REDACTED]`; keep only the credential type and the fact that it was used when that fact is relevant.

## Detection checklist

Before writing, inspect fenced code blocks, frontmatter, links, tables, and filenames for:

- `Authorization: Bearer`, `api[_-]?key`, `secret`, `password`, `token`, `cookie`, and private-key markers;
- PEM blocks such as `-----BEGIN ... PRIVATE KEY-----`;
- common cloud key prefixes and long hexadecimal/base64 strings;
- environment-variable assignments and URLs containing embedded credentials.

If a candidate still contains a likely secret or an unreviewed high-entropy value, do not write it. Ask for a revised preview or explicit confirmation after redaction; never print the detected value in the error message.
