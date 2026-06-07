# bazzite-linux-utils

## create-smb-automount.tool

### Overview

This script creates a systemd `.mount` and `.automount` pair for an SMB/CIFS network share. It accepts an SMB URL, generates systemd unit files, creates a credentials file, and enables automounting through systemd.

It is intended for Linux systems using `systemd` with CIFS support.

---

### Features

- Accepts SMB URLs in the format:
```
smb://[user@]server/share
```
- Supports optional username in the URL (`user@server`)
- Defaults to the current local system username if none is provided
- Generates:
- systemd `.mount` unit
- systemd `.automount` unit
- SMB credentials file under `~/.smb/`
- Enables automounting via systemd
- Prevents boot failure if the share is unavailable (`nofail`)
- Makes the mount path under `/media/` by default
- SELinux compatibility via `restorecon` when enforcing

---

### Requirements

#### System requirements

- systemd-based Linux system
- CIFS kernel support (`mount.cifs`)
- SMB server supporting SMBv3 (default `vers=3`)
- readlink or realpath

---

### Usage

Run the script:

```bash
./create-smb-automount.tool
```
You will be prompted for an SMB path in the form:
```
smb://[user@]server/share
```
Examples:
```
smb://fileserver01/shared
smb://alice@192.168.1.50/media
```
