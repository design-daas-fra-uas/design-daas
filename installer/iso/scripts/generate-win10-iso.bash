#!/bin/bash

# Default config
VOLNAME=Win10
INCFOLDER=cfg/win10
OUTFOLDER=out
ISOFOLDER=iso
QMSGFOLDER="../../src/app/daas/messaging"
QINSTFOLDER="../../src/app/inst"
ISONAME=${VOLNAME}_22H2_German_x64v1
ISONAME_VIO=virtio-win-0.1.266
OUTNAME=${VOLNAME}-22H2_German_x64_unattend
INFOLDER=$OUTFOLDER/$ISONAME
OUTFILE=$OUTFOLDER/${OUTNAME}
VIRTIOFOLDER=$OUTFOLDER/${ISONAME_VIO}
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

# Help
usage() {
    echo "Usage: $0 " 1>&2
    echo "      [-a <action>] [-n <isoname>]" 1>&2
    echo "      [-u <username>] [-p <userpass>]" 1>&2
    echo "      [-d <outdir>] [-i <incdir>]" 1>&2
    echo "      " 1>&2
    echo "      Action  : [clean,install,download,generate]" 1>&2
    echo "      Isoname : [isoname in ./iso without extension]" 1>&2
    echo "      Username: [Hostname to connect to (Default: localhost)]" 1>&2
    echo "      Userpass: [User name (Default: root)]" 1>&2
    echo "      Outdir  : [Output folder (Default: ./out)]" 1>&2
    echo "      IncDir  : [Include folder (Default: ./config)]" 1>&2
}

# install
toolinstall(){
    sudo -E apt --yes install rsync unzip isolinux genisoimage 1>&2 2>/dev/null
}
# clean
clean(){
    sudo umount "$MNTFOLDER" 1>&2 2>/dev/null
    rm -rf "$INFOLDER" "$MNTFOLDER" "$VIRTIOFOLDER"
    sudo rm -rf "$MODFOLDER"
}

# fetch URL FILE: download FILE once; a failed download leaves no file
# behind (wget -O alone leaves an empty one, which counts as "downloaded")
fetch() {
    [ -s "$2" ] && return 0
    mkdir -p "$(dirname "$2")"
    if wget -O "$2.part" "$1" && [ -s "$2.part" ] ; then
        mv "$2.part" "$2"
    else
        rm -f "$2.part"
        echo "ERROR: download failed: $1" 1>&2
        return 1
    fi
}
# Download
download() {
    mkdir -p "$ISOFOLDER"
    # Microsoft only offers Windows 10 22H2 downloads through a browser page with
    # links that expire after 24h, so the ISO cannot be downloaded here
    if [ ! -s "$ISOFILE" ] ; then
        echo "ERROR: $ISOFILE is missing or empty." 1>&2
        echo "Download Windows 10 22H2 (German, x64) from" 1>&2
        echo "  https://www.microsoft.com/de-de/software-download/windows10ISO" 1>&2
        echo "and save it as $ISOFILE" 1>&2
        return 1
    fi
    fetch "$URL_VIRTIO" "$ISOFILE_VIO"
}
download_tools() {
    mkdir -p "$INCFOLDER/tools"
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

    mkdir -p "$INCFOLDER/env"
    fetch "$URL_PSTOOLS" "$INCFOLDER/env/PSTools.zip" || return 1
    if [ ! -d "$INCFOLDER/env/PSTools" ] ; then
        unzip "$INCFOLDER/env/PSTools.zip" -d "$INCFOLDER/env/PSTools"
    fi
    # Office is not installed (its line in postinstall.bat is commented out):
    # put a licensed Office Deployment Tool setup in tools/office to use it
}

