# Flashing Debian (OpenStick) on the UZ801 USB modem

This is the procedure used to replace the stock Android firmware of a **UZ801 / FY_UZ801_V3.2**
4G USB modem (Qualcomm **MSM8916**) with **Debian 12 (OpenStick)**, get LTE working again and
install `openstick-config`. It was done from a Debian 13 x86_64 PC ("the host").

> **Warning.** This wipes Android and rewrites the partition table and bootloaders. A mistake can
> leave the stick unbootable (recoverable only through EDL) or **lose the radio calibration and
> IMEI**, which cannot be recreated. Do the backup in step 2 and keep it somewhere safe.

## What you get

| Before | After |
|---|---|
| Android 4.4.4, kernel 3.10.28, firmware V2.3.15 | Debian 12 Bookworm, kernel 6.7.0-rc4-msm8916 |
| Web UI hotspot stick | Full Linux box: SSH, NetworkManager, ModemManager, Tailscale, … |

Hardware seen on this unit: ~381 MiB RAM usable, 3.6 GiB eMMC, Wi-Fi 2.4 GHz only,
LTE bands 1/3/5/7/8/20/38/40/41 + UMTS 1/8 (no 2G).

## Requirements

- Host PC with `adb`, `fastboot`, `python3`, `git` (`sudo apt install adb fastboot python3-venv git`)
- [bkerler/edl](https://github.com/bkerler/edl) for the EDL backup
- The OpenStick image for this board: `openstick-uz801-v3.0.zip`
  (referenced by the [UZ801 Debian wiki](https://github.com/AlienWolfX/UZ801-USB-MODEM/wiki/Debian);
  background: [OpenStick](https://github.com/OpenStick/OpenStick),
  [OpenStick-Builder](https://github.com/kinsamanka/OpenStick-Builder))
- ~4 GB free space on the host for the full backup
- A **5 V / 2 A** supply if you later use a powered USB hub (a power bank caused crashes)

## 1. Check the stick

Plug the stick into the host. The stock firmware exposes ADB, and on this unit ADB already ran
as root:

```bash
adb devices
adb shell getprop ro.product.model       # UZ801
adb shell getprop ro.build.version.release   # 4.4.4
adb shell cat /proc/partitions           # mmcblk0 ≈ 3.6 GiB
```

## 2. Full backup through EDL (do not skip)

EDL (Qualcomm Emergency Download) reads the eMMC while Android is stopped, so nothing changes
during the copy.

```bash
git clone https://github.com/bkerler/edl && cd edl
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt

adb reboot edl                 # usual way into EDL on this stick (05c6:9008 appears in lsusb)
.venv/bin/python edl.py printgpt --memory=emmc
.venv/bin/python edl.py rf uz801-stock.bin --memory=emmc      # whole user area (~3.9 GB, ~14 min)
.venv/bin/python edl.py rl partitions/ --memory=emmc --genxml # every partition as a file
.venv/bin/python edl.py reset
sha256sum uz801-stock.bin partitions/* > SHA256SUMS
```

Our dump: **3,875,536,896 bytes, 27 partitions, both GPT CRCs valid**. Keep also the firehose
loader that worked for your unit (`edl` prints which one it used).

The partitions that matter most are the radio ones:

| Partition | Contents |
|---|---|
| `modemst1`, `modemst2` | Radio EFS working copies: IMEI, RF calibration, network settings |
| `fsg` | "Golden" EFS copy |
| `fsc` | EFS cookie / sync data |
| `modem` | Radio firmware (FAT image, `image/modem.*`, `mba.mbn`) — needed in step 5 |

## 3. Unpack the image

```bash
unzip openstick-uz801-v3.0.zip -d openstick && cd openstick
ls base debian       # base/: gpt_both0.bin aboot.bin hyp.mbn rpm.mbn sbl1.mbn tz.mbn sbc_1.0_8016.bin
                     # debian/: boot.img rootfs.img
```

The bundled `flash.sh` does the same as below but would overwrite the radio partitions with
generic ones. The sequence here restores **your own** `fsc`, `fsg`, `modemst1`, `modemst2`
from step 2 instead.

## 4. Flash

```bash
adb reboot bootloader
fastboot devices                    # note the serial, used as -s below
fb() { fastboot -s <serial> "$@"; }

fb flash partition base/gpt_both0.bin               # new partition table
for p in hyp rpm sbl1 tz; do fb flash $p base/$p.mbn; done
for p in fsc fsg modemst1 modemst2; do fb flash $p ../backup/partitions/$p.bin; done   # your radio data
fb flash aboot base/aboot.bin
fb flash cdt base/sbc_1.0_8016.bin
fb erase boot
fb erase rootfs
fb reboot                           # comes back in fastboot with the new bootloader
sleep 5; fb getvar product

fastboot -s <serial> -S 200M flash rootfs debian/rootfs.img   # sparse, ~8 min
fb flash boot debian/boot.img
fb reboot
```

## 5. First boot

The stick now enumerates as a USB network gadget (`1d6b:0104`).

| Access | Address | Default login |
|---|---|---|
| USB network | modem `192.168.200.1` (host needs an IP in `192.168.200.0/24`) | `user` / `1` |
| Built-in hotspot | SSID `4G-UFI-XX`, password `1234567890`, modem `192.168.100.1` | `user` / `1` |

If the host has no DHCP client, give it an address by hand:

```bash
sudo ip addr add 192.168.200.100/24 dev enx<mac-of-gadget>
ssh user@192.168.200.1
```

**Change the default password right away** (or create your own sudo user and delete `user`).

Join your Wi-Fi (the hotspot and the Wi-Fi client share the radio, so stop the hotspot first):

```bash
sudo nmcli con modify hotspot connection.autoconnect no
sudo nmcli con down hotspot
sudo nmcli dev wifi connect "<SSID>" password "<password>"
```

Run these from the USB link or with `nohup`, because the hotspot link drops.

## 6. Fix LTE: use the stock radio firmware

With the firmware bundled in the image the radio stayed **offline**:

```text
$ mmcli -m 0 -e
error: couldn't enable the modem: ... QMI protocol error (52): 'DeviceNotReady'
$ qmicli -d /dev/wwan0qmi0 --dms-get-operating-mode
	Mode: 'offline'
```

The bundled `/lib/firmware/modem.*` did not match this board's EFS. Copy the stock radio
firmware out of the `modem` partition backup (on the host):

```bash
sudo mount -o loop,ro backup/partitions/modem.bin /mnt
cd /mnt/image && tar cf /tmp/stockmodem.tar mba.mbn modem.mdt modem.b* modem_pr
scp /tmp/stockmodem.tar <user>@<modem>:/tmp/
```

On the stick:

```bash
sudo mkdir -p /root/firmware-orig
sudo cp -a /lib/firmware/mba.mbn /lib/firmware/modem.* /root/firmware-orig/   # keep the original
sudo rm -f /lib/firmware/modem.b* /lib/firmware/modem.mdt
sudo tar xf /tmp/stockmodem.tar -C /lib/firmware
sudo reboot
```

After the reboot `qmicli --dms-get-operating-mode` reports `online` and the `lte` connection comes
up by itself (APN `internet` for XL; change it with
`sudo nmcli con modify lte gsm.apn <apn>`). Our unit used `MPSS.DPM.1.0.1.C1-00121`.

## 7. Install openstick-config

```bash
sudo apt install git
git clone https://github.com/murdokoja-max/openstick-config.git
cd openstick-config
sudo ./install.sh --with-usb-host --with-sms    # options are optional, see README
sudo openstick-config
```

Recommended first steps in the menu: **System › Timezone** (the image ships with
`Europe/Amsterdam`), **System › Password**, **Network › Hotspot › Password**.

Optional: Tailscale for access from anywhere —
`curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up`.

## 8. Backup the identity again

The radio writes to its EFS while running, and the new partition layout differs from the stock
one (`modemst` is 2 MiB instead of 1.5 MiB, no `persist`). Keep a second backup from Debian:

```bash
D=/root/idbackup-$(date +%Y%m%d); sudo mkdir -p $D
for p in modemst1 modemst2 fsg fsc devinfo; do
  sudo dd if=/dev/disk/by-partlabel/$p of=$D/$p.bin bs=1M status=none
done
sudo cp /lib/firmware/wlan/prima/WCNSS_qcom_wlan_nv.bin $D/
sudo sh -c "cd $D && sha256sum * > SHA256SUMS"
sudo tar czf $D.tgz -C /root $(basename $D)      # copy this file off the stick
```

Restore a partition with `dd of=/dev/disk/by-partlabel/<name>` on the same layout.

## Going back to Android

Restore the full EDL dump from step 2 (destructive, overwrites everything):

```bash
cd edl
.venv/bin/python edl.py wf ../backup/uz801-stock.bin --memory=emmc --loader=<your-firehose-loader.bin>
.venv/bin/python edl.py reset
```

This restores the eMMC user area, not RPMB or the separate eMMC boot areas.

## Known issues on this unit

| Issue | Cause / workaround |
|---|---|
| Crashes and reboots in USB host mode | Weak supply (power bank). Use a 5 V / 2 A adapter on the hub |
| Wi-Fi "authentication timed out" although signal is 99 % | Overheating (~60 °C+). LTE data is the main heat source; add airflow |
| LTE connected with IPv6 only | IPv4 data call rejected (`CallFailed`); reconnect. `openstick-smsd` does it automatically |
| Hotspot clients have no internet | `net.ipv4.ip_forward` disabled in the image; `openstick-config` enables it |
| Incoming SMS and calls never arrive (XL, Indonesia) | 4G only, no 2G and the operator's 3G is off. Outgoing SMS works |
| No policy routing, no USB-serial drivers | Not enabled in the image kernel |
| Many `wwan1`–`wwan7` interfaces | Fixed BAM-DMUX data channels of the MSM8916 driver; harmless, cannot be removed |

**IMEI** is shown for reference only. Changing it is illegal in Indonesia and many other countries.
