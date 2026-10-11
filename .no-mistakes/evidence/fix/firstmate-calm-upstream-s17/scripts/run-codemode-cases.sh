#!/usr/bin/env bash
# Run only the repository's Codemode rendering and TUI cases against the Pi package named by FM_PI_PACKAGE_DIR.
set -u
WT=/Users/nikunjkotecha/.no-mistakes/worktrees/2ee2211c408e/01M4M7NNF4YEM5TECNVZ0CXH4K
. "$WT/tests/lib.sh"
TMP_ROOT=$(fm_test_tmproot fm-calm-codemode-cases)
EXT="$ROOT/.pi/extensions/fm-calm.ts"
PI_PACKAGE_DIR=$FM_PI_PACKAGE_DIR
. "$ROOT/tests/assets/fm-calm-codemode.sh"

cleanup() {
  local status=0
  cleanup_codemode_e2e || status=1
  fm_test_cleanup
  [ "$status" -eq 0 ] || exit 1
}
trap cleanup EXIT

echo "pi on PATH: $(command -v pi) version $(pi --version)"
test_codemode_rendering
test_codemode_terminal_e2e
