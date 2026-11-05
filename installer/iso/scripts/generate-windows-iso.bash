#!/bin/bash
#
# Builds the unattended Windows install ISO (Windows 10 or 11) for DaaS VMs,
# see ../README.md. Downloads everything it needs once:
#   - the Windows 10/11 Enterprise Evaluation ISO from Microsoft (stable
#     official links; 90-day evaluation, no product key)
#   - the virtio drivers and the tools the VM installs (Python, Firefox, ...)
# and adds cfg/winNN (autounattend.xml, postinstall/, ssh/), the DaaS agent
# and the host's public ssh key.
#
# Usage: generate-windows-iso.bash -v <10|11> -a <clean|install|download|generate>
#            [-n <outname>] [-u <username>] [-p <password>] [-d <outdir>] [-i <incdir>]

# ============================================================
# Per version
# ============================================================

# Windows 10 22H2 Enterprise Evaluation, German
WIN10_URL="https://go.microsoft.com/fwlink/p/?LinkID=2208844&clcid=0x407&culture=de-de&country=DE"
WIN10_ISO="Win10_22H2_EnterpriseEval_x64_de-de"
# Windows 11 24H2 Enterprise Evaluation: Microsoft's stable link only has it
# in English (German keyboard and formats are set in autounattend.xml)
WIN11_URL="https://go.microsoft.com/fwlink/?linkid=2289031&clcid=0x409&culture=en-us&country=us"
WIN11_ISO="Win11_24H2_EnterpriseEval_x64_en-us"

# ============================================================
# Common
# ============================================================

OUTFOLDER=out
ISOFOLDER=iso
QMSGFOLDER="../../src/app/daas/messaging"
QINSTFOLDER="../../src/app/inst"
ISONAME_VIO=virtio-win-0.1.266
URL_VIRTIO="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.266-1/virtio-win-0.1.266.iso"
URL_PYTHON="https://www.python.org/ftp/python/3.11.4/python-3.11.4-amd64.exe"
URL_FIREFOX="https://download-installer.cdn.mozilla.net/pub/firefox/releases/115.0.3/win64/de/Firefox%20Setup%20115.0.3.msi"
URL_PSTOOLS="https://download.sysinternals.com/files/PSTools.zip"
URL_TIGHTVNC="https://www.tightvnc.com/download/2.8.81/tightvnc-2.8.81-gpl-setup-64bit.msi"
URL_WINGET="https://aka.ms/getwinget"
URL_VCLIBS="https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
URL_XAML="https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx"
URL_CEPH="https://cloudbase.it/downloads/ceph_reef_beta.msi"
URL_DOKANY1="https://github.com/dokan-dev/dokany/releases/download/v1.0.5/Dokan_x64-1.0.5.1000.msi"
URL_DOKANY2="https://github.com/dokan-dev/dokany/releases/download/v2.1.0.1000/Dokan_x64.msi"
URL_DOKANYSETUP="https://github.com/dokan-dev/dokany/releases/download/v1.0.5/DokanSetupDbg_redist-1.0.5.1000.exe"
USERNAME=root
ROOTPASS=root
export DEBIAN_FRONTEND=noninteractive

usage() {
    cat <<EOF 1>&2
Usage: $0 -v <10|11> -a <clean|install|download|generate>
          [-n <outname>] [-u <username>] [-p <password>] [-d <outdir>] [-i <incdir>]

    -v  Windows version: 10 or 11
    -a  clean | install (tools) | download (ISOs, tools) | generate (the ISO)
    -n  Output name in ./iso, without .iso (default: winNN-daas)
    -u  Account created in the VM (default: root)
    -p  Its password (default: root)
    -d  Build folder (default: ./out)
    -i  Config folder (default: cfg/winNN)
EOF
}

toolinstall(){
    sudo -E apt --yes install rsync unzip isolinux genisoimage curl 1>&2 2>/dev/null
}

clean(){
    sudo umount "$MNTFOLDER" 1>&2 2>/dev/null
    rm -rf "$INFOLDER" "$MNTFOLDER" "$VIRTIOFOLDER"
}

# fetch URL FILE: download FILE once; a failed download leaves no file
# behind, an interrupted one is continued on the next run (.part)
fetch() {
    [ -s "$2" ] && return 0
    mkdir -p "$(dirname "$2")"
    if curl -fL --retry 3 -C - -o "$2.part" "$1" && [ -s "$2.part" ] ; then
        mv "$2.part" "$2"
    else
        echo "ERROR: download failed: $1 (run again to continue it)" 1>&2
        return 1
    fi
}

