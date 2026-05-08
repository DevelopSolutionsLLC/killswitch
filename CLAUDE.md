# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`killswitch.sh` is a POSIX `sh` script for Debian-family Linux systems. It uses UFW to restrict traffic to an OpenVPN tunnel and includes a long-running monitor mode that protects a service such as Deluge when tunnel connectivity fails.

## Modes

- `up` stops the protected `SERVICE`, verifies it is down, waits up to `READINESS_TIMEOUT` seconds for OpenVPN, the tunnel interface, DNS, and the tunnel ping to be healthy before configuring UFW with default deny inbound/outbound rules, VPN tunnel allowances, VPN port allowances, DNS port 53 over the tunnel, and local-network access. It verifies readiness again after UFW is enabled and starts the protected `SERVICE` only after that succeeds. DNS is intentionally not allowed before the tunnel is available.
- `down` stops the protected `SERVICE`, verifies it is down, and reapplies deny-by-default UFW policy. It does not intentionally open the firewall.
- `check` stops the protected `SERVICE`, verifies it is down, waits up to `READINESS_TIMEOUT` seconds for OpenVPN, the tunnel interface, DNS, and the tunnel ping to be healthy before starting the protected `SERVICE` and entering the monitor loop. It pings `CHECK_HOST` through `NET_TUN`; on failure it stops the protected `SERVICE`, verifies the protected service is stopped, restarts the configured OpenVPN systemd service up to `OPENVPN_RESTART_ATTEMPTS` times, starts the protected service only if readiness returns, and otherwise reapplies deny-by-default UFW policy, logs the failure, and intentionally forces a reboot.
- `health` checks OpenVPN service state, tunnel interface presence, DNS, and tunnel ping once.
- `guard` waits until OpenVPN service state, tunnel interface presence, DNS, and tunnel ping are all healthy, bounded by `READINESS_TIMEOUT`.
- `install` copies the configured script to `INSTALL_PATH`, writes `SERVICE_FILE`, disables independent autostart for the protected `SERVICE`, and reloads systemd. It does not enable or start `killswitch.service`; that remains an explicit operator step.

## Configuration

All runtime configuration is in variables at the top of `killswitch.sh`. `SETUP` must be changed to `yes` before operational modes run.

Primary variables:

- `NET_DEV`, `LOCAL_NET`, `NET_TUN`, `PORT`, and optional `VPN_ENDPOINT` define the network and firewall behavior. When `VPN_ENDPOINT` is set, physical-interface VPN egress is pinned to that destination and port.
- `SERVICE` is an optional protected service to stop while the VPN is down.
- `OPENVPN_SERVICE` is required and identifies the systemd OpenVPN service checked for readiness and restarted during bounded recovery, for example `openvpn-client@ipvanish.service`. The script uses systemd only and does not use direct `pkill` or `openvpn --daemon` control.
- `CHECK_HOST`, `CHECK_INTERVAL`, `WAIT_INTERVAL`, `READINESS_TIMEOUT`, and `OPENVPN_RESTART_ATTEMPTS` define health checking, readiness wait behavior, and bounded recovery.
- `REQUIRE_UFW_IPV6` defaults to `yes` and requires UFW IPv6 rule management before applying or monitoring firewall rules.
- `INSTALL_PATH` and `SERVICE_FILE` control where `install` writes the script and systemd unit.
- Command path variables such as `UFW`, `SYSTEMCTL`, `IP`, and `PING` are intentional because root service environments may not include `/usr/sbin` in `PATH`.

## Platform

Target Debian-family Linux distributions such as Debian, Ubuntu, and derivatives. Required packages include `ufw`, `openvpn`, `iproute2`, `iputils-ping`, `libc-bin`, `systemd`, `coreutils`, and `hostname`.
