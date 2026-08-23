#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_dir/.." && pwd -P)"
clean=0
[[ "${1:-}" == '--clean' ]] && clean=1 && shift
[[ $# -eq 0 ]] || { echo "Unknown argument: $1" >&2; exit 2; }
command -v osascript >/dev/null 2>&1 || { echo 'osascript is required to parse the plugin manifest.' >&2; exit 1; }
plugin_name="$(MANIFEST_PATH="$repo_root/.codex-plugin/plugin.json" osascript -l JavaScript <<'JXA'
ObjC.import('Foundation');
const raw = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError($.getenv('MANIFEST_PATH'), $.NSUTF8StringEncoding, null));
console.log(String(JSON.parse(raw.replace(/^\uFEFF/, '')).name));
JXA
)"
[[ "$plugin_name" =~ ^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*$ ]] || { echo "Invalid plugin name in manifest: $plugin_name" >&2; exit 1; }
packages_root="$repo_root/plugins"
package_root="$packages_root/$plugin_name"
marker="$package_root/.generated-by-codex-obsidian-knowledge"
[[ "$package_root" == "$repo_root/plugins/"* ]] || { echo 'Generated package path escaped the repository plugins directory.' >&2; exit 1; }

if [[ "$clean" -eq 1 ]]; then
  if [[ -e "$package_root" ]]; then [[ -f "$marker" ]] || { echo "Refusing to clean unmanaged path: $package_root" >&2; exit 1; }; rm -rf -- "$package_root"; fi
  echo 'Generated plugin package cleaned.'
  exit 0
fi

mkdir -p "$packages_root"
staging_root="$(mktemp -d "$packages_root/.staging.XXXXXX")"
backup_root="$packages_root/.backup.$RANDOM.$RANDOM"
cleanup() { [[ -d "$staging_root" ]] && rm -rf -- "$staging_root"; }
trap cleanup EXIT
for directory in .codex-plugin assets skills templates scripts docs; do cp -R "$repo_root/$directory" "$staging_root/$directory"; done
for file in README.md PRIVACY.md SECURITY.md LICENSE CHANGELOG.md; do cp "$repo_root/$file" "$staging_root/$file"; done
printf '%s\n' 'generated from repository root' > "$staging_root/.generated-by-codex-obsidian-knowledge"
if [[ -e "$package_root" ]]; then
  [[ -f "$marker" ]] || { echo "Plugin package path exists and is unmanaged: $package_root" >&2; exit 1; }
  mv "$package_root" "$backup_root"
fi
if ! mv "$staging_root" "$package_root"; then
  [[ -e "$backup_root" ]] && mv "$backup_root" "$package_root"
  exit 1
fi
[[ -e "$backup_root" ]] && rm -rf -- "$backup_root"
echo "Generated plugin package: $package_root"
