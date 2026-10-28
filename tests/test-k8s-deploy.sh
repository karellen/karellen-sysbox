#!/bin/bash
#
# Offline tests for the sysbox-deploy-k8s image tooling as patched by sysbox-pkgr-0.patch:
# the Makefile artifact checks and the deploy script's Sysbox binaries precheck.
#
# Usage: tests/test-k8s-deploy.sh [patched sysbox-pkgr directory]
#

set -eEu
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKGR_DIR="$(cd "${1:-${SCRIPT_DIR}/../sysbox/sysbox-pkgr}" && pwd)"
MAKEFILE="${PKGR_DIR}/k8s/Makefile"
DEPLOY_SCRIPT="${PKGR_DIR}/k8s/scripts/sysbox-deploy-k8s.sh"

TEST_TMP="$(mktemp -d)"
trap 'rm -rf "${TEST_TMP}"' EXIT

failures=0

function pass() {
	echo "PASS: $*"
}

function fail() {
	echo "FAIL: $*"
	failures=$((failures + 1))
}

# make_bins <dir> <bin>... creates the named (empty) binaries in <dir>
function make_bins() {
	local dir=$1
	shift
	mkdir -p "$dir"
	local bin
	for bin in "$@"; do
		touch "${dir}/${bin}"
	done
}

# run_make <work dir> <target> [make args...]
function run_make() {
	local work=$1 target=$2
	shift 2
	(cd "$work" && TMPDIR="$work" make -s -f "$MAKEFILE" SYSBOX_CE_VER=0.7.1 "$@" "$target")
}

#
# Makefile: check-sysbox-artifacts
#

# check_artifacts_case <name> <pass|fail> <setup function>
function check_artifacts_case() {
	local name=$1 expected=$2 setup=$3
	local work="${TEST_TMP}/make-${name}"
	mkdir -p "$work"
	(cd "$work" && $setup)

	local rc=0
	run_make "$work" check-sysbox-artifacts SYSBOX_CE_VER_KARELLEN=0.7.1.8-1 >"${work}.log" 2>&1 || rc=$?
	if { [[ "$expected" == "pass" ]] && [[ $rc -eq 0 ]]; } || { [[ "$expected" == "fail" ]] && [[ $rc -ne 0 ]]; }; then
		pass "check-sysbox-artifacts ${name} (rc=${rc})"
	else
		fail "check-sysbox-artifacts ${name}: expected ${expected}, got rc=${rc}"
		sed 's/^/    /' "${work}.log"
	fi
}

function artifacts_complete() {
	make_bins bin/sysbox-ce/generic sysbox-runc sysbox-mgr sysbox-fs
	make_bins bin/sysbox-ce/fedora-44 sysbox-runc sysbox-mgr sysbox-fs
	make_bins bin/sysbox-ce/centos-stream-9 sysbox-runc sysbox-mgr sysbox-fs
}

function artifacts_generic_only() {
	make_bins bin/sysbox-ce/generic sysbox-runc sysbox-mgr sysbox-fs
}

function artifacts_generic_missing_fs() {
	make_bins bin/sysbox-ce/generic sysbox-runc sysbox-mgr
	make_bins bin/sysbox-ce/fedora-44 sysbox-runc sysbox-mgr sysbox-fs
	make_bins bin/sysbox-ce/centos-stream-9 sysbox-runc sysbox-mgr sysbox-fs
}

function artifacts_distro_missing_runc() {
	make_bins bin/sysbox-ce/generic sysbox-runc sysbox-mgr sysbox-fs
	make_bins bin/sysbox-ce/fedora-44 sysbox-mgr sysbox-fs
	make_bins bin/sysbox-ce/centos-stream-9 sysbox-runc sysbox-mgr sysbox-fs
}

check_artifacts_case complete pass artifacts_complete
check_artifacts_case generic-only fail artifacts_generic_only
check_artifacts_case generic-missing-sysbox-fs fail artifacts_generic_missing_fs
check_artifacts_case distro-missing-sysbox-runc fail artifacts_distro_missing_runc

#
# Makefile: fetch-sysbox-ce-rpm-bins refuses to run without a release version
#

work="${TEST_TMP}/make-fetch-no-version"
mkdir -p "$work"
rc=0
run_make "$work" fetch-sysbox-ce-rpm-bins SYSBOX_CE_VER_KARELLEN= >"${work}.log" 2>&1 || rc=$?
if [[ $rc -ne 0 ]] && grep -q "SYSBOX_CE_VER_KARELLEN is empty" "${work}.log"; then
	pass "fetch-sysbox-ce-rpm-bins without a release version (rc=${rc})"
else
	fail "fetch-sysbox-ce-rpm-bins without a release version: expected failure, got rc=${rc}"
	sed 's/^/    /' "${work}.log"
fi

