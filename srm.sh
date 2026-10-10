#!/usr/bin/env bash
set -o pipefail
SRM_SOURCE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC2034 # read by the sourced modules
SRM_SELF=$SRM_SOURCE/dist/srm
for part in common config protocols system firewall certificates routing menu updates main; do
    # shellcheck source=/dev/null
    source "$SRM_SOURCE/lib/$part.sh" || exit 1
done
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
