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
  - `ghrelease.yml` - On tag push: syncs COPR build to GitHub Release, builds multi-arch K8s deploy images

## Build System

- **RPM/Tito**: `tito tag` and `tito build` drive versioning and packaging
- **Version scheme**: `{sysbox/VERSION}.{commits_since_version_change}-{release}` (e.g. `0.7.0.3-2`)
- **Custom tagger**: `.tito/libs/karellen/tito/version_tagger.py` - reads `sysbox/VERSION`, counts submodule commits
- **RPM build**: Downloads Go + protoc, runs `make sysbox-local` in the submodule

## Patch Workflow

The single patch `sysbox-pkgr-0.patch` is applied:
- During RPM build: automatically via `%autosetup` in the spec file
- During K8s image build: explicitly via `patch -p1 -d sysbox/sysbox-pkgr < sysbox-pkgr-0.patch` in `ghrelease.yml`

When upstream changes files touched by the patch, the patch must be regenerated against the new submodule state.

## Key Commands

```bash
# Tag a new release (after committing changes)
tito tag --accept-auto-changelog

# Build RPM locally
tito build --rpm --test

# Apply patch manually for testing
patch -p1 -d sysbox/sysbox-pkgr < sysbox-pkgr-0.patch
```
