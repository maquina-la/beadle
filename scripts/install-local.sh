#!/bin/bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP_BUNDLE="$PROJECT_ROOT/dist/Beads Status Bar.app"

"$PROJECT_ROOT/scripts/build-app.sh"
ditto "$APP_BUNDLE" "/Applications/Beads Status Bar.app"
open "/Applications/Beads Status Bar.app"
