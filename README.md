# killswitch

A configurable OpenVPN killswitch for Debian-family Linux systems. It uses UFW to block non-local traffic outside the VPN tunnel and can run a systemd monitor that protects a service such as Deluge when tunnel connectivity fails.

## Behavior

When enabled with `up`, the script stops the protected service, verifies it is down, waits up to 180 seconds for OpenVPN readiness, configures UFW, verifies readiness again under the firewall rules, then starts the protected service. UFW is configured to:

1. Deny inbound and outbound traffic by default
2. Allow traffic through the VPN tunnel interface, such as `tun0`
3. Allow the configured VPN port on the physical network interface
4. Allow DNS port 53 through the VPN tunnel
5. Allow access to the configured local network

When running in `check` mode, the monitor first stops the protected service, verifies it is down, then waits up to 180 seconds for OpenVPN, the tunnel interface, DNS, and the tunnel ping to be healthy, checking every 5 seconds. After readiness passes, it starts the protected `SERVICE`, then pings `CHECK_HOST` through `NET_TUN` on each monitor interval. If the check fails, it stops the protected service, verifies the service is stopped, resets UFW, logs the failure, and reboots. That is intentional killswitch behavior: if the VPN path fails, the host should not continue running in an unknown network state.

OpenVPN readiness is checked through systemd, for example against `openvpn-client@ipvanish.service`, but the script does not start, stop, or restart OpenVPN. Recovery relies on rebooting into a clean service/firewall state instead of controlling OpenVPN inside the failure loop.

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
SERVICE="deluged"
OPENVPN_SERVICE="openvpn-client@ipvanish.service"
CHECK_HOST="google.com"
WAIT_INTERVAL=5
READINESS_TIMEOUT=180
```

Use `ip link` to confirm interface names on the target host.

On current Debian-family OpenVPN installs, client configs commonly map to systemd units such as `openvpn-client@ipvanish.service`. The installed killswitch service declares an `After=` relationship to that OpenVPN unit, then the script performs its own 180-second readiness guard before starting the protected service.

The script uses explicit command path variables because root service environments may not include `/usr/sbin` in `PATH`. If your system installs commands somewhere else, update the command path variables near the top of the script before enabling it.

## Usage

```sh
# Activate the firewall killswitch rules and start the protected service
sudo ./killswitch.sh up

# Disable UFW and restore normal networking
sudo ./killswitch.sh down

# Run the monitor in the foreground
sudo ./killswitch.sh check

# Check VPN readiness once
sudo ./killswitch.sh health

# Wait until VPN readiness checks pass
sudo ./killswitch.sh guard

# Install the systemd monitor service
sudo ./killswitch.sh install
```

`down` disables UFW entirely. This restores normal networking, but it also removes firewall protection until UFW is enabled again.

`up` and `check` call the same readiness guard before continuing. The guard waits up to `READINESS_TIMEOUT` seconds, retrying every `WAIT_INTERVAL` seconds, until the configured OpenVPN service is active, the configured tunnel interface exists, DNS resolves `CHECK_HOST`, and `CHECK_HOST` responds through the tunnel.

`install` copies the configured script to `/usr/sbin/killswitch.sh`, writes `/etc/systemd/system/killswitch.service`, reloads systemd, and runs:

```sh
systemctl daemon-reload
```

`install` disables independent autostart for the protected service, but does not enable or start `killswitch.service`. Run `sudo ./killswitch.sh up` separately when you are ready to activate the firewall rules, then run `sudo systemctl enable --now killswitch.service` when you are ready for the monitor to run persistently.

## License

GNU General Public License v3.
