# Karellen Sysbox

Unofficial Fedora/RHEL/CentOS RPM packaging of [Nestybox Sysbox](https://github.com/nestybox/sysbox) container runtime.

## Project Structure

- `sysbox/` - Git submodule tracking upstream `nestybox/sysbox` master branch
- `karellen-sysbox.spec` - RPM spec file (build/install instructions, changelog)
- `sysbox-pkgr-0.patch` - Patch applied to `sysbox/sysbox-pkgr/` for K8s deployment (Fedora/RHEL support, Karellen image registry)
- `packaging/` - systemd units, sysctl config, Docker daemon config
- `.tito/` - Tito RPM build/release tooling with custom `SysboxVersionTagger`
- `.github/workflows/` - CI/CD workflows:
  - `update.yml` - Checks upstream submodule changes every 6h, auto-commits and tags via tito
  - `ghrelease.yml` - On tag push: syncs COPR build to GitHub Release, builds multi-arch K8s deploy images. The sync (`karellen/copr-to-gh-release`) fails the run, and so blocks the image build, if any RPM of a succeeded COPR chroot cannot be fetched. Also triggered via `repository_dispatch` (event type `crio-release`) from karellen-sysbox-crio when a new patched CRI-O release is published — in that case the COPR sync is skipped and the images are rebuilt at the latest existing `karellen-sysbox-*` tag, repackaging them with the new CRI-O binaries. The same images-only rebuild can be run manually via `workflow_dispatch` with an empty `tag` input

## Build System

- **RPM/Tito**: `tito tag` and `tito build` drive versioning and packaging
- **Version scheme**: `{sysbox/VERSION}.{commits_since_version_change}-{release}` (e.g. `0.7.0.3-2`)
- **Custom tagger**: `.tito/libs/karellen/tito/version_tagger.py` - reads `sysbox/VERSION`, counts submodule commits
- **RPM build**: Downloads Go + protoc, installs the `protoc-gen-go` and `protoc-gen-go-grpc` plugins (versions pinned in the spec), runs `make sysbox-local` in the submodule

## Patch Workflow

The single patch `sysbox-pkgr-0.patch` is applied:
- During RPM build: automatically via `%autosetup` in the spec file
- During K8s image build: `ghrelease.yml` runs `build.sh`, which applies it via `patch.sh`, runs `tests/test-k8s-deploy.sh`, then `make all` in `sysbox/sysbox-pkgr/k8s`

When upstream changes files touched by the patch, the patch must be regenerated against the new submodule state.

## K8s Deploy Image Invariants

An image must never ship without Sysbox binaries for the distros it claims, and the deploy daemonset must never stop a running Sysbox it cannot reinstall:
- `fetch-sysbox-ce-rpm-bins` fails if the release version is empty, the GitHub API call fails, or the `karellen-sysbox-<version>` release has no distro RPM assets for the build arch
- `check-sysbox-artifacts` requires all of `sysbox-runc`, `sysbox-mgr`, `sysbox-fs` in `bin/sysbox-ce/generic` and in every distro directory, and at least one distro directory
- `sysbox-deploy-k8s.sh` runs `check_sysbox_artifacts` in the main shell right after `install_precheck` (when installing or updating), before the node is tainted or Sysbox is stopped

`tests/test-k8s-deploy.sh [patched sysbox-pkgr dir]` covers these offline; it defaults to `sysbox/sysbox-pkgr`, so run it after `patch.sh`.

## Key Commands

```bash
# Tag a new release (after committing changes)
tito tag --accept-auto-changelog

# Build RPM locally
tito build --rpm --test

# Apply patch manually for testing
patch -p1 -d sysbox/sysbox-pkgr < sysbox-pkgr-0.patch

# Test the patched K8s deploy image tooling (offline)
tests/test-k8s-deploy.sh
```
