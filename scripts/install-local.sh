#!/bin/bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP_BUNDLE="$PROJECT_ROOT/dist/Beadle.app"

"$PROJECT_ROOT/scripts/build-app.sh"
ditto "$APP_BUNDLE" "/Applications/Beadle.app"
open "/Applications/Beadle.app"
