#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
MANIFEST_PATH=""; PROJECT_ID=""; FEATURE_ID=""; THREAD_ID='unknown'; SOURCE_COMMIT='unknown'
while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST_PATH="${2:?Missing value for --manifest}"; shift 2 ;;
    --project) PROJECT_ID="${2:?Missing value for --project}"; shift 2 ;;
    --feature) FEATURE_ID="${2:?Missing value for --feature}"; shift 2 ;;
    --thread) THREAD_ID="${2:?Missing value for --thread}"; shift 2 ;;
    --source-commit) SOURCE_COMMIT="${2:?Missing value for --source-commit}"; shift 2 ;;
    -h|--help) echo 'Usage: new-evidence-identity.sh --manifest evidence.json --project project-id --feature feature-id [--thread id] [--source-commit sha]'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
[[ -f "$MANIFEST_PATH" ]] || { echo 'Evidence manifest is required.' >&2; exit 2; }
[[ "$PROJECT_ID" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || { echo 'Project ID must be a lowercase safe slug.' >&2; exit 2; }
[[ "$FEATURE_ID" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || { echo 'Feature ID must be a lowercase safe slug.' >&2; exit 2; }
[[ "$SOURCE_COMMIT" == 'unknown' || "$SOURCE_COMMIT" =~ ^[0-9a-fA-F]{7,64}$ ]] || { echo 'Source commit must be a Git object ID or unknown.' >&2; exit 2; }
command -v osascript >/dev/null 2>&1 || { echo 'osascript is required.' >&2; exit 1; }
command -v shasum >/dev/null 2>&1 || { echo 'shasum is required.' >&2; exit 1; }

temporary="$(mktemp "${TMPDIR:-/tmp}/codex-evidence.XXXXXX")"
cleanup() { rm -f -- "$temporary"; }
trap cleanup EXIT
MANIFEST_PATH="$MANIFEST_PATH" CANONICAL_PATH="$temporary" osascript -l JavaScript <<'JXA'
ObjC.import('Foundation');
const source = $.getenv('MANIFEST_PATH');
const target = $.getenv('CANONICAL_PATH');
const raw = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(source, $.NSUTF8StringEncoding, null));
const entropy = (text) => {
  const counts = {};
  for (const character of text) counts[character] = (counts[character] || 0) + 1;
  return Object.values(counts).reduce((sum, count) => {
    const probability = count / text.length;
    return sum - probability * Math.log2(probability);
  }, 0);
};
const sensitivePatterns = [
  /-----BEGIN [A-Z0-9 ]+ PRIVATE KEY-----/,
  /\bAuthorization\s*:\s*Bearer\s+(?!\[REDACTED\]|<[^>]+>|\$[A-Za-z_][A-Za-z0-9_]*|\{[^}]+\})\S+/i,
  /\b(api[_-]?key|access[_-]?key|secret|password|passwd|token|cookie|private[_-]?key)\s*[:=]\s*["'`]?(?!\[REDACTED\])([A-Za-z0-9_./+=-]{12,})/i,
  /\b(AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,})\b/,
  /\bsk-(?:(?:proj|ant)-)?[A-Za-z0-9_-]{20,}\b/,
  /https?:\/\/[^\s/@:]+:[^\s/@]+@/i
];
const scanValue = (value, key = '') => {
  if (Array.isArray(value)) return value.forEach((item) => scanValue(item, key));
  if (value && typeof value === 'object') {
    return Object.keys(value).forEach((childKey) => scanValue(value[childKey], childKey));
  }
  if (typeof value !== 'string') return;
  if (sensitivePatterns.some((pattern) => pattern.test(value))) throw new Error('Sensitive-looking evidence must be redacted before hashing.');
  if (!/(sha-?256|checksum|digest|commit|content[-_ ]?hash)/i.test(key)) {
    const urls = [];
    const urlPattern = /https?:\/\/\S+/ig;
    let urlMatch;
    while ((urlMatch = urlPattern.exec(value)) !== null) urls.push([urlMatch.index, urlMatch.index + urlMatch[0].length]);
    const tokenPattern = /(?<![A-Za-z0-9+/=_-])[A-Za-z0-9+/=_-]{32,}(?![A-Za-z0-9+/=_-])/g;
    let tokenMatch;
    while ((tokenMatch = tokenPattern.exec(value)) !== null) {
      const token = tokenMatch[0];
      const following = value.slice(tokenMatch.index + token.length);
      const relativeFile = /^(?:[A-Za-z0-9_-]+\/)+[A-Za-z0-9_-]+$/.test(token) && /^\.[A-Za-z0-9]{1,10}(?:\b|$)/.test(following);
      const urlPath = urls.some(([start, end]) => tokenMatch.index >= start && tokenMatch.index + token.length <= end);
      if (!/^(REDACTED|YOUR[_-]|EXAMPLE[_-]|PLACEHOLDER[_-])/i.test(token) && !relativeFile && !urlPath && entropy(token) >= 4.2) {
        throw new Error('High-entropy evidence must be reviewed and redacted before hashing.');
      }
    }
  }
};
const unorderedArrayKeys = new Set(['files', 'tests']);
const sortValue = (value, key = '') => {
  if (Array.isArray(value)) {
    const items = value.map((item) => sortValue(item));
    if (unorderedArrayKeys.has(key)) items.sort((left, right) => {
      const leftKey = JSON.stringify(left);
      const rightKey = JSON.stringify(right);
      return leftKey < rightKey ? -1 : leftKey > rightKey ? 1 : 0;
    });
    return items;
  }
  if (value && typeof value === 'object') {
    const result = {};
    Object.keys(value).sort().forEach((childKey) => { result[childKey] = sortValue(value[childKey], childKey); });
    return result;
  }
  if (typeof value === 'string') return value.replace(/\r\n?/g, '\n');
  return value;
};
const parsed = JSON.parse(raw.replace(/^\uFEFF/, ''));
scanValue(parsed);
const canonical = JSON.stringify(sortValue(parsed));
if (!$.NSString.stringWithString(canonical).writeToFileAtomicallyEncodingError(target, true, $.NSUTF8StringEncoding, null)) throw new Error('Could not write canonical evidence');
JXA
hash="$(shasum -a 256 "$temporary" | awk '{print $1}')"; prefix="${hash:0:16}"
safe_thread="$(printf '%s' "$THREAD_ID" | sed -E 's/[^A-Za-z0-9._-]+/-/g; s/^-+|-+$//g')"; [[ -n "$safe_thread" ]] || safe_thread='unknown'
source_commit="$(printf '%s' "$SOURCE_COMMIT" | tr '[:upper:]' '[:lower:]')"
if [[ "$safe_thread" != 'unknown' ]]; then capture_id="codex:$safe_thread:$PROJECT_ID:$FEATURE_ID:$prefix"
elif [[ "$source_commit" != 'unknown' ]]; then capture_id="$PROJECT_ID:$FEATURE_ID:$source_commit:$prefix"
else capture_id="$PROJECT_ID:$FEATURE_ID:$prefix"; fi
printf '{"capture_id":"%s","evidence_hash":"%s","source_commit":"%s"}\n' "$capture_id" "$hash" "$source_commit"
