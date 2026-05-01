# killswitch

A VPN killswitch for OpenVPN on Ubuntu that uses UFW to ensure all traffic routes through the VPN tunnel. If the VPN drops, all non-local traffic is blocked — no IP leaks.

## How it works

When activated, the script configures UFW to:
1. **Deny all** inbound and outbound traffic by default
2. **Allow** traffic through the VPN tunnel interface (`tun0`)
3. **Allow** the VPN connection port on the physical interface
4. **Allow** DNS resolution through the tunnel
5. **Allow** local network access (e.g., LAN printers, NAS)

A monitoring mode continuously checks connectivity through the tunnel and automatically restarts OpenVPN if it drops.

## Setup

Edit the variables at the top of `killswitch.sh`:

```bash
NET_DEV="eth0"               # Physical network interface
LOCAL_NET="192.168.0.0/24"   # Local network subnet
NET_TUN="tun0"               # VPN tunnel interface
PORT=443                     # VPN connection port
SERVICE="apache2"            # Service to protect (stopped when VPN drops)
```

Then change `SETUP="no"` to `SETUP="yes"`.

## Usage

```bash
# Activate the killswitch
sudo ./killswitch.sh up

# Deactivate (disables UFW)
sudo ./killswitch.sh down

# Monitor VPN and auto-restart on failure (run as service or cron)
sudo ./killswitch.sh check
```

## Requirements

- Ubuntu 18.04/16.04 LTS
- UFW
- OpenVPN
- Root privileges

## License

GNU General Public License v3.
