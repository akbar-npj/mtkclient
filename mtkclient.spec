Name:           mtkclient
Version:        2.1.4
Release:        1%{?dist}
Summary:        MediaTek reverse engineering and flashing tools

License:        GPL-3.0-or-later
URL:            https://github.com/bkerler/mtkclient
Source0:        %{name}-%{version}.tar.gz
Source1:        mtk_gui.desktop

BuildArch:      noarch

BuildRequires:  python3-devel
BuildRequires:  python3-pip
BuildRequires:  python3-setuptools
BuildRequires:  desktop-file-utils
BuildRequires:  systemd-rpm-macros

Requires:       python3
Requires:       python3-pyusb
Requires:       python3-pycryptodomex
Requires:       python3-colorama
Requires:       python3-pyserial

Recommends:     python3-pyside6
Recommends:     python3-shiboken6
Recommends:     python3-fusepy

# Filter out unresolvable / optional python dependencies in Fedora
%global __requires_exclude ^python3(\.[0-9]+)?dist\\((mfusepy|pycryptodome)\\)

%description
mtkclient is a reverse engineering and flashing toolkit for MediaTek (MTK)
SoCs. It supports reading/writing flash partitions, dumping bootroms,
bypassing security SLA/DAA, exploiting bootrom vulnerabilities (kamakiri,
ammonite, etc.), reading/writing RPMB, erasing partitions, and more.

Both CLI (mtk, stage2, da_parser, brom_to_offs) and GUI (mtk_gui) interfaces
are provided, along with standard udev rules for MediaTek USB devices.

%prep
%autosetup -p1 -n %{name}-%{version}

%build
%pyproject_wheel

%install
%pyproject_install

# Remove force-included top-level files from site-packages
rm -f %{buildroot}%{python3_sitelib}/LICENSE
rm -f %{buildroot}%{python3_sitelib}/README.md

# Install symlinks for .py command names
ln -s mtk %{buildroot}%{_bindir}/mtk.py
ln -s mtk_gui %{buildroot}%{_bindir}/mtk_gui.py
ln -s stage2 %{buildroot}%{_bindir}/stage2.py

# Install udev rules
install -D -p -m 0644 Setup/Linux/52-mtk.rules %{buildroot}%{_udevrulesdir}/52-mtk.rules
install -D -p -m 0644 Setup/Linux/51-edl.rules %{buildroot}%{_udevrulesdir}/51-edl.rules

# Install desktop file and icons for GUI
install -D -p -m 0644 %{SOURCE1} %{buildroot}%{_datadir}/applications/mtk_gui.desktop
desktop-file-validate %{buildroot}%{_datadir}/applications/mtk_gui.desktop

install -D -p -m 0644 mtkclient/gui/images/logo_256.png %{buildroot}%{_datadir}/icons/hicolor/256x256/apps/mtkclient.png
install -D -p -m 0644 mtkclient/gui/images/logo_64.png %{buildroot}%{_datadir}/icons/hicolor/64x64/apps/mtkclient.png
install -D -p -m 0644 mtkclient/gui/images/logo_32.png %{buildroot}%{_datadir}/icons/hicolor/32x32/apps/mtkclient.png

%check
test -x %{buildroot}%{_bindir}/mtk
test -x %{buildroot}%{_bindir}/mtk_gui
test -x %{buildroot}%{_bindir}/stage2
test -f %{buildroot}%{_udevrulesdir}/52-mtk.rules
desktop-file-validate %{buildroot}%{_datadir}/applications/mtk_gui.desktop
PYTHONPATH=%{buildroot}%{python3_sitelib} %{python3} -c "import mtkclient; print('mtkclient import test passed')"

%files
%license LICENSE
%doc README.md README-USAGE.md README-INSTALL.md
%{_bindir}/mtk
%{_bindir}/mtk.py
%{_bindir}/mtk_gui
%{_bindir}/mtk_gui.py
%{_bindir}/stage2
%{_bindir}/stage2.py
%{_bindir}/da_parser
%{_bindir}/brom_to_offs
%{python3_sitelib}/mtkclient
%{python3_sitelib}/mtkclient-%{version}.dist-info
%{_udevrulesdir}/52-mtk.rules
%{_udevrulesdir}/51-edl.rules
%{_datadir}/applications/mtk_gui.desktop
%{_datadir}/icons/hicolor/*/apps/mtkclient.png

%changelog
* Fri Oct 02 2026 akbar_npj <akbar.npj@protonmail.com> - 2.1.4-1
- Initial RPM package for Fedora Asahi Remix