# check_windows_iso FILE: is FILE a complete Windows install ISO?
check_windows_iso(){
    local mnt ok=1
    mnt="$(mktemp -d)"
    if sudo mount -o loop,ro "$1" "$mnt" 2>/dev/null; then
        [ -f "$mnt/boot/etfsboot.com" ] && { [ -f "$mnt/sources/install.wim" ] || [ -f "$mnt/sources/install.esd" ]; } && ok=0
        sudo umount "$mnt"
    fi
    rmdir "$mnt"
    return $ok
}

download() {
    mkdir -p "$ISOFOLDER"
    if [ ! -s "$ISOFILE" ] ; then
        echo "Downloading Windows $VERSION Enterprise Evaluation (about 5.5 GB) from Microsoft"
        fetch "$URL_WIN" "$ISOFILE" || return 1
    fi
    if ! check_windows_iso "$ISOFILE" ; then
        echo "ERROR: $ISOFILE is not a complete Windows ISO; delete it and run again" 1>&2
        return 1
    fi
    fetch "$URL_VIRTIO" "$ISOFILE_VIO"
}

download_tools() {
    mkdir -p "$INCFOLDER/tools" "$INCFOLDER/env"
    fetch "$URL_PYTHON" "$INCFOLDER/tools/python-3.11.4-amd64.exe" || return 1
    fetch "$URL_FIREFOX" "$INCFOLDER/tools/Firefox_Setup_115.0.3.msi" || return 1
    fetch "$URL_TIGHTVNC" "$INCFOLDER/tools/tightvnc-2.8.81-gpl-setup-64bit.msi" || return 1
    fetch "$URL_WINGET" "$INCFOLDER/tools/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" || return 1
    fetch "$URL_VCLIBS" "$INCFOLDER/tools/Microsoft.VCLibs.x64.14.00.Desktop.appx" || return 1
    fetch "$URL_XAML" "$INCFOLDER/tools/Microsoft.UI.Xaml.2.8.x64.appx" || return 1
    fetch "$URL_CEPH" "$INCFOLDER/tools/ceph_reef_beta.msi" || return 1
    fetch "$URL_DOKANY1" "$INCFOLDER/tools/Dokan_x64-1.0.5.1000.msi" || return 1
    fetch "$URL_DOKANY2" "$INCFOLDER/tools/Dokan_x64.msi" || return 1
    fetch "$URL_DOKANYSETUP" "$INCFOLDER/tools/DokanSetup_redist-1.0.5.1000.exe" || return 1
    fetch "$URL_PSTOOLS" "$INCFOLDER/env/PSTools.zip" || return 1
    if [ ! -d "$INCFOLDER/env/PSTools" ] ; then
        unzip -q "$INCFOLDER/env/PSTools.zip" -d "$INCFOLDER/env/PSTools"
    fi
    # Office is not installed (its line in postinstall.bat is commented out):
    # put a licensed Office Deployment Tool setup in tools/office to use it
}

# Mount and extract the Windows and virtio ISOs
copybase(){
    mkdir -p "$MNTFOLDER" "$INFOLDER"
    sudo mount -o loop,ro "$ISOFILE" "$MNTFOLDER"
    rsync -a -H --exclude=TRANS.TBL "$MNTFOLDER"/ "$INFOLDER"
    chmod 755 -R "$INFOLDER"
    sudo umount "$MNTFOLDER"

    sudo mount -o loop,ro "$ISOFILE_VIO" "$MNTFOLDER"
    rsync -a -H --exclude=TRANS.TBL "$MNTFOLDER"/ "$VIRTIOFOLDER"
    chmod 755 -R "$VIRTIOFOLDER"
    sudo umount "$MNTFOLDER"
    rm -rf "$MNTFOLDER"
}

# Only the host's PUBLIC key goes into the ISO (as authorized_keys, so the
# backend can log in to the VM). The private key must never leave the host:
# anyone with a VM could otherwise log in to the host as root.
copykeys(){
    if [[ ! -r /root/.ssh/id_rsa.pub ]] ; then
        echo "Missing /root/.ssh/id_rsa.pub: run 'make deps' in installer/" 1>&2
        exit 1
    fi
    mkdir -p "$INFOLDER"/postinstall/ssh
    cp "$INCFOLDER"/ssh/sshd_config "$INFOLDER"/postinstall/ssh/
    cp /root/.ssh/id_rsa.pub "$INFOLDER"/postinstall/ssh/id_rsa.pub
    cp /root/.ssh/id_rsa.pub "$INFOLDER"/postinstall/ssh/authorized_keys
}

