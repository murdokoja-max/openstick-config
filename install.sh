#!/bin/bash
# Install openstick-config and its helpers on an OpenStick (Debian) device.
# Usage: sudo ./install.sh [--with-usb-host] [--with-sms]
#   --with-usb-host  enable usb-host.service (USB port in host mode at boot)
#   --with-sms       enable openstick-smsd (SMS remote control + LTE IPv4 watchdog)
set -e
[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0 $*"; exit 1; }
cd "$(dirname "$0")"

command -v whiptail >/dev/null || apt-get install -y whiptail

install -m 755 bin/openstick-config bin/openstick-smsd /usr/local/bin/
install -m 644 systemd/usb-host.service systemd/openstick-smsd.service /etc/systemd/system/
[ -f /etc/openstick-sms.conf ] || install -m 600 etc/openstick-sms.conf.example /etc/openstick-sms.conf
systemctl daemon-reload

for arg in "$@"; do
  case $arg in
    --with-usb-host) systemctl enable usb-host.service ;;
    --with-sms)      systemctl enable --now openstick-smsd.service ;;
  esac
done

echo "Installed. Run: sudo openstick-config"
