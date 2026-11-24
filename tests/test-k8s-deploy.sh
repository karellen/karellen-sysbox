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
# Makefile: fetch-sysbox-ce-rpm-bins looks the release up through the authenticated GitHub API (gh api)
# and installs the Sysbox binaries of every distro RPM for the build arch. gh, curl, rpm2cpio and cpio
# are stubbed; every call is recorded in <work>/calls. The curl stub refuses api.github.com requests,
# like GitHub does once the unauthenticated rate limit of a shared runner IP is exhausted.
#

HOST_ARCH="$(uname -m)"
if [[ "$HOST_ARCH" == "x86_64" ]]; then OTHER_ARCH=aarch64; else OTHER_ARCH=x86_64; fi
RELEASE_VER=0.7.2.1-2
RELEASE_DL="https://github.com/karellen/karellen-sysbox/releases/download/karellen-sysbox-${RELEASE_VER}"

# make_fetch_stubs <work dir> <gh mode: ok|fail> <release asset name>...
function make_fetch_stubs() {
	local work=$1 gh_mode=$2
	shift 2
	mkdir -p "${work}/stubs"

	local asset assets=""
	for asset in "$@"; do
		assets="${assets:+${assets},}{\"name\":\"${asset}\",\"browser_download_url\":\"${RELEASE_DL}/${asset}\"}"
	done
	echo "{\"tag_name\":\"karellen-sysbox-${RELEASE_VER}\",\"assets\":[${assets}]}" > "${work}/release.json"

	cat > "${work}/stubs/gh" <<EOF
#!/bin/bash
echo "gh \$*" >> "${work}/calls"
if [[ "${gh_mode}" == "fail" ]]; then
	echo "gh: Forbidden (HTTP 403)" >&2
	exit 1
fi
if [[ "\$*" == "api repos/karellen/karellen-sysbox/releases/tags/karellen-sysbox-${RELEASE_VER}" ]]; then
	cat "${work}/release.json"
	exit 0
fi
echo "gh: Not Found (HTTP 404)" >&2
exit 1
EOF
	cat > "${work}/stubs/curl" <<EOF
#!/bin/bash
echo "curl \$*" >> "${work}/calls"
url="\${@: -1}"
if [[ "\$url" == *api.github.com* ]]; then
	echo "curl: (22) The requested URL returned error: 403" >&2
	exit 22
fi
echo "\$(basename "\$url")"
EOF
	cat > "${work}/stubs/rpm2cpio" <<EOF
#!/bin/bash
cat
EOF
	cat > "${work}/stubs/cpio" <<EOF
#!/bin/bash
echo "cpio \$*" >> "${work}/calls"
dest=""
while [[ \$# -gt 0 ]]; do
	if [[ "\$1" == "-D" ]]; then dest=\$2; shift; fi
	shift
done
rpm="\$(cat)"
if [[ "\$rpm" == *-debuginfo-* ]] || [[ "\$rpm" == *-debugsource-* ]]; then
	mkdir -p "\${dest}/usr/lib/debug"
	echo "\${rpm}" > "\${dest}/usr/lib/debug/\${rpm}"
	exit 0
fi
mkdir -p "\${dest}/usr/bin"
for bin in sysbox-runc sysbox-mgr sysbox-fs; do
	echo "\${rpm}" > "\${dest}/usr/bin/\${bin}"
done
EOF
	chmod +x "${work}/stubs/"*
}

# run_fetch <work dir>
function run_fetch() {
	local work=$1
	PATH="${work}/stubs:${PATH}" run_make "$work" fetch-sysbox-ce-rpm-bins SYSBOX_CE_VER_KARELLEN="${RELEASE_VER}"
}

# Two distros for the build arch (each with debuginfo), the same distros for the other arch, and
# release assets that are not distro RPMs.
work="${TEST_TMP}/make-fetch-ok"
make_fetch_stubs "$work" ok \
	"fedora-44-karellen-sysbox-${RELEASE_VER}.${HOST_ARCH}.rpm" \
	"fedora-44-karellen-sysbox-debuginfo-${RELEASE_VER}.${HOST_ARCH}.rpm" \
	"fedora-44-karellen-sysbox-${RELEASE_VER}.${OTHER_ARCH}.rpm" \
	"centos-stream-9-karellen-sysbox-${RELEASE_VER}.${HOST_ARCH}.rpm" \
	"centos-stream-9-karellen-sysbox-debuginfo-${RELEASE_VER}.${HOST_ARCH}.rpm" \
	"centos-stream-9-karellen-sysbox-${RELEASE_VER}.${OTHER_ARCH}.rpm" \
	"karellen-sysbox-${RELEASE_VER}.src.rpm" \
	"sha256sums.txt"
rc=0
run_fetch "$work" >"${work}.log" 2>&1 || rc=$?
problems=()
[[ $rc -eq 0 ]] || problems+=("rc=${rc}")
grep -qx "gh api repos/karellen/karellen-sysbox/releases/tags/karellen-sysbox-${RELEASE_VER}" "${work}/calls" 2>/dev/null ||
	problems+=("release not looked up with gh api")
! grep -q "api.github.com" "${work}/calls" 2>/dev/null || problems+=("unauthenticated api.github.com request")
! grep -q "${OTHER_ARCH}" "${work}/calls" 2>/dev/null || problems+=("downloaded ${OTHER_ARCH} assets")
! grep -q "src.rpm\|sha256sums" "${work}/calls" 2>/dev/null || problems+=("downloaded non-distro assets")
for distro in fedora-44 centos-stream-9; do
	for bin in sysbox-runc sysbox-mgr sysbox-fs; do
		grep -qx "${distro}-karellen-sysbox-${RELEASE_VER}.${HOST_ARCH}.rpm" "${work}/bin/sysbox-ce/${distro}/${bin}" 2>/dev/null ||
			problems+=("bin/sysbox-ce/${distro}/${bin} not from the ${distro} ${HOST_ARCH} RPM")
	done
done
dirs="$(cd "${work}/bin/sysbox-ce" 2>/dev/null && ls | sort | tr '\n' ' ' || true)"
[[ "$dirs" == "centos-stream-9 fedora-44 " ]] || problems+=("distro dirs: '${dirs}'")
if [[ ${#problems[@]} -eq 0 ]]; then
	pass "fetch-sysbox-ce-rpm-bins installs the ${HOST_ARCH} distro binaries of the release found with gh api"
else
	fail "fetch-sysbox-ce-rpm-bins with a release: $(IFS=';'; echo "${problems[*]}")"
	sed 's/^/    /' "${work}.log" "${work}/calls" 2>/dev/null || true
fi

# The release lookup fails (e.g. HTTP 403): the target fails without installing anything.
work="${TEST_TMP}/make-fetch-lookup-fails"
make_fetch_stubs "$work" fail "fedora-44-karellen-sysbox-${RELEASE_VER}.${HOST_ARCH}.rpm" \
	"centos-stream-9-karellen-sysbox-${RELEASE_VER}.${HOST_ARCH}.rpm"
rc=0
run_fetch "$work" >"${work}.log" 2>&1 || rc=$?
if [[ $rc -ne 0 ]] && [[ ! -e "${work}/bin/sysbox-ce" ]] && ! grep -q "distro RPM assets" "${work}.log"; then
	pass "fetch-sysbox-ce-rpm-bins fails when the release lookup fails (rc=${rc})"
else
	fail "fetch-sysbox-ce-rpm-bins with a failing release lookup: expected a lookup failure, got rc=${rc}"
	sed 's/^/    /' "${work}.log"
fi

# The release has distro RPMs only for the other arch.
work="${TEST_TMP}/make-fetch-other-arch-only"
make_fetch_stubs "$work" ok "fedora-44-karellen-sysbox-${RELEASE_VER}.${OTHER_ARCH}.rpm" \
	"centos-stream-9-karellen-sysbox-${RELEASE_VER}.${OTHER_ARCH}.rpm"
rc=0
run_fetch "$work" >"${work}.log" 2>&1 || rc=$?
if [[ $rc -ne 0 ]] && grep -q "has no ${HOST_ARCH} distro RPM assets" "${work}.log" && [[ ! -e "${work}/bin/sysbox-ce" ]]; then
	pass "fetch-sysbox-ce-rpm-bins fails when the release has no ${HOST_ARCH} distro RPMs (rc=${rc})"
else
	fail "fetch-sysbox-ce-rpm-bins with only ${OTHER_ARCH} RPMs: expected 'has no ${HOST_ARCH} distro RPM assets', got rc=${rc}"
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