copyaddons(){
    copykeys
    mkdir -p "$INFOLDER"/postinstall/daas/env
    cp -r "$INCFOLDER"/env -t "$INFOLDER"/postinstall/
    cp -r "$INCFOLDER"/tools -t "$INFOLDER"/postinstall/
    cp -r "$INCFOLDER"/postinstall/*.bat -t "$INFOLDER"/postinstall/
    cp -r "$INCFOLDER"/postinstall/*.ps1 -t "$INFOLDER"/postinstall/
    cp -r "$INCFOLDER"/postinstall/daas.jpg "$INCFOLDER"/postinstall/daas-logo.png -t "$INFOLDER"/postinstall/
    cp -r "$INCFOLDER"/autounattend.xml "$INFOLDER"/autounattend.xml
    cp -r "$QMSGFOLDER"/* "$INFOLDER"/postinstall/daas/
    cp -r "$QINSTFOLDER"/* "$INFOLDER"/postinstall/daas/env
    cp -r "$VIRTIOFOLDER" "$INFOLDER"/virtio
}

# The account in autounattend.xml is "user"; its home folder in the
# postinstall scripts is C:\Users\user\ (win10) or C:\Users\root\ (win11)
updateuser() {
    local tag
    for tag in Name Username UserName FullName DisplayName RegisteredOwner; do
        sed "s#<$tag>user</$tag>#<$tag>$USERNAME</$tag>#g" -i "$INFOLDER/autounattend.xml"
    done
    sed "s#<Value>user</Value>#<Value>$ROOTPASS</Value>#g" -i "$INFOLDER/autounattend.xml"
    sed -E "s#C:\\\\Users\\\\(user|root)\\\\#C:\\\\Users\\\\$USERNAME\\\\#g" \
        -i "$INFOLDER/postinstall/postinstall.bat"
}

geniso(){
    mkisofs -allow-limited-size \
        -V "$VOLNAME" \
        -no-emul-boot \
        -b boot/etfsboot.com \
        -boot-load-seg 0x07C0 \
        -boot-load-size 8 \
        -iso-level 2 \
        -udf \
        -joliet \
        -D \
        -N \
        -relaxed-filenames \
        -o "$OUTFILE".iso \
        "$INFOLDER"
}

VERSION=""
ACTION=""
OUTNAME=""
INCFOLDER=""
while getopts ":v:a:u:p:d:i:n:" o; do
    case "$o" in
        v) VERSION=${OPTARG} ;;
        a) ACTION=${OPTARG} ;;
        u) USERNAME=${OPTARG} ;;
        p) ROOTPASS=${OPTARG} ;;
        d) OUTFOLDER=${OPTARG} ;;
        i) INCFOLDER=${OPTARG} ;;
        n) OUTNAME=${OPTARG} ;;
        *) usage; exit 1 ;;
    esac
done
shift $((OPTIND-1))

case "$VERSION" in
    10) URL_WIN="$WIN10_URL"; ISONAME="$WIN10_ISO" ;;
    11) URL_WIN="$WIN11_URL"; ISONAME="$WIN11_ISO" ;;
    *)  usage; exit 1 ;;
esac
VOLNAME="Win$VERSION"
INCFOLDER="${INCFOLDER:-cfg/win$VERSION}"
OUTNAME="${OUTNAME:-win$VERSION-daas}"
MNTFOLDER=$OUTFOLDER/mnt
INFOLDER=$OUTFOLDER/$ISONAME
VIRTIOFOLDER=$OUTFOLDER/${ISONAME_VIO}
ISOFILE=$ISOFOLDER/${ISONAME}.iso
ISOFILE_VIO=$ISOFOLDER/${ISONAME_VIO}.iso
OUTFILE=$ISOFOLDER/${OUTNAME}

case "$ACTION" in
    clean)    clean ;;
    install)  toolinstall ;;
    download) download || exit 1; download_tools || exit 1 ;;
    generate)
        clean
        download || exit 1
        download_tools || exit 1
        copybase
        copyaddons
        updateuser
        geniso
        ;;
    *) usage; exit 1 ;;
esac
