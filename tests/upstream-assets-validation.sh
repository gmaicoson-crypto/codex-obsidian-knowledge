#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
metadata="$repo_root/scripts/upstream-assets.json"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-upstream-assets.XXXXXX")"
cleanup() { [[ "$temporary_dir" == "${TMPDIR:-/tmp}/codex-upstream-assets."* ]] && rm -rf -- "$temporary_dir"; }
trap cleanup EXIT

values_path="$temporary_dir/metadata-values.txt"
python3 - "$metadata" > "$values_path" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print(data["pluginId"])
print(data["version"])
print(data["releaseBase"])
for name in ("main.js", "manifest.json", "styles.css"):
    print(f"{name}\t{data['assets'][name]}")
PY
plugin_id="$(sed -n '1p' "$values_path")"; version="$(sed -n '2p' "$values_path")"; release_base="$(sed -n '3p' "$values_path")"
tail -n +4 "$values_path" | while IFS=$'\t' read -r name expected; do
  target="$temporary_dir/$name"
  curl --fail --location --silent --show-error --retry 3 "$release_base/$name" --output "$target"
  actual="$(shasum -a 256 "$target" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || { echo "SHA-256 mismatch for $name" >&2; exit 1; }
done
python3 - "$temporary_dir/manifest.json" "$plugin_id" "$version" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
assert manifest["id"] == sys.argv[2]
assert manifest["version"] == sys.argv[3]
PY
echo "Pinned upstream assets validated: $plugin_id $version"
