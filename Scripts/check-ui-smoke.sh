#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: Scripts/check-ui-smoke.sh SIMULATOR_UDID [all|regular|largest-ax]

Run the Piano UI smoke plan on the explicitly selected iPhone, iPad, or iPhone Duo
simulator. The script does not boot, erase, or select another simulator.

Optional environment:
  PIANOFLOW_UI_SMOKE_OUTPUT_DIR  Result directory outside the repository
  PIANOFLOW_SPM_PACKAGES_DIR     Existing or writable Swift package cache
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 2
fi

simulator_udid=$1
mode=${2:-all}
if [[ ! $simulator_udid =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
  printf 'Expected an explicit simulator UDID, received: %s\n' "$simulator_udid" >&2
  usage
  exit 2
fi

case $mode in
  all|regular|largest-ax) ;;
  *) usage; exit 2 ;;
esac

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
output_base=${PIANOFLOW_UI_SMOKE_OUTPUT_DIR:-${TMPDIR:-/tmp}/PianoFlowUISmoke}
mkdir -p "$output_base"
output_base=$(cd "$output_base" && pwd -P)
case $output_base in
  "$project_root"|"$project_root"/*)
    printf 'UI smoke output must be outside the repository: %s\n' "$output_base" >&2
    exit 2
    ;;
esac

run_dir=$(mktemp -d "$output_base/ui-smoke.XXXXXXXX")
build_arguments=(
  -project "$project_root/Piano.xcodeproj"
  -scheme PianoUISmoke
  -testPlan PianoUISmoke
  -configuration Debug
  -destination "platform=iOS Simulator,id=$simulator_udid"
  -derivedDataPath "$run_dir/DerivedData"
  -resultBundlePath "$run_dir/PianoUISmoke.xcresult"
  -parallel-testing-enabled NO
  -collect-test-diagnostics never
  -test-timeouts-enabled YES
  -default-test-execution-time-allowance 180
  -maximum-test-execution-time-allowance 240
  CODE_SIGN_IDENTITY=-
  CODE_SIGNING_ALLOWED=YES
  CODE_SIGNING_REQUIRED=NO
)

if [[ -n ${PIANOFLOW_SPM_PACKAGES_DIR:-} ]]; then
  build_arguments+=(-clonedSourcePackagesDirPath "$PIANOFLOW_SPM_PACKAGES_DIR")
fi

case $mode in
  regular) build_arguments+=(-only-test-configuration Regular) ;;
  largest-ax) build_arguments+=(-only-test-configuration 'Largest AX') ;;
esac

printf 'UI smoke destination: %s\n' "$simulator_udid"
printf 'UI smoke configurations: %s\n' "$mode"
printf 'Results: %s\n' "$run_dir/PianoUISmoke.xcresult"

cd "$project_root"
xcodebuild "${build_arguments[@]}" test 2>&1 | tee "$run_dir/xcodebuild.log"
