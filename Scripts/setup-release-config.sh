#!/bin/bash
set +x
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destination="${PIANOFLOW_RELEASE_CONFIG_PATH:-$repo_root/Piano/Config/Release.xcconfig}"

fail() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

[[ "$destination" = /* ]] || fail 'PIANOFLOW_RELEASE_CONFIG_PATH must be absolute.'
[[ ! -e "$destination" && ! -L "$destination" ]] || fail 'Release config already exists; it was not changed.'

# The setup inputs may come from local environment variables or CI secrets.
# Never put them in command arguments or diagnostic output.
export GADApplicationIdentifier="${PIANOFLOW_RELEASE_GAD_APP_ID-}"
export bannerViewAdUnitID="${PIANOFLOW_RELEASE_BANNER_AD_UNIT_ID-}"
export appOpenAdID="${PIANOFLOW_RELEASE_APP_OPEN_AD_UNIT_ID-}"
"$repo_root/Scripts/check-release-config.sh"

[[ -d "$(dirname "$destination")" ]] || fail 'Release config parent directory does not exist.'
umask 077
temporary="$(mktemp "${destination}.tmp.XXXXXX")"
trap 'rm -f "$temporary"' EXIT
{
    printf 'GADApplicationIdentifier = %s\n' "$GADApplicationIdentifier"
    printf 'bannerViewAdUnitID = %s\n' "$bannerViewAdUnitID"
    printf 'appOpenAdID = %s\n' "$appOpenAdID"
} > "$temporary"

# A hard link atomically creates the ignored file only if it is still absent.
# This protects an existing local production config from accidental overwrite.
ln "$temporary" "$destination" 2>/dev/null || fail 'Release config already exists; it was not changed.'
rm -f "$temporary"
trap - EXIT
printf 'Release config created.\n'
