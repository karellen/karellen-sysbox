%global debug_package %{nil}
%global _missing_build_ids_terminate_build 0

Name: karellen-sysbox
Version: 0.6.6.6
Release: 2
License: ASL 2.0
Summary: Karellen Sysbox is an UNOFFICIAL Fedora/RHEL/CentOS spin of the Nestybox Sysbox.
Url: https://github.com/karellen/%{name}
Vendor: Karellen, Inc.
Packager: Karellen, Inc. <supervisor@karellen.co>
Group: Tools/Docker

BuildRequires: git
BuildRequires: make
BuildRequires: iproute
BuildRequires: automake
BuildRequires: autoconf
BuildRequires: libtool
BuildRequires: pkg-config
BuildRequires: wget
BuildRequires: tar
BuildRequires: gzip
BuildRequires: unzip
BuildRequires: glibc-static
BuildRequires: systemd-rpm-macros
BuildRequires: libseccomp-devel

Requires: (docker or docker-ce)
Requires: systemd
Requires: fuse
Requires: libseccomp

Provides: sysbox

Source0: %{name}-%{version}.tar.gz

%description
Karellen Sysbox is an UNOFFICIAL Fedora/RHEL/CentOS spin of the Nestybox Sysbox.
The project is NOT affiliated with or supported by Docker or Nestybox.
Depending on whether you're using Karellen Sysbox with moby-engine or docker-ce either
/etc/sysconfig/docker or /etc/docker/daemon.json have to be modified respectively,
using configuration available in /etc/sysconfig/docker-karellen-sysbox or
/etc/docker/daemon-karellen-sysbox.json respectively.
Restart docker daemon (systemctl restart docker) after configuration changes.

%ifarch x86_64
  %global sys_arch amd64
  %global protoc_arch x86_64
%endif
%ifarch aarch64
  %global sys_arch arm64
  %global protoc_arch aarch_64
%endif
%ifarch arm
  %global sys_arch armf
%endif
%ifarch armel
  %global sys_arch armel
%endif

%prep
%autosetup
cd /tmp
mkdir -p $HOME/.local
export PATH="$PATH:$HOME/.local/bin:$HOME/.local/go/bin"
wget https://go.dev/dl/go1.22.9.linux-%{sys_arch}.tar.gz
tar -C $HOME/.local -xzf go1.22.9.linux-%{sys_arch}.tar.gz
curl -LO https://github.com/protocolbuffers/protobuf/releases/download/v3.15.8/protoc-3.15.8-linux-%{protoc_arch}.zip
unzip -u protoc-3.15.8-linux-%{protoc_arch}.zip -d $HOME/.local
go install github.com/golang/protobuf/protoc-gen-go@latest
export PATH="$PATH:$(go env GOPATH)/bin"

%build
export PATH="$PATH:$HOME/.local/bin:$HOME/.local/go/bin"
export PATH="$PATH:$(go env GOPATH)/bin"

cd sysbox
make sysbox-local

%install
export PATH="$PATH:$HOME/.local/bin:$HOME/.local/go/bin"
export PATH="$PATH:$(go env GOPATH)/bin"

cp sysbox/OSS_DISCLOSURES.md .
cp sysbox/LICENSE LICENSE-nestybox
cp LICENSE LICENSE-karellen

install -Dpm 644 packaging/docker-karellen-sysbox \
                 %{buildroot}%{_sysconfdir}/sysconfig/docker-karellen-sysbox
install -Dpm 644 packaging/daemon-karellen-sysbox.json \
                 %{buildroot}%{_sysconfdir}/docker/daemon-karellen-sysbox.json

install -Dpm 644 packaging/sysctl.d/99-sysbox-sysctl.conf -t %{buildroot}%{_sysctldir}/
install -Dpm 644 packaging/systemd/sysbox-fs.service \
                 packaging/systemd/sysbox-mgr.service \
                 packaging/systemd/sysbox.service -t %{buildroot}%{_unitdir}/

cd sysbox
make DESTDIR=%{buildroot}%{_bindir} install

