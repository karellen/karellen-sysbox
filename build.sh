#!/bin/bash

set -eEux
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/patch.sh"

cd "${SCRIPT_DIR}/sysbox/sysbox-pkgr/k8s"
mkdir -p bin
make all
