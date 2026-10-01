# openstick-config

A `raspi-config` style text menu for **OpenStick** USB modems (Qualcomm MSM8916, tested on the
**UZ801 / FY_UZ801_V3.2**) running Debian. It puts Wi-Fi, hotspot, LTE, USB LAN, USB mode,
Tailscale and basic system settings in one place, with the live state shown on every menu row.

```
openstick · LTE connected · Wi-Fi disabled · modem 52C
  1) Status         overview of all connections
  2) Network        Wi-Fi · Hotspot · LTE · LAN · USB · Tailscale
  3) SMS control    active · whitelist: +6281234567890
  4) USB mode       host · boot: host
  5) System         password · hostname · timezone · reboot
  6) About          openstick-config 2.0
```

```
Network
  1) Wi-Fi          on · HomeWiFi · 192.168.1.50/24
  2) Hotspot        off
  3) LTE modem      connected · XL Axiata · 100% · 10.20.30.40/30
  4) LAN            up · 192.168.1.51/24
  5) USB network    unavailable (USB in host mode)
  6) Tailscale      100.101.102.103
```

## Features

| Menu | What you can do |
|---|---|
| **Status** | One screen with system, temperatures, every network link (LTE IPv4 + IPv6), USB and SMS state. Also available without the menu: `openstick-config --status` |
| **Network › Wi-Fi** | Radio on/off, scan and connect, forget networks, DHCP/static IP |
| **Network › Hotspot** | On/off, SSID and password shown and editable, start at boot, connected clients, internet source (LTE first or LAN/Wi-Fi first) |
| **Network › LTE modem** | Mobile data on/off (radio stays registered), radio fully off, APN, 4G/3G mode, IP/DNS, SIM and IMEI info (read only), restart |
| **Network › LAN** | USB Ethernet adapter on/off, DHCP / static / share internet |
| **Network › USB network** | IP settings for `usb0` when the modem is a USB gadget |
| **Network › Tailscale** | Connect/disconnect, exit node on/off |
| **SMS control** | Commands by SMS (`lte on`, `lte off`, `wifi on`, `wifi off`, `status`), whitelist or any sender, optional replies |
| **USB mode** | Switch host/device now, choose the mode used at boot, `lsusb` |
| **System** | Password, hostname, timezone (WIB/WITA/WIT), log, reboot, shutdown |

Toggles are a single row that shows the current state and the action, e.g.
`Mobile data   ON  → turn off (radio stays on for SMS)`. Anything that could cut your SSH session
asks for confirmation first.

## Install

New stick still on Android? Follow [docs/flashing-uz801.md](docs/flashing-uz801.md) first
(backup, flashing Debian, fixing LTE).

```bash
git clone https://github.com/murdokoja-max/openstick-config.git
cd openstick-config
sudo ./install.sh                      # menu only
sudo ./install.sh --with-usb-host      # also put the USB port in host mode at boot
sudo ./install.sh --with-sms           # also start the SMS daemon / LTE IPv4 watchdog
sudo openstick-config
```

Requirements: Debian with NetworkManager and ModemManager (as shipped by OpenStick images),
`whiptail` (installed automatically), optional `tailscale`.

## Files

| Path | Purpose |
|---|---|
| `bin/openstick-config` | The menu (`/usr/local/bin`) |
| `bin/openstick-smsd` | SMS remote control daemon; also reconnects LTE when it comes up without IPv4 |
| `systemd/openstick-smsd.service` | Runs the daemon |
| `systemd/usb-host.service` | Switches the USB port to host mode at boot |
| `etc/openstick-sms.conf.example` | Copied to `/etc/openstick-sms.conf` (whitelist, replies, interval) |

## Notes from the UZ801

- **USB host mode** needs a powered hub (5 V / 2 A adapter, not a power bank) connected to the
  modem through the hub's **upstream** cable. Some hubs are not detected at all.
- **Heat:** LTE data is the main heat source. Around 60 °C the Wi-Fi radio starts failing
  authentication although the signal looks fine. Keep mobile data off when not needed and give the
  stick some airflow.
- **Hotspot:** the image uses a static `192.168.100.1/24` on `wlan0`, DHCP from the system
  `dnsmasq` and NAT from `/etc/iptables/rules.v4`; only IP forwarding was missing. Do not switch the
  hotspot profile to NetworkManager "shared" mode (it collides with the system dnsmasq on port 67).
- **No policy routing** in the stock kernel (`CONFIG_IP_ADVANCED_ROUTER` is off), so "Internet via
  LTE first" lowers the LTE route metric for *all* traffic, not just hotspot clients.
- **LTE IPv4:** with `ipv4v6` the modem places two data calls; the IPv4 one is sometimes rejected
  (`CallFailed`). `openstick-smsd` reconnects after 60 s without IPv4.
- **SMS / calls:** outgoing SMS works, but on XL (Indonesia) incoming SMS and calls never reached the
  modem (4G only, no 2G, 3G switched off by the operator). SMS control is in place for SIMs/operators
  where incoming SMS works.
- **IMEI** is shown for reference only. Changing it is illegal in Indonesia and many other countries.
- No USB-serial drivers (CH340/FTDI/CP210x/ACM) in the stock kernel.
