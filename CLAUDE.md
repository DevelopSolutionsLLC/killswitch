# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A bash script that implements a VPN killswitch using UFW (Uncomplicated Firewall) on Ubuntu. Ensures all traffic routes through an OpenVPN tunnel by blocking non-VPN connections at the firewall level, with a monitoring loop that restarts the VPN if it drops.

## Modes

- `up` — Configures UFW: denies all traffic by default, then allows traffic only through the VPN tunnel (`tun0`), the VPN port on the physical interface, DNS over the tunnel, and local network access.
- `down` — Disables UFW entirely, restoring normal networking.
- `check` — Infinite monitoring loop (for cron/service use). Pings google.com through the tunnel every 60 seconds. On failure: stops the protected service, kills openvpn, disables UFW, waits for network, reconnects VPN, re-enables UFW, restarts the service. Reboots as a last resort if UFW won't disable.
- `install` — Stub, not yet implemented.

## Configuration

All config is via variables at the top of the script. The `SETUP` variable must be changed to `"yes"` after configuring, or the script refuses to run.

Key variables: `NET_DEV` (physical interface), `LOCAL_NET` (LAN subnet), `NET_TUN` (VPN interface), `PORT` (VPN port), `SERVICE` (service to stop/start with VPN), `LOGFILE`.

## Platform

Ubuntu 18.04/16.04 LTS with UFW and OpenVPN. Requires root privileges for UFW and service management.

## Known issues

- Line 64: duplicate `elif [ "$INPUT" == "up" ]` — dead code, likely meant to be a different command
- `install` mode is a stub that overwrites `/etc/init.d/killswitch` with an empty file
- Hardcoded IP pattern `192.168.15` in check mode doesn't use `$LOCAL_NET`
- Hardcoded VPN config path `/etc/openvpn/ipvanish.conf`
- DNS rules only allow port 53 on tun0, so DNS fails before VPN connects
