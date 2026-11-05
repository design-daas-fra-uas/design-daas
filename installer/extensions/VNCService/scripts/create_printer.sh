#!/bin/sh

NAME="$1"
OUT_DIR="/usr/src/app/files/$NAME"
CONFIG_FILE="/etc/cups/cups-pdf-$NAME.conf"

# Prepare folder
if [ -d "$OUT_DIR" ]; then
    echo "Directory $OUT_DIR already exists."
else
    mkdir -p "$OUT_DIR"
    chmod -R 777 "$OUT_DIR"
fi

# Add config file
if [ -f "$CONFIG_FILE" ]; then
    echo "Config file $CONFIG_FILE already exists."
else
    cp "/etc/cups/cups-pdf.conf" "$CONFIG_FILE"
    sed -i "s/Out \${HOME}\/PDF/Out \/usr\/src\/app\/files\/$NAME/g" "$CONFIG_FILE"
    sed -i "s/#AnonDirName \/var\/spool\/cups-pdf\/ANONYMOUS/AnonDirName \/usr\/src\/app\/files\/$NAME/g" "$CONFIG_FILE"
    sed -i "s/#PostProcessing/PostProcessing \/usr\/src\/app\/scripts\/postprocess.sh/g" "$CONFIG_FILE"
fi

# Add printer
if lpstat -p "$NAME" > /dev/null 2>&1; then
  echo "Printer $NAME already exists."
else
    # The cups-pdf driver file is CUPS-PDF_opt.ppd (Ubuntu 22.04) or
    # CUPS-PDF_noopt.ppd (24.04)
    PPD="$(ls /usr/share/ppd/cups-pdf/CUPS-PDF_*.ppd | head -n1)"
    lpadmin -p "$NAME" -v "cups-pdf:/$NAME" -E -P "$PPD"
    cupsaccept "$NAME"
    lpadmin -p "$NAME" -o printer-is-shared=true
fi

exit 0
