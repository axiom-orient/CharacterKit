#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
usage() {
  echo "Usage: $0 [--ios | --ios-test SIMULATOR_ID]"
}
ios_configuration=""
ios_simulator=""
case "$#:${1:-}" in
  0:) ;;
  1:--ios) ios_configuration=debug ;;
  1:--help) usage; exit 0 ;;
  2:--ios-test)
    [[ -n "$2" ]] || { usage >&2; exit 2; }
    ios_configuration=release
    ios_simulator="$2"
    ;;
  *) usage >&2; exit 2 ;;
esac
MANIFEST="$(mktemp -t characterkit-manifest)"
trap 'rm -f "$MANIFEST"' EXIT
xcrun swift package dump-package > "$MANIFEST"
python3 - "$MANIFEST" <<'PY'
import json, sys
from pathlib import Path
package = json.loads(Path(sys.argv[1]).read_text())
assert len(package['products']) == 1 and package['products'][0]['name'] == 'ReactiveCharacterKit'
assert 'library' in package['products'][0]['type']
assert package['products'][0]['targets'] == ['ReactiveCharacterKit']
assert {t['name']: t['type'] for t in package['targets']} == {
    'ReactiveCharacterKit': 'regular',
    'ReactiveCharacterKitTests': 'test',
}
PY
xcrun swift test
xcrun swift build -c release
if [[ -n "$ios_configuration" ]]; then
  CHARACTERKIT_IOS_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
  CHARACTERKIT_IOS_ARCH="$(uname -m)"
  xcrun swift build --scratch-path .build/ios-validation \
    --triple "${CHARACTERKIT_IOS_ARCH}-apple-ios16.0-simulator" --sdk "$CHARACTERKIT_IOS_SDK" \
    --configuration "$ios_configuration"
fi
if [[ -n "$ios_simulator" ]]; then
  xcrun xcodebuild -scheme CharacterKit -destination "platform=iOS Simulator,id=$ios_simulator" \
    -derivedDataPath .build/ios-tests -parallel-testing-enabled NO test
fi
