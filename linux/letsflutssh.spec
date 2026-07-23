Name:           letsflutssh
Version:        __VERSION__
Release:        1%{?dist}
Summary:        Lightweight cross-platform SSH/SFTP client
License:        MIT
URL:            https://github.com/Llloooggg/LetsFLUTssh

%global _buildrootpath /tmp

%description
A full-featured SSH terminal and SFTP file browser with session
management, encrypted credential storage, and tiling terminal layout.

%install
mkdir -p %{buildroot}/usr/lib/letsflutssh
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/icons/hicolor/256x256/apps
mkdir -p %{buildroot}/usr/lib/udev/rules.d
cp -a %{_builddir}/letsflutssh-%{version}/* %{buildroot}/usr/lib/letsflutssh/
ln -sf /usr/lib/letsflutssh/letsflutssh %{buildroot}/usr/bin/letsflutssh
cp /tmp/SOURCES/letsflutssh.desktop %{buildroot}/usr/share/applications/
cp /tmp/SOURCES/letsflutssh.png %{buildroot}/usr/share/icons/hicolor/256x256/apps/
cp /tmp/SOURCES/70-letsflutssh-fido.rules %{buildroot}/usr/lib/udev/rules.d/

%files
/usr/lib/letsflutssh
/usr/bin/letsflutssh
/usr/share/applications/letsflutssh.desktop
/usr/share/icons/hicolor/256x256/apps/letsflutssh.png
/usr/lib/udev/rules.d/70-letsflutssh-fido.rules

%post
/usr/bin/letsflutssh --help >/dev/null 2>&1 || true
