#!/usr/bin/env bash
set -euo pipefail
TIKDOG_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TIKDOG_ROOT"
mkdir -p .build-artifacts
swift test --package-path TikDogCore > .build-artifacts/release-core.log 2>&1
scripts/test_database.sh > .build-artifacts/release-database.log 2>&1
deno test --allow-env supabase/functions/_shared/*_test.ts > .build-artifacts/release-edge-tests.log 2>&1
deno check supabase/functions/apple-credentials/index.ts supabase/functions/delete-account/index.ts supabase/functions/delete-video/index.ts scripts/moderate.ts scripts/live_smoke.ts > .build-artifacts/release-deno.log 2>&1
python3 scripts/test_release_gate.py > .build-artifacts/release-gate-tests.log 2>&1
if [[ "${1:-}" != "--skip-ui" ]]; then
  if [[ -n "${TIKDOG_TEST_DESTINATION:-}" ]]; then
    TIKDOG_DESTINATION="$TIKDOG_TEST_DESTINATION"
  else
    TIKDOG_DESTINATION="$(python3 scripts/simulator_destination.py)"
  fi
  TIKDOG_RESULTS=".build-artifacts/Release-$(date -u +%Y%m%dT%H%M%SZ).xcresult"
  xcodebuild -project TikDog.xcodeproj -scheme TikDog -destination "$TIKDOG_DESTINATION" -derivedDataPath .build-artifacts/ReleaseSafety -resultBundlePath "$TIKDOG_RESULTS" -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO test > .build-artifacts/release-ui.log 2>&1
fi
# A blocked publication gate is reported honestly; it does not erase local test evidence.
if python3 scripts/check_release.py > .build-artifacts/release-preflight.log 2>&1; then
  echo 'PASS: local verification and configured public identity. Signed-device/live launch evidence is still required for archiving.'
else
  echo 'PASS: local verification. Publication is BLOCKED; see .build-artifacts/release-preflight.log.'
fi
