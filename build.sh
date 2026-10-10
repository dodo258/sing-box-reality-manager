#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
mkdir -p dist
file=$(mktemp dist/.bundle.XXXXXX)
trap 'rm -f "$file"' EXIT
printf '#!/usr/bin/env bash\n# SRM_BUNDLE\nset -o pipefail\nSRM_SELF=$(readlink -f -- "${BASH_SOURCE[0]}")\n' > "$file"
for part in common config protocols system firewall certificates routing menu updates migrate main; do cat "lib/$part.sh" >> "$file"; done
printf '\nif [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi\n' >> "$file"
bash -n "$file"
chmod 755 "$file"
mv "$file" dist/srm
if command -v sha256sum >/dev/null; then (cd dist && sha256sum srm > SHA256SUMS); else (cd dist && shasum -a 256 srm > SHA256SUMS); fi
