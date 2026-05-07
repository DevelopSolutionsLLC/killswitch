# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`killswitch.sh` is a POSIX `sh` script for Debian-family Linux systems. It uses UFW to restrict traffic to an OpenVPN tunnel and includes a long-running monitor mode that can restart OpenVPN through systemd when tunnel connectivity fails.

## Modes

- `up` configures UFW with default deny inbound/outbound rules, VPN tunnel allowances, VPN port allowances, DNS port 53 over the tunnel, and local-network access. DNS is intentionally not allowed before the tunnel is available.
- `down` disables UFW entirely. This restores normal networking and removes firewall protection until UFW is enabled again.
- `check` runs the monitor loop. It pings `CHECK_HOST` through `NET_TUN`; on failure it stops the protected `SERVICE`, disables UFW, waits for the physical interface to regain IPv4 connectivity, restarts OpenVPN, re-enables UFW, and restarts `SERVICE`. If UFW cannot be disabled during recovery and still reports active, the script intentionally forces a reboot.
- `install` copies the configured script to `INSTALL_PATH`, writes `SERVICE_FILE`, reloads systemd, and enables/starts `killswitch.service`.

## Configuration

All runtime configuration is in variables at the top of `killswitch.sh`. `SETUP` must be changed to `yes` before operational modes run.

Primary variables:

- `NET_DEV`, `LOCAL_NET`, `NET_TUN`, and `PORT` define the network and firewall behavior.
- `SERVICE` is an optional protected service to stop while the VPN is down.
- `OPENVPN_SERVICE` is required and identifies the systemd OpenVPN restart target, for example `openvpn-client@ipvanish.service`.
- `INSTALL_PATH` and `SERVICE_FILE` control where `install` writes the script and systemd unit.
- Command path variables such as `UFW`, `SYSTEMCTL`, `IP`, and `PING` are intentional because root service environments may not include `/usr/sbin` in `PATH`.

## Platform

Target Debian-family Linux distributions such as Debian, Ubuntu, and derivatives. Required packages include `ufw`, `openvpn`, `iproute2`, `iputils-ping`, and `systemd`.