#
# sysbox-deploy-k8s.sh: Sysbox binaries for the host distro are verified before the host is touched
#

# deploy_case <name> <bins in /opt/sysbox/bin/fedora-44...>
# Runs "install" on a Fedora 44 node that needs a Sysbox update. Kubernetes and systemd side effects
# are stubbed and recorded in <root>/events; the Sysbox binaries are really copied into <root>/host-bin.
function deploy_case() {
	local root="${TEST_TMP}/deploy-$1"
	shift
	mkdir -p "${root}/opt/sysbox/bin" "${root}/host-bin"
	printf 'ID=fedora\nVERSION_ID=44\n' >"${root}/os-release"
	if [[ $# -gt 0 ]]; then
		make_bins "${root}/opt/sysbox/bin/fedora-44" "$@"
	fi
	: >"${root}/events"

	# Not "( ... ) || rc=$?": errexit is ignored in a subshell whose status is tested, and the deploy
	# script relies on the errexit it sets for itself.
	local rc
	set +e
	(
		export SYSBOX_VERSION=0.7.1
		# shellcheck disable=SC1090
		source <(sed '/^main "\$@"$/d' "$DEPLOY_SCRIPT")

		sysbox_artifacts="${root}/opt/sysbox"
		host_os_release="${root}/os-release"
		host_bin="${root}/host-bin"
		host_var_lib_sysbox_deploy_k8s="${root}/var-lib-sysbox-deploy-k8s"
		events="${root}/events"

		function id() { echo 0; }
		function get_host_kernel() { echo 7.2.13-200.fc44.x86_64; }
		function is_supported_kernel() { return 0; }
		function is_supported_arch() { return 0; }
		function get_k8s_version() { echo v1.33.13; }
		function get_container_runtime() { echo containerd; }
		function install_precheck() {
			do_sysbox_install="false"
			do_sysbox_update="true"
		}
		function add_taint_to_node() { echo "taint $*" >>"$events"; }
		function rm_taint_from_node() { echo "untaint $*" >>"$events"; }
		function add_label_to_node() { echo "label $*" >>"$events"; }
		function install_sysbox_deps() { echo "deps" >>"$events"; }
		function stop_sysbox() { echo "stop" >>"$events"; }
		function start_sysbox() { echo "start" >>"$events"; }
		function config_sysbox_env() { :; }
		function copy_sysbox_env_config_to_host() { :; }
		function apply_sysbox_env_config() { :; }
		function config_sysbox() { :; }
		function copy_sysbox_config_to_host() { :; }
		function is_containerd_with_userns() { return 1; }
		function delete_sysbox_pods() { :; }
		function sleep() { :; }

		main ce install
	) >"${root}.log" 2>&1
	rc=$?
	set -e

	DEPLOY_RC=$rc
	DEPLOY_EVENTS="$(tr '\n' ',' <"${root}/events")"
	DEPLOY_LOG="${root}.log"
	DEPLOY_HOST_BIN="${root}/host-bin"
}

deploy_case complete sysbox-runc sysbox-mgr sysbox-fs
if [[ $DEPLOY_RC -eq 0 ]] &&
	[[ "$DEPLOY_EVENTS" == *"stop,start,"* ]] &&
	[[ -f "${DEPLOY_HOST_BIN}/sysbox-runc" ]] && [[ -f "${DEPLOY_HOST_BIN}/sysbox-mgr" ]] &&
	[[ -f "${DEPLOY_HOST_BIN}/sysbox-fs" ]]; then
	pass "deploy with Sysbox binaries for the host distro installs them (events: ${DEPLOY_EVENTS})"
else
	fail "deploy with Sysbox binaries for the host distro: rc=${DEPLOY_RC} events: ${DEPLOY_EVENTS}"
	sed 's/^/    /' "$DEPLOY_LOG"
fi

for missing_case in no-distro-dir missing-sysbox-fs; do
	if [[ "$missing_case" == "no-distro-dir" ]]; then
		deploy_case "$missing_case"
	else
		deploy_case "$missing_case" sysbox-runc sysbox-mgr
	fi
	if [[ $DEPLOY_RC -ne 0 ]] && [[ -z "$DEPLOY_EVENTS" ]] &&
		grep -q "ERROR: Sysbox .*fedora-44" "$DEPLOY_LOG"; then
		pass "deploy without Sysbox binaries (${missing_case}) fails before touching the host (rc=${DEPLOY_RC})"
	else
		fail "deploy without Sysbox binaries (${missing_case}): expected failure before touching the host," \
			"got rc=${DEPLOY_RC} events: ${DEPLOY_EVENTS}"
		sed 's/^/    /' "$DEPLOY_LOG"
	fi
done

if [[ $failures -ne 0 ]]; then
	echo "${failures} test(s) failed"
	exit 1
fi
echo "All tests passed"