%files
%license OSS_DISCLOSURES.md LICENSE-nestybox LICENSE-karellen
%config %{_sysconfdir}/sysconfig/docker-karellen-sysbox
%config %{_sysconfdir}/docker/daemon-karellen-sysbox.json

%{_bindir}/sysbox-fs
%{_bindir}/sysbox-mgr
%{_bindir}/sysbox-runc
%{_bindir}/sysbox
%{_sysctldir}/99-sysbox-sysctl.conf
%{_unitdir}/sysbox-fs.service
%{_unitdir}/sysbox-mgr.service
%{_unitdir}/sysbox.service

%post
%sysctl_apply 99-sysbox-sysctl.conf
%systemd_post sysbox-fs.service sysbox-mgr.service sysbox.service

%preun
%systemd_preun sysbox-fs.service sysbox-mgr.service sysbox.service

%postun
%systemd_postun_with_restart sysbox-fs.service sysbox-mgr.service sysbox.service

%changelog
* Wed Jan 22 2025 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.6.6-2
- Fix daemon.json configuration syntax for Docker 27 (arcadiy@ivanov.biz)

* Sat Jan 18 2025 Karellen Supervisor <supervisor@karellen.co> 0.6.6.6-1
- Update 2025-01-18T00:13:53Z (supervisor@karellen.co)

* Fri Jan 10 2025 Karellen Supervisor <supervisor@karellen.co> 0.6.6.4-1
- Update 2025-01-10T00:15:22Z (supervisor@karellen.co)

* Sat Jan 04 2025 Karellen Supervisor <supervisor@karellen.co> 0.6.6.3-1
- Update 2025-01-04T06:04:21Z (supervisor@karellen.co)

* Sat Jan 04 2025 Karellen Supervisor <supervisor@karellen.co> 0.6.6.0-1
- Update 2025-01-04T00:14:24Z (supervisor@karellen.co)

* Tue Dec 10 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.5.15-1
- Update 2024-12-10T18:05:14Z (supervisor@karellen.co)

* Tue Dec 10 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.5.14-1
- Update 2024-12-10T00:16:19Z (supervisor@karellen.co)

* Sat Dec 07 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.5.13-1
- Update 2024-12-07T00:15:35Z (supervisor@karellen.co)

* Fri Dec 06 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.5.12-1
- Update 2024-12-06T00:16:04Z (supervisor@karellen.co)

* Thu Dec 05 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.5.11-1
- Update 2024-12-05T12:06:11Z (supervisor@karellen.co)

* Thu Dec 05 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.5.9-1
- Update 2024-12-05T06:05:43Z (supervisor@karellen.co)

* Wed Dec 04 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.5.6-1
- Update 2024-12-04T18:05:05Z (supervisor@karellen.co)

* Tue Nov 12 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.5.4-1
- Update 2024-11-12T00:14:19Z (supervisor@karellen.co)

* Mon Nov 11 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.5.2-1
- Update 2024-11-11T18:04:34Z (supervisor@karellen.co)

* Sun Nov 10 2024 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.5.0-3
- Fix changelog chronological order (arcadiy@ivanov.biz)

* Sat Nov 10 2024 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.5.0-2
- Update to Golang 1.22 (arcadiy@ivanov.biz)

* Sun Nov 10 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.5.0-1
- Update 2024-11-10T00:15:37Z (supervisor@karellen.co)
- Token for the update script to allow to chain triggers (arcadiy@ivanov.biz)

* Sat Nov 09 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.4.80-1
- Update 2024-11-09T06:04:25Z (supervisor@karellen.co)

* Tue Nov 05 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.4.77-1
- Update 2024-11-05T06:04:58Z (supervisor@karellen.co)
- Use PAT token (arcadiy@ivanov.biz)
- Try to fix the on-push-tag not working (arcadiy@ivanov.biz)

* Tue Nov 05 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.4.75-1
- Update 2024-11-05T00:14:27Z (supervisor@karellen.co)

