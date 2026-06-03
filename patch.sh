#!/bin/bash

set -eEux
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

patch -p1 -d "${SCRIPT_DIR}/sysbox/sysbox-pkgr" < "${SCRIPT_DIR}/sysbox-pkgr-0.patch"

CRIO_VERSIONS="$(cat "${SCRIPT_DIR}/crio-versions" | tr '\n' ' ')"
sed -i "s/^CRIO_VERSIONS = .*/CRIO_VERSIONS = ${CRIO_VERSIONS}/" "${SCRIPT_DIR}/sysbox/sysbox-pkgr/k8s/Makefile"
