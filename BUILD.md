# Building and Packaging MTKClient

This guide details how to compile, package, and install **mtkclient** from source, with a particular focus on generating native **RPM packages** for Fedora, Red Hat Enterprise Linux (RHEL), CentOS Stream, and Fedora Asahi Remix (aarch64 / Apple Silicon).

---

## Table of Contents

- [Overview](#overview)
- [RPM Package Highlights](#rpm-package-highlights)
- [Automated Compilation & Testing (build.sh)](#automated-compilation--testing-buildsh)
- [Prerequisites & Dependencies](#prerequisites--dependencies)
  - [Fedora / RHEL / CentOS / Fedora Asahi Remix](#fedora--rhel--centos--fedora-asahi-remix)
  - [Debian / Ubuntu](#debian--ubuntu)
  - [Arch Linux](#arch-linux)
- [Building the RPM Package (Fedora / RHEL)](#building-the-rpm-package-fedora--rhel)
  - [1. Prepare the RPM Build Directory Structure](#1-prepare-the-rpm-build-directory-structure)
  - [2. Generate the Source Tarball](#2-generate-the-source-tarball)
  - [3. Stage the Spec and Desktop Files](#3-stage-the-spec-and-desktop-files)
  - [4. Build Binary and Source RPMs](#4-build-binary-and-source-rpms)
  - [5. Install the Generated RPM](#5-install-the-generated-rpm)
  - [6. Configure Udev Permissions & User Groups](#6-configure-udev-permissions--user-groups)
- [Standard Python Installation (Alternative)](#standard-python-installation-alternative)
  - [Using pip (System / User)](#using-pip-system--user)
  - [Using a Virtual Environment (venv)](#using-a-virtual-environment-venv)
  - [Using uv (Fast Package Manager)](#using-uv-fast-package-manager)
- [Package Verification & Testing](#package-verification--testing)
  - [Inspecting the RPM](#inspecting-the-rpm)
  - [Verifying CLI Tools](#verifying-cli-tools)
  - [Verifying GUI Application](#verifying-gui-application)
- [Troubleshooting & FAQ](#troubleshooting--faq)

---

## Overview

`mtkclient` is an exploitation, flashing, and reverse-engineering suite for MediaTek (MTK) SoCs. It enables reading and writing flash partitions, dumping BootROM and Preloader firmware, bypassing SLA/DAA security handshakes, executing payloads via USB BROM vulnerabilities (such as Kamakiri and Ammonite), and interacting directly with device hardware.

The project is packaged as an architecture-independent (`noarch`) RPM package because all executable logic is implemented in Python 3. Target firmware binaries, Preloaders, and DA loaders included in the package are device payloads rather than host machine native binaries, allowing the same package to run seamlessly on both `x86_64` and `aarch64` (including Apple Silicon on Fedora Asahi Remix).

---

## RPM Package Highlights

The RPM package specification (`mtkclient.spec`) configures a complete system installation:

- **Command-Line Tools (`/usr/bin/`):**
  - Primary commands: `mtk`, `stage2`, `da_parser`, `brom_to_offs`
  - Backward-compatible symlinks: `mtk.py`, `mtk_gui.py`, `stage2.py`
- **Graphical Interface (`mtk_gui`):**
  - PySide6/Qt desktop application launcher (`/usr/share/applications/mtk_gui.desktop`)
  - Application icons installed to standard hicolor paths (`256x256`, `64x64`, `32x32`)
- **Hardware Integration (`/usr/lib/udev/rules.d/`):**
  - `52-mtk.rules`: Grants USB permissions (`uaccess`, `0666`) for MediaTek bootrom and preloader devices (VID `0e8d`, etc.)
  - `51-edl.rules`: Rules for Qualcomm EDL and emergency diagnostic interfaces
- **Package Metadata:**
  - Python wheel built using Fedora's `%pyproject_wheel` macro with PEP 517/621 compliance (`hatchling` backend)
  - Dist-info metadata and documentation installed to `/usr/share/doc/mtkclient` and `/usr/share/licenses/mtkclient`

---

## Automated Compilation & Testing (build.sh)

A turnkey build and test automation script `build.sh` is provided in the repository. It automatically handles source tarball creation, RPM compilation, and end-to-end sandbox verification tests.

### Quick Start

Simply run:

```bash
chmod +x build.sh
./build.sh
```

This single command will:
1. Validate required build tools (`rpmbuild`, `python3`, `git`, `tar`, `rpm2cpio`, `cpio`, `desktop-file-validate`).
2. Generate the source tarball `mtkclient-2.1.4.tar.gz` and place it in `~/rpmbuild/SOURCES/`.
3. Compile both binary RPM (`.noarch.rpm`) and source RPM (`.src.rpm`).
4. Copy the compiled RPMs to `dist/` for immediate access.
5. Perform automated verification tests:
   - Queries and validates RPM metadata (`rpm -qip`).
   - Verifies the file manifest for all CLI binaries, desktop entries, and udev rules.
   - Extracts the package to an isolated sandbox and checks python3 shebangs.
   - Validates the desktop entry file (`desktop-file-validate`).
   - Verifies MediaTek vendor IDs in udev rules.
   - Verifies isolated module import from python site-packages.
6. Display the path to the ready-to-install RPM and the installation command.

### Available Options

```text
Usage: build.sh [OPTIONS]

Options:
  -r, --rpm          Build RPM package (default: true)
  -w, --wheel        Build Python wheel package (default: false)
  -t, --test         Run verification tests on built artifacts (default: true)
  --no-test          Skip artifact verification tests
  -c, --clean        Clean build directories and temporary files
  -h, --help         Show this help message and exit

Examples:
  ./build.sh                  # Build RPM and run tests (standard)
  ./build.sh --wheel          # Build RPM and Python wheel
  ./build.sh --clean          # Clean local build directories
```

---

## Prerequisites & Dependencies

### Fedora / RHEL / CentOS / Fedora Asahi Remix

Install the development tools, Python 3 libraries, and RPM packaging utilities via `dnf`:

```bash
sudo dnf install -y \
    python3 \
    python3-devel \
    python3-pip \
    python3-setuptools \
    python3-wheel \
    python3-hatchling \
    rpm-build \
    rpmdevtools \
    desktop-file-utils \
    systemd-rpm-macros \
    git \
    libusb1
```

For runtime dependencies (required for device interaction and GUI):

```bash
sudo dnf install -y \
    python3-pyusb \
    python3-pycryptodomex \
    python3-colorama \
    python3-pyserial \
    python3-pyside6 \
    python3-shiboken6
```

*(Optional: `python3-fusepy` for mounting partitions via FUSE).*

### Debian / Ubuntu

```bash
sudo apt update
sudo apt install -y \
    python3 \
    python3-dev \
    python3-pip \
    python3-setuptools \
    python3-pyusb \
    python3-serial \
    python3-colorama \
    libusb-1.0-0-dev \
    git
```

### Arch Linux

```bash
sudo pacman -S --needed \
    python \
    python-pip \
    python-setuptools \
    python-pyusb \
    python-pyserial \
    python-colorama \
    python-pyside6 \
    libusb \
    git
```

---

## Building the RPM Package (Fedora / RHEL)

### 1. Prepare the RPM Build Directory Structure

Ensure the standard `rpmbuild` workspace tree exists in your home directory:

```bash
mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
```

### 2. Generate the Source Tarball

From the root of the `mtkclient` repository, generate the source archive using `git archive`:

```bash
git archive --format=tar.gz --prefix=mtkclient-2.1.4/ HEAD -o ~/rpmbuild/SOURCES/mtkclient-2.1.4.tar.gz
```

Verify that the tarball contains the source tree:

```bash
tar -ztvf ~/rpmbuild/SOURCES/mtkclient-2.1.4.tar.gz | head -n 15
```

### 3. Stage the Spec and Desktop Files

Copy the spec file and desktop entry into the `rpmbuild` tree:

```bash
cp mtkclient.spec ~/rpmbuild/SPECS/
cp mtk_gui.desktop ~/rpmbuild/SOURCES/
```

### 4. Build Binary and Source RPMs

Run `rpmbuild` to build both the binary RPM (`.noarch.rpm`) and the source RPM (`.src.rpm`):

```bash
rpmbuild -ba ~/rpmbuild/SPECS/mtkclient.spec
```

Upon successful compilation, the packages are output to:
- **Binary RPM:** `~/rpmbuild/RPMS/noarch/mtkclient-2.1.4-1.fc*.noarch.rpm`
- **Source RPM (SRPM):** `~/rpmbuild/SRPMS/mtkclient-2.1.4-1.fc*.src.rpm`

### 5. Install the Generated RPM

Install the package directly using `dnf`:

```bash
sudo dnf install ~/rpmbuild/RPMS/noarch/mtkclient-2.1.4-1.fc*.noarch.rpm
```

Or using `rpm`:

```bash
sudo rpm -Uvh ~/rpmbuild/RPMS/noarch/mtkclient-2.1.4-1.fc*.noarch.rpm
```

### 6. Configure Udev Permissions & User Groups

To allow non-root users to communicate with MediaTek devices over USB:

1. Reload the udev subsystem to apply the newly installed rules:
   ```bash
   sudo udevadm control --reload-rules
   sudo udevadm trigger
   ```

2. Add your user account to the `dialout` and `plugdev` groups:
   ```bash
   sudo usermod -aG dialout,plugdev $USER
   ```

3. Log out and log back in (or reboot) for group changes to take full effect.

---

## Standard Python Installation (Alternative)

If you prefer installing directly using Python tools without RPM:

### Using pip (System / User)

```bash
python3 -m pip install .
```

For development / editable mode:

```bash
python3 -m pip install -e .
```

### Using a Virtual Environment (venv)

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pip install .
mtk --help
```

### Using uv (Fast Package Manager)

```bash
uv sync --frozen
uv run mtk --help
```

---

## Package Verification & Testing

### Inspecting the RPM

View detailed package information:

```bash
rpm -qip ~/rpmbuild/RPMS/noarch/mtkclient-2.1.4-*.rpm
```

List all files packaged inside the RPM:

```bash
rpm -qlp ~/rpmbuild/RPMS/noarch/mtkclient-2.1.4-*.rpm
```

### Verifying CLI Tools

Verify the CLI binaries installed to `/usr/bin/`:

```bash
# Print general usage and available subcommands
mtk --help

# Test stage2 exploit utility
stage2 --help

# Verify backward compatibility symlink
mtk.py --help
```

### Verifying GUI Application

Launch the Qt/PySide6 graphical user interface:

```bash
mtk_gui
```

You can also launch **MTK Client GUI** directly from your desktop environment application menu (GNOME / KDE / XFCE).

---

## Troubleshooting & FAQ

### 1. Device Not Detected in BootROM Mode
**Cause:** The device exited BROM mode before `mtkclient` captured the USB handshake.  
**Resolution:**
- Power off the device completely.
- Start the command first (e.g., `mtk printgpt`).
- Hold `Volume Down` (or `Volume Down` + `Power`) and plug in the USB cable.
- Release the buttons once the tool connects.

### 2. Permission Denied on `/dev/bus/usb/...` or `/dev/ttyACM0`
**Cause:** Missing udev rules or user account lacks `dialout`/`plugdev` group membership.  
**Resolution:**
```bash
sudo udevadm control --reload-rules && sudo udevadm trigger
sudo usermod -aG dialout,plugdev $USER
```
Re-plug the USB cable after reloading rules.

### 3. Linux Kernel / ModemManager Interference
**Cause:** The Linux kernel `cdc_acm` driver or `ModemManager` may claim the serial interface before `mtkclient` can communicate with it.  
**Resolution:**
Temporarily stop or mask `ModemManager`:
```bash
sudo systemctl stop ModemManager
```
If using older legacy chipsets (e.g. MT6260 requiring Kamakiri), refer to `Setup/Linux/kernelpatches` for kernel patches.

### 4. PySide6 / GUI Wayland Display Issues
**Cause:** Qt Wayland plugin issues on some desktop environments.  
**Resolution:**
Run with the XWayland or X11 platform fallback:
```bash
QT_QPA_PLATFORM=xcb mtk_gui
```