# Mount and extract
copybase(){
    mkdir -p "$MNTFOLDER" "$INFOLDER"
    sudo mount -o loop "$ISOFILE" "$MNTFOLDER"
    rsync -a -H --exclude=TRANS.TBL "$MNTFOLDER"/ "$INFOLDER"
    chmod 755 -R "$INFOLDER"
    sudo umount "$MNTFOLDER"

    sudo mount -o loop "$ISOFILE_VIO" "$MNTFOLDER"
    rsync -a -H --exclude=TRANS.TBL "$MNTFOLDER"/ "$VIRTIOFOLDER"
    chmod 755 -R "$VIRTIOFOLDER"
    sudo umount "$MNTFOLDER"
    sudo rm -rf "$MNTFOLDER"
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

# Copy addons
copyaddons(){
    copykeys
    mkdir -p "$INFOLDER"/postinstall/daas
    mkdir -p "$INFOLDER"/postinstall/daas/env
    cp -r "$INCFOLDER"/env -t "$INFOLDER"/postinstall/
    cp -r "$INCFOLDER"/tools -t "$INFOLDER"/postinstall/
    cp -r "$INCFOLDER"/postinstall/*.bat -t "$INFOLDER"/postinstall/
    cp -r "$INCFOLDER"/postinstall/*.ps1 -t "$INFOLDER"/postinstall/
    cp -r "$INCFOLDER"/postinstall/daas.jpg "$INFOLDER"/postinstall/daas.jpg
    cp -r "$INCFOLDER"/postinstall/daas-logo.png "$INFOLDER"/postinstall/daas-logo.png
    cp -r "$INCFOLDER"/autounattend.xml "$INFOLDER"/autounattend.xml
    cp -r "$QMSGFOLDER"/* "$INFOLDER"/postinstall/daas/
    cp -r "$QINSTFOLDER"/* "$INFOLDER"/postinstall/daas/env
    cp -r "$VIRTIOFOLDER" "$INFOLDER"/virtio
}

updateuser() {
    sed "s#<Name>user</Name>#<Name>$USERNAME</Name>#g" \
         -i "$INFOLDER/autounattend.xml"
    sed "s#<Username>user</Username>#<Username>$USERNAME</Username>#g" \
         -i "$INFOLDER/autounattend.xml"
    sed "s#<UserName>user</UserName>#<UserName>$USERNAME</UserName>#g" \
         -i "$INFOLDER/autounattend.xml"
    sed "s#<FullName>user</FullName>#<FullName>$USERNAME</FullName>#g" \
         -i "$INFOLDER/autounattend.xml"
    sed "s#<DisplayName>user</DisplayName>#<DisplayName>$USERNAME</DisplayName>#g" \
         -i "$INFOLDER/autounattend.xml"
    sed "s#<RegisteredOwner>user</RegisteredOwner>#<RegisteredOwner>$USERNAME</RegisteredOwner>#g" \
         -i "$INFOLDER/autounattend.xml"
    sed "s#<Value>user</Value>#<Value>$ROOTPASS</Value>#g" \
         -i "$INFOLDER/autounattend.xml"
    sed "s#C:\\\\Users\\\\user\\\\#C:\\\\Users\\\\$USERNAME\\\\#g" \
         -i "$INFOLDER/postinstall/postinstall.bat"
}

# Generate iso
geniso(){
	mkdir -p "$OUTFOLDER"
	mkisofs  -allow-limited-size \
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
	#sudo rm -rf $(DATAFOLDER)
}

# Read params
while getopts ":a:u:p:d:i:n:" o; do
    case "$o" in
        a)
            ACTION=${OPTARG}
            ;;
        u)
            USERNAME=${OPTARG}
            ;;
        p)
            ROOTPASS=${OPTARG}
            ;;
        d)
            OUTFOLDER=${OPTARG}
            ;;
        i)
            INCFOLDER=${OPTARG}
            ;;
        n)
            OUTNAME=${OPTARG}
            ;;
        *)
            ;;
    esac
done
shift $((OPTIND-1))

# Dynamic vars
MNTFOLDER=$OUTFOLDER/mnt
MODFOLDER=$OUTFOLDER/irmod
INFOLDER=$OUTFOLDER/$ISONAME
VIRTIOFOLDER=$OUTFOLDER/${ISONAME_VIO}
ISOFILE=$ISOFOLDER/${ISONAME}.iso
ISOFILE_VIO=$ISOFOLDER/${ISONAME_VIO}.iso
OUTFILE=$ISOFOLDER/${OUTNAME}

# Execute action
case "$ACTION" in
    "clean")
        [[ -z "$ISONAME" ]] && echo "No Isoname specified" && usage && exit 1
        clean
        ;;
    "install")
        [[ -z "$ISONAME" ]] && echo "No Isoname specified" && usage && exit 1
        toolinstall
        ;;
    "download")
        [[ -z "$ISONAME" ]] && echo "No Isoname specified" && usage && exit 1
        download || exit 1
        download_tools || exit 1
        ;;
    "generate")
        [[ -z "$ISONAME" ]] && echo "No Isoname specified" && usage && exit 1
        clean
        #toolinstall
        download || exit 1
        download_tools || exit 1
        copybase
        copyaddons
        updateuser
        geniso
        ;;
     *)
        echo "Not a valid target: '$1'"
        ;;
esac
