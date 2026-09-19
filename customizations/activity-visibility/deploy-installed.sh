#!/usr/bin/env bash
# Deploy the activity-visibility hotpatch onto an INSTALLED dsh 0.1.0-rc.6
# (no source build). Verifies the target files are pristine (sha256), backs
# them up, installs the patched copies, and re-verifies the patched hashes.
#
#   bash deploy-installed.sh                 # auto-detect: $(npm root -g)/@deepseek-ai/dsh
#   DSH_PKG=/path/to/dsh bash deploy-installed.sh
#
# Revert: the backup path printed at the end; cp those files back, or
# `npm install -g @deepseek-ai/dsh@0.1.0-rc.6 --force`.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DSH="${DSH_PKG:-$(npm root -g)/@deepseek-ai/dsh}"
NM="$DSH/node_modules/@deepseek-ai"
[ -d "$NM" ] || { echo "FAIL: no dsh install at $DSH (set DSH_PKG=/path/to/dsh)"; exit 1; }

VER=$(node -p "require(process.argv[1]).version" "$DSH/package.json")
if [ "$VER" != "0.1.0-rc.6" ]; then
  echo "FAIL: expected dsh 0.1.0-rc.6, found $VER."
  echo "This kit is verified for rc.6 only. See README.md 'Future builds'."
  exit 1
fi

sha() { shasum -a 256 "$1" | awk '{print $1}'; }

# pristine sha256 (must match a fresh rc.6 install exactly)
WS_EXP=7579ea4578750df71309dcf4881cf588aced13cf8137273a2c308a29bceb6464
SB_EXP=b8f03724988d75954b88d1fbaecf7e0cd1bf5dd17b722f7cfeb65220f9de915b
WEB_EXP=19f3d90921204ef582573aef6b3d58f171b362e420e0b7d1fe0982c9dc5e9afe
SH_EXP=a40165a9916acf9c5710e440842c9a56bc472ae9991f37f4675a7664ae784d68
# patched sha256 (what success looks like)
WS_GOT=a88e398de2e7bc66f9558ca5bda279e9a0586eaa67f12b7fab4b93355cfbfebf
SB_GOT=b01e4fe687e3fef529a8f73bd9136ca7c475d1536498b0b3cf45259eb1e1bb90
WEB_GOT=9c84df25058233b04c363741863f5b205614bf61c8c211bf856f614a40f92d5c
SH_GOT=546593945656493cc18abfcdb1d96b3a224717d1c3ab562885c6a78033bb1456

# the served Vite shell asset keeps a build-specific name:
SHELL_NAME=$(basename "$(ls "$NM/dsh-web-frontend/dist/assets/"index-*.js | head -1)")
[ -n "$SHELL_NAME" ] || { echo "FAIL: no assets/index-*.js under dist"; exit 1; }
[ "$SHELL_NAME" = "index-Dqw48FrP.js" ] || echo "WARN: shell asset is $SHELL_NAME (expected index-Dqw48FrP.js for rc.6) — the sha256 gate below decides."

declare -a T=(
  "$NM/dsh-client-ui-workspace/lib/client.js|dsh-client-ui-workspace__client.js|$WS_EXP|$WS_GOT|activityMeta"
  "$NM/dsh-client-ui-sidebar/lib/client.js|dsh-client-ui-sidebar__client.js|$SB_EXP|$SB_GOT|activityPill"
  "$NM/dsh-client-web/lib/index.js|dsh-client-web__index.js|$WEB_EXP|$WEB_GOT|activeCount"
  "$NM/dsh-web-frontend/dist/assets/$SHELL_NAME|shell__index-Dqw48FrP.js|$SH_EXP|$SH_GOT|active) "
)

BK="$HOME/dsh-activity-backup/pre-deploy-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BK"
echo "backup dir: $BK"

APPLIED=0
for row in "${T[@]}"; do
  IFS='|' read -r target src exp got marker <<< "$row"
  [ -f "$target" ] || { echo "FAIL: missing $target"; exit 1; }
  if grep -qF "$marker" "$target" && [ "$(sha "$target")" = "$got" ]; then
    echo "skip (already patched): $(basename "$(dirname "$(dirname "$target")")")/$src"; continue
  fi
  actual=$(sha "$target")
  if [ "$actual" != "$exp" ]; then
    echo "FAIL: $target sha256 mismatch."
    echo "  expected pristine $exp"
    echo "  actual           $actual"
    echo "Tree is not a pristine rc.6 file — refusing to overwrite. See README 'Future builds'."
    exit 1
  fi
  cp "$target" "$BK/$(basename "${target%/*}")__$(basename "$target")" 2>/dev/null || cp "$target" "$BK/$src"
  cp "$HERE/installed/$src" "$target"
  if [ "$(sha "$target")" = "$got" ]; then echo "OK: $target"; APPLIED=$((APPLIED+1));
  else echo "FAIL: post-copy hash mismatch for $target"; exit 1; fi
done

echo
echo "Applied $APPLIED file(s). Restart dsh (or just hard-refresh: Cmd+Shift+R)."
echo "Smoke test:"
echo "  curl -s localhost:3080/plugins/@deepseek-ai/dsh-client-ui-workspace/client.js | grep -c activityMeta   # -> 3"
echo "  curl -s localhost:3080/plugins/@deepseek-ai/dsh-client-ui-sidebar/client.js   | grep -c activityPill   # -> 3"
echo "Revert: files in $BK (cp back to their paths), or npm i -g @deepseek-ai/dsh@0.1.0-rc.6 --force"