* Sun Nov 03 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.4.74-1
- Update 2024-11-03T00:16:05Z (supervisor@karellen.co)
- Fix workflow tag (arcadiy@ivanov.biz)
- Another fix (arcadiy@ivanov.biz)
- Fix copr gh release build (arcadiy@ivanov.biz)
- Add Copr to GH Release synchronizer (arcadiy@ivanov.biz)

* Sun Oct 20 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.4.72-1
- Update 2024-10-20T00:16:01Z (supervisor@karellen.co)

* Sat Oct 19 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.4.71-1
- Update 2024-10-19T06:04:17Z (supervisor@karellen.co)

* Sat Oct 19 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.4.70-1
- Update 2024-10-19T00:14:11Z (supervisor@karellen.co)

* Sun Oct 13 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.4.69-1
- Update 2024-10-13T00:15:57Z (supervisor@karellen.co)

* Sat Oct 12 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.4.68-1
- Update 2024-10-12T18:03:55Z (supervisor@karellen.co)

* Thu Oct 10 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.4.66-1
- Update 2024-10-10T18:04:32Z (supervisor@karellen.co)

* Thu Oct 10 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.4.65-1
- Update 2024-10-10T00:14:11Z (supervisor@karellen.co)

* Tue Oct 08 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.4.64-1
- Update 2024-10-08T18:04:26Z (supervisor@karellen.co)

* Tue Oct 08 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.4.63-1
- Update 2024-10-08T06:05:13Z (supervisor@karellen.co)

* Tue Oct 08 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.4.62-1
- Update 2024-10-08T00:14:09Z (supervisor@karellen.co)

* Tue Sep 24 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.4.58-1
- Update 2024-09-24T00:14:32Z (supervisor@karellen.co)
- Fix regex pattern syntax (arcadiy@ivanov.biz)

* Sun Sep 22 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.4.56-1
- Update 2024-09-22T16:11:21Z (supervisor@karellen.co)
- Settle on Ubuntu 24.04 (arcadiy@ivanov.biz)
- Upgrade pip (arcadiy@ivanov.biz)
- Fix the pip3 install script further (arcadiy@ivanov.biz)
- Fix tito not installing into root (arcadiy@ivanov.biz)

* Tue Jun 04 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.4.42-1
- Update 2024-06-04T06:02:16Z (supervisor@karellen.co)

* Mon Jun 03 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.4.41-1
- Update 2024-06-03T06:02:10Z (supervisor@karellen.co)

* Sat Jun 01 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.4.40-1
- Update 2024-06-01T00:05:29Z (supervisor@karellen.co)

* Fri May 31 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.4.33-1
- Update 2024-05-31T18:02:05Z (supervisor@karellen.co)

* Fri May 31 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.4.30-1
- Update 2024-05-31T00:05:11Z (supervisor@karellen.co)

* Fri May 24 2024 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.4.28-2
- Move to golang 1.21.10 (arcadiy@ivanov.biz)

* Fri May 24 2024 Arcadiy Ivanov <arcadiy@ivanov.biz>
- Move to golang 1.21.10 (arcadiy@ivanov.biz)

* Fri May 24 2024 Karellen Supervisor <supervisor@karellen.co> 0.6.4.28-1
- Update 2024-05-24T19:40:00Z (supervisor@karellen.co)
- Add python rpm bindings (arcadiy@ivanov.biz)
- Install rpm (arcadiy@ivanov.biz)
- Add user-local bin to PATH (arcadiy@ivanov.biz)
- This doesn't have to be self-hosted (arcadiy@ivanov.biz)
- Add auto-updater (arcadiy@ivanov.biz)

* Sat May 11 2024 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.4.24-1
- Update 2024-05-11 (arcadiy@ivanov.biz)

* Sat May 04 2024 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.4.20-1
- Update 2024-05-04 (arcadiy@ivanov.biz)

* Sat Apr 20 2024 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.4.11-1
- Update 20240420 (arcadiy@ivanov.biz)

