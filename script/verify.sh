#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
case "${1:-}" in ""|--ios) ;; *) echo "Usage: $0 [--ios]" >&2; exit 2 ;; esac
MANIFEST="$(mktemp -t characterkit-manifest)"
trap 'rm -f "$MANIFEST"' EXIT
xcrun swift package dump-package > "$MANIFEST"
python3 - "$MANIFEST" <<'PY'
import json, sys
from pathlib import Path
package = json.loads(Path(sys.argv[1]).read_text())
assert len(package['products']) == 1 and package['products'][0]['name'] == 'ReactiveCharacterKit'
assert 'library' in package['products'][0]['type']
assert all(t['type'] != 'executable' for t in package['targets'])
assert not Path('Sources/CharacterChat').exists()
assert not any(Path('Tools').glob('*/Package.swift'))
PY
xcrun swift test
xcrun swift build -c release
if [[ "${1:-}" == --ios ]]; then
  CHARACTERKIT_IOS_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
  CHARACTERKIT_IOS_ARCH="$(uname -m)"
  xcrun swift build --scratch-path .build/ios-validation \
    --triple "${CHARACTERKIT_IOS_ARCH}-apple-ios16.0-simulator" --sdk "$CHARACTERKIT_IOS_SDK"
fi
