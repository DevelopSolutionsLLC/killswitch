# killswitch

A configurable OpenVPN killswitch for Debian-family Linux systems. It uses UFW to block non-local traffic outside the VPN tunnel and can run a systemd monitor that restarts OpenVPN when tunnel connectivity fails.

## Behavior

When enabled with `up`, the script configures UFW to:

1. Deny inbound and outbound traffic by default
2. Allow traffic through the VPN tunnel interface, such as `tun0`
3. Allow the configured VPN port on the physical network interface
4. Allow DNS port 53 through the VPN tunnel
5. Allow access to the configured local network

When running in `check` mode, the monitor pings `CHECK_HOST` through `NET_TUN`. If that check fails, it stops the protected `SERVICE` when configured, disables UFW, waits for the physical interface to have an IPv4 address, restarts OpenVPN, re-enables UFW, and then restarts the protected service. If UFW cannot be disabled during recovery and still reports active, the script forces a reboot. That is intentional killswitch behavior: if the VPN/firewall recovery path fails, the host should not continue running in an unknown network state.

OpenVPN is restarted through systemd, for example `systemctl restart openvpn-client@ipvanish.service`.

DNS is intentionally limited to the VPN tunnel. The killswitch does not allow pre-tunnel DNS fallback because that can leak host lookups outside the VPN path.

## Requirements

- Debian-family Linux distribution such as Debian, Ubuntu, or a derivative
- UFW
- OpenVPN
- iproute2
- iputils-ping
- systemd for service installation and OpenVPN service restarts
- Root privileges for firewall, service, and install operations

Install the common packages with:

```sh
sudo apt install ufw openvpn iproute2 iputils-ping
```

## Configuration

Edit the variables at the top of `killswitch.sh`, then change `SETUP="no"` to `SETUP="yes"`.

```sh
NET_DEV="eth0"
LOCAL_NET="192.168.0.0/24"
NET_TUN="tun0"
PORT=443
SERVICE="apache2"
OPENVPN_SERVICE="openvpn-client@ipvanish.service"
CHECK_HOST="google.com"
```

Use `ip link` to confirm interface names on the target host.

On current Debian-family OpenVPN installs, client configs commonly map to systemd units such as `openvpn-client@ipvanish.service`. The monitor uses systemd to restart OpenVPN, and the installed killswitch service declares `After=` and `Wants=` relationships to that OpenVPN unit.

The script uses explicit command path variables because root service environments may not include `/usr/sbin` in `PATH`. If your system installs commands somewhere else, update the command path variables near the top of the script before enabling it.

## Usage

```sh
# Activate the firewall killswitch rules
sudo ./killswitch.sh up

# Disable UFW and restore normal networking
sudo ./killswitch.sh down

# Run the monitor in the foreground
sudo ./killswitch.sh check

# Install, enable, and start the systemd monitor service
sudo ./killswitch.sh install
```

`down` disables UFW entirely. This restores normal networking, but it also removes firewall protection until UFW is enabled again.

`install` copies the configured script to `/usr/sbin/killswitch.sh`, writes `/etc/systemd/system/killswitch.service`, reloads systemd, and runs:

```sh
systemctl enable --now killswitch.service
```

`install` starts the monitor service only. Run `sudo ./killswitch.sh up` separately when you are ready to activate the firewall rules.

## License

GNU General Public License v3.
