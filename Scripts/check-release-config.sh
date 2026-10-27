#!/bin/bash
set +x
set -euo pipefail

# Xcode exports resolved build settings to Run Script phases. Validate those
# values rather than the source xcconfig so command-line overrides are checked.
fail() {
    printf 'error: Release ad configuration: %s\n' "$1" >&2
    exit 1
}

app_id="${GADApplicationIdentifier-}"
banner_id="${bannerViewAdUnitID-}"
open_id="${appOpenAdID-}"

[[ -n "$app_id" ]] || fail 'GADApplicationIdentifier is missing.'
[[ -n "$banner_id" ]] || fail 'bannerViewAdUnitID is missing.'
[[ -n "$open_id" ]] || fail 'appOpenAdID is missing.'

if [[ ! "$app_id" =~ ^ca-app-pub-([0-9]{16})~([0-9]{10})$ ]]; then
    fail 'GADApplicationIdentifier has an invalid or unresolved format.'
fi
publisher="${BASH_REMATCH[1]}"
app_suffix="${BASH_REMATCH[2]}"

if [[ "$publisher" == '3940256099942544' ]]; then
    fail 'Google sample ad IDs are not allowed in Release.'
fi
if [[ "$publisher" == '0000000000000000' || "$app_suffix" == '0000000000' ]]; then
    fail 'GADApplicationIdentifier contains placeholder digits.'
fi

check_ad_unit() {
    local name="$1" value="$2" unit_publisher
    if [[ ! "$value" =~ ^ca-app-pub-([0-9]{16})/([0-9]{10})$ ]]; then
        fail "$name has an invalid or unresolved format."
    fi
    unit_publisher="${BASH_REMATCH[1]}"
    local unit_suffix="${BASH_REMATCH[2]}"
    if [[ "$unit_suffix" == '0000000000' ]]; then
        fail "$name contains placeholder digits."
    fi
    if [[ "$unit_publisher" != "$publisher" ]]; then
        fail "$name does not match the app's AdMob publisher."
    fi
}

check_ad_unit 'bannerViewAdUnitID' "$banner_id"
check_ad_unit 'appOpenAdID' "$open_id"
[[ "$banner_id" != "$open_id" ]] || fail 'Banner and app-open ad units must be different.'

printf 'Release ad configuration validated.\n'
