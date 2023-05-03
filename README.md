# Karellen Sysbox

Karellen spin on the Nestybox/Docker Sysbox, packaged for use with Fedora 36+

This project is NOT endorsed by or affiliated with Nestybox/Docker and is NOT supported by them.

## Installation Instructions

```bash
dnf copr enable karellen/karellen-sysbox
dnf install karellen-sysbox
```

Depending on whether you're using `moby-engine` or `docker-ce` either `/etc/sysconfig/docker` or `/etc/docker/daemon.json` 
have to be modified respectively, using configuration available in `/etc/sysconfig/docker-karellen-sysbox` or 
`/etc/docker/daemon-karellen-sysbox.json` respectively.

Restart docker daemon (`systemctl restart docker`) after configuration changes.
