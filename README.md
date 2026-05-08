# killswitch

A configurable OpenVPN killswitch for Debian-family Linux systems. It uses UFW to block non-local traffic outside the VPN tunnel and can run a systemd monitor that protects a service such as Deluge when tunnel connectivity fails.

## Behavior

`up` follows a strict leak-prevention order: stop the protected service, verify it is down, wait up to 180 seconds for VPN readiness, configure UFW, verify readiness again under the firewall rules, then start the protected service. UFW is configured to:

1. Deny inbound and outbound traffic by default
2. Allow traffic through the VPN tunnel interface, such as `tun0`
3. Allow the configured VPN port on the physical network interface
4. Allow DNS port 53 through the VPN tunnel
5. Allow access to the configured local network

`check` uses the same safe startup flow, then monitors `CHECK_HOST` through `NET_TUN` every `CHECK_INTERVAL` seconds. If the check fails, it stops the protected service, verifies it is down, restarts the configured OpenVPN systemd service up to `OPENVPN_RESTART_ATTEMPTS` times, and starts the protected service again only if readiness returns. If recovery fails, it reapplies deny-by-default UFW policy, logs the failure, and reboots.

OpenVPN readiness and recovery are handled through systemd, for example against `openvpn-client@ipvanish.service`. The script does not use direct `pkill` or `openvpn --daemon` control.

DNS is intentionally limited to the VPN tunnel. The killswitch does not allow pre-tunnel DNS fallback because that can leak host lookups outside the VPN path.

## Requirements

- Debian-family Linux distribution such as Debian, Ubuntu, or a derivative
- UFW
- OpenVPN
- iproute2
- iputils-ping
- libc-bin for `getent`
- systemd for service installation, service readiness checks, and protected-service control
- Root privileges for firewall, service, and install operations

Install the common packages with:

```sh
sudo apt install ufw openvpn iproute2 iputils-ping libc-bin systemd coreutils hostname
```

## Configuration

Edit the variables at the top of `killswitch.sh`, then change `SETUP="no"` to `SETUP="yes"`.

```sh
NET_DEV="eth0"
LOCAL_NET="192.168.0.0/24"
NET_TUN="tun0"
PORT=443
VPN_ENDPOINT=""
SERVICE="deluged"
OPENVPN_SERVICE="openvpn-client@ipvanish.service"
CHECK_HOST="google.com"
WAIT_INTERVAL=5
READINESS_TIMEOUT=180
OPENVPN_RESTART_ATTEMPTS=2
REQUIRE_UFW_IPV6="yes"
```

Use `ip link` to confirm interface names on the target host.

Set `VPN_ENDPOINT` to the VPN server IP address or hostname when it is stable. When set, the physical interface allows only that destination on `PORT`; when empty, the script allows any destination on the configured VPN port.

On current Debian-family OpenVPN installs, client configs commonly map to systemd units such as `openvpn-client@ipvanish.service`. The installed killswitch service declares an `After=` relationship to that OpenVPN unit, then the script performs its own 180-second readiness guard before starting the protected service.

The script uses explicit command path variables because root service environments may not include `/usr/sbin` in `PATH`. If your system installs commands somewhere else, update the command path variables near the top of the script before enabling it.

When `REQUIRE_UFW_IPV6="yes"`, the script requires `/etc/default/ufw` to contain `IPV6=yes` before applying or monitoring rules. If the host does not use IPv6, disable IPv6 at the OS level or keep UFW IPv6 rule management enabled so outbound-deny behavior is consistent.

## Usage

```sh
# Configure UFW, verify VPN, and start the protected service
sudo ./killswitch.sh up

# Stop the protected service and keep UFW deny-by-default
sudo ./killswitch.sh down

# Start safely, then monitor VPN health
sudo ./killswitch.sh check

# Check VPN readiness once
sudo ./killswitch.sh health

# Wait until VPN readiness checks pass
sudo ./killswitch.sh guard

# Install the systemd monitor service
sudo ./killswitch.sh install
```

`down` stops the protected service and reapplies deny-by-default UFW policy. It does not intentionally open the firewall or restore normal networking.

`up` and `check` call the same readiness guard before continuing. The guard waits up to `READINESS_TIMEOUT` seconds, retrying every `WAIT_INTERVAL` seconds, until the configured OpenVPN service is active, the configured tunnel interface exists, DNS resolves `CHECK_HOST`, and `CHECK_HOST` responds through the tunnel.

`install` copies the configured script to `/usr/sbin/killswitch.sh`, writes `/etc/systemd/system/killswitch.service`, reloads systemd, and runs:

```sh
systemctl daemon-reload
```

`install` disables independent autostart for the protected service, but does not enable or start `killswitch.service`. Run `sudo ./killswitch.sh up` separately when you are ready to activate the firewall rules, then run `sudo systemctl enable --now killswitch.service` when you are ready for the monitor to run persistently.

## License

GNU General Public License v3.