* Wed Mar 27 2024 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.3.23-1
- Update 2024-03-27 (arcadiy@ivanov.biz)

* Fri Feb 16 2024 Arcadiy Ivanov <arcadiy@ivanov.biz>
- Update 20240216 (arcadiy@ivanov.biz)

* Mon Feb 05 2024 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.3.17-1
- Update 2024-02-05 (arcadiy@ivanov.biz)

* Mon Jan 22 2024 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.3.9-1
- Update 2024-01-22 (v0.6.3) (arcadiy@ivanov.biz)

* Sat Dec 16 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.2.32-1
- Update 2023-12-16 (arcadiy@ivanov.biz)

* Thu Nov 23 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.2.30-7
- Fix libseccomp dependency (arcadiy@ivanov.biz)

* Thu Nov 23 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.2.30-6
- Do explicitly depend on libsseccomp just in case (arcadiy@ivanov.biz)

* Thu Nov 23 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.2.30-5
- Attempt to build sysbox shared (arcadiy@ivanov.biz)

* Thu Nov 23 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.2.30-4
- Actually we need a static version of libseccomp (arcadiy@ivanov.biz)

* Thu Nov 23 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.2.30-3
- Add Libseccomp to requirements (arcadiy@ivanov.biz)

* Thu Nov 23 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.2.30-2
- Attempt to fix the build with libseccomp-devel dependency
  (arcadiy@ivanov.biz)

* Wed Nov 22 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.2.30-1
- Update 2023-11-22 (arcadiy@ivanov.biz)

* Fri Sep 22 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.2.11-1
- Update 2023-09-22 (arcadiy@ivanov.biz)

* Sun Sep 17 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.2.9-1
- Update 2023-09-17 (arcadiy@ivanov.biz)

* Fri Sep 01 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.2.8-1
- Update 20230901 (arcadiy@ivanov.biz)

* Thu Aug 24 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.2.6-2
- Ensure `unzip` doesn't wait for prompts (arcadiy@ivanov.biz)
- Require either docker or docker-ce Add some vendor metadata
  (arcadiy@ivanov.biz)

* Fri Aug 18 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.2.6-1
- Update 20230818 (arcadiy@ivanov.biz)

* Tue Jul 04 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.2.1-3
- Sysbox on Fedora requires fuse package to operate (arcadiy@ivanov.biz)

* Sat Jul 01 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.2.1-2
- SubmoduleAwareBuilder has been fixed in tito 0.6.23 Removing local patch
  (arcadiy@ivanov.biz)

* Tue Jun 27 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.2.1-1
- Update to latest 2023-06-27 (arcadiy@ivanov.biz)

* Wed May 10 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.1.29-1
- Update submodule (arcadiy@ivanov.biz)

* Sat May 06 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.1.28-1
- 2023-05-06 upstream update (arcadiy@ivanov.biz)

* Wed May 03 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.1.23-1
- Pull latest submodules Update summary and description 
  Add README.md (arcadiy@ivanov.biz)

* Mon May 01 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.1.21-1
- Update to latest sysbox (arcadiy@ivanov.biz)

* Mon May 01 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.1.17-5
- Fix Tito submodule population detection (arcadiy@ivanov.biz)

* Mon May 01 2023 Arcadiy Ivanov <arcadiy@ivanov.biz>
- Fix Tito submodule population detection (arcadiy@ivanov.biz)

* Mon May 01 2023 Arcadiy Ivanov <arcadiy@ivanov.biz>
- Fix Tito submodule population detection (arcadiy@ivanov.biz)

* Mon May 01 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.1.17-4
- Harden Tito submodules processor 
- Ensure selinux is disabled from Docker daemon.json (arcadiy@ivanov.biz)

* Sun Apr 30 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.1.17-3
- Add `selinux-enabled` to the daemon.json template

* Sun Apr 30 2023 Arcadiy Ivanov <arcadiy@ivanov.biz> 0.6.1.17-2
- Remove Debian-only kernel sysctl (arcadiy@ivanov.biz)

