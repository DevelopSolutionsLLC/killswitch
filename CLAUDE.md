# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`killswitch.sh` is a POSIX `sh` script for Debian-family Linux systems. It uses UFW to restrict traffic to an OpenVPN tunnel and includes a long-running monitor mode that can restart OpenVPN through systemd when tunnel connectivity fails.

## Modes

- `up` waits for OpenVPN, the tunnel interface, and the tunnel ping to be healthy before configuring UFW with default deny inbound/outbound rules, VPN tunnel allowances, VPN port allowances, DNS port 53 over the tunnel, and local-network access. DNS is intentionally not allowed before the tunnel is available.
- `down` disables UFW entirely. This restores normal networking and removes firewall protection until UFW is enabled again.
- `check` waits for OpenVPN, the tunnel interface, and the tunnel ping to be healthy before entering the monitor loop. It pings `CHECK_HOST` through `NET_TUN`; on failure it stops the protected `SERVICE`, verifies the protected service is stopped, resets UFW, logs the failure, and intentionally forces a reboot.
- `health` checks OpenVPN service state, tunnel interface presence, and tunnel ping once.
- `guard` waits until OpenVPN service state, tunnel interface presence, and tunnel ping are all healthy.
- `install` copies the configured script to `INSTALL_PATH`, writes `SERVICE_FILE`, and reloads systemd. It does not enable or start `killswitch.service`; that remains an explicit operator step.

## Configuration

All runtime configuration is in variables at the top of `killswitch.sh`. `SETUP` must be changed to `yes` before operational modes run.

Primary variables:

- `NET_DEV`, `LOCAL_NET`, `NET_TUN`, and `PORT` define the network and firewall behavior.
- `SERVICE` is an optional protected service to stop while the VPN is down.
- `OPENVPN_SERVICE` is required and identifies the systemd OpenVPN service checked for readiness, for example `openvpn-client@ipvanish.service`.
- `CHECK_HOST`, `CHECK_INTERVAL`, and `WAIT_INTERVAL` define health checking and readiness wait behavior.
- `INSTALL_PATH` and `SERVICE_FILE` control where `install` writes the script and systemd unit.
- Command path variables such as `UFW`, `SYSTEMCTL`, `IP`, and `PING` are intentional because root service environments may not include `/usr/sbin` in `PATH`.

## Platform

Target Debian-family Linux distributions such as Debian, Ubuntu, and derivatives. Required packages include `ufw`, `openvpn`, `iproute2`, `iputils-ping`, `systemd`, `grep`, `coreutils`, and `hostname`.
