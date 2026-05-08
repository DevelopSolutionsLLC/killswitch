#!/bin/sh
#
# /usr/sbin/killswitch.sh
#
# Copyright (C) 2018 Free Software Foundation, Inc.
# This is free software.  You may redistribute copies of it under the terms of
# the GNU General Public License .
# There is NO WARRANTY, to the extent permitted by law.
#
# Written by Victor T. Chevalier
#
# Designed for use with OpenVPN on Debian-family Linux distributions.
#
# Network configuration
SETUP="no"                            # Change to yes after updating script
NET_DEV="eth0"                        # Physical network interface
LOCAL_NET="192.168.0.0/24"            # Local network subnet
NET_TUN="tun0"                        # VPN tunnel interface
PORT=443                              # Port used by the VPN connection
VPN_ENDPOINT=""                       # Optional VPN server IP/host

# Service and health configuration
SERVICE="deluged"                     # Protected service stopped on VPN loss
OPENVPN_SERVICE="openvpn-client@ipvanish.service"
CHECK_HOST="google.com"               # Connectivity check host
CHECK_INTERVAL=60                     # Seconds between checks
WAIT_INTERVAL=5                       # Seconds between readiness checks
READINESS_TIMEOUT=180                 # Seconds to wait for VPN readiness
OPENVPN_RESTART_ATTEMPTS=2            # OpenVPN restarts before reboot
REQUIRE_UFW_IPV6="yes"                # Require UFW to manage IPv6 rules
LOGFILE="/var/log/killswitch/vpn.log" # Log file location

# Installation targets
INSTALL_PATH="/usr/sbin/killswitch.sh"
SERVICE_FILE="/etc/systemd/system/killswitch.service"
UFW_DEFAULT="/etc/default/ufw"

# Command paths
UFW="/usr/sbin/ufw"
IP="/usr/sbin/ip"
PING="/usr/bin/ping"
GETENT="/usr/bin/getent"
SYSTEMCTL="/usr/bin/systemctl"
REBOOT="/usr/sbin/reboot"
MKDIR="/usr/bin/mkdir"
GREP="/usr/bin/grep"
HOSTNAME="/usr/bin/hostname"
DATE="/usr/bin/date"
SLEEP="/usr/bin/sleep"
CP="/usr/bin/cp"
CHMOD="/usr/bin/chmod"
CAT="/usr/bin/cat"
ID="/usr/bin/id"

info()
{
  printf '%s\n\n' "Usage: killswitch.sh up/down/check/health/guard/install"
  printf '%s\n\n' "killswitch.sh guards a protected service behind OpenVPN and UFW."
  printf '%s\n' "Options:"
  printf '%s\n' "  up       configure UFW, verify VPN, then start the protected service"
  printf '%s\n' "  down     stop the protected service and keep UFW deny-by-default"
  printf '%s\n' "  check    start safely, monitor VPN, recover or reboot on failure"
  printf '%s\n' "  health   checks OpenVPN, tunnel interface, DNS, and tunnel ping once"
  printf '%s\n' "  guard    waits until OpenVPN, tunnel interface, DNS, and tunnel ping are ready"
  printf '%s\n' "  install  install the script and systemd monitor service"
  printf '\n%s\n' "An argument must be provided or you will receive this message."
}

fail()
{
  printf '%s\n' "$1" >&2
  exit 1;
}

require_setup()
{
  if [ "$SETUP" != "yes" ]; then
    fail "Please update variables in /usr/sbin/killswitch.sh"
  fi

  if [ -z "$OPENVPN_SERVICE" ]; then
    fail "Please set OPENVPN_SERVICE to the systemd OpenVPN client service name"
  fi
}

require_paths()
{
  MISSING_PATHS=""
  MISSING_PACKAGES=""

  while [ "$#" -gt 0 ]; do
    COMMAND_PATH=$1
    PACKAGE=$2

    if [ ! -x "$COMMAND_PATH" ]; then
      MISSING_PATHS="${MISSING_PATHS} ${COMMAND_PATH}"
      case " $MISSING_PACKAGES " in
        *" $PACKAGE "*)
          ;;
        *)
          MISSING_PACKAGES="${MISSING_PACKAGES} ${PACKAGE}"
          ;;
      esac
    fi

    shift 2
  done

  if [ -n "$MISSING_PATHS" ]; then
    printf 'Missing required command path(s):%s\n' "$MISSING_PATHS" >&2
    printf 'Install the related Debian packages, for example:\n' >&2
    printf '  sudo apt install%s\n' "$MISSING_PACKAGES" >&2
    printf 'If your system uses different paths, update the command path variables near the top of this script.\n' >&2
    exit 1
  fi
}

require_guard_paths()
{
  require_paths \
    "$UFW" ufw \
    "$IP" iproute2 \
    "$PING" iputils-ping \
    "$GETENT" libc-bin \
    "$GREP" grep \
    "$SYSTEMCTL" systemd \
    "$SLEEP" coreutils
}

require_monitor_paths()
{
  require_guard_paths
  require_paths \
    "$REBOOT" systemd \
    "$MKDIR" coreutils \
    "$HOSTNAME" hostname \
    "$DATE" coreutils
}

require_install_paths()
{
  require_monitor_paths
  require_paths "$CP" coreutils "$CHMOD" coreutils "$CAT" coreutils
}

require_root()
{
  if [ "$("$ID" -u)" != "0" ]; then
    fail "This command must be run as root"
  fi
}

ensure_log_dir()
{
  LOGDIR=${LOGFILE%/*}

  if [ "$LOGDIR" != "$LOGFILE" ]; then
    "$MKDIR" -p "$LOGDIR" || fail "Could not create log directory: $LOGDIR"
  fi
}

tunnel_is_up()
{
  "$PING" -c 1 -I "$NET_TUN" "$CHECK_HOST" >/dev/null 2>&1
}

dns_is_ready()
{
  "$GETENT" hosts "$CHECK_HOST" >/dev/null 2>&1
}

tunnel_interface_exists()
{
  "$IP" link show dev "$NET_TUN" >/dev/null 2>&1
}

openvpn_is_active()
{
  "$SYSTEMCTL" is-active --quiet "$OPENVPN_SERVICE"
}

verify_ufw_ipv6()
{
  if [ "$REQUIRE_UFW_IPV6" = "yes" ]; then
    if [ ! -r "$UFW_DEFAULT" ] || ! "$GREP" -Eq '^IPV6=yes$' "$UFW_DEFAULT"; then
      fail "UFW IPv6 handling is not enabled in $UFW_DEFAULT; set IPV6=yes or disable IPv6 before using killswitch"
    fi
  fi
}

health_check()
{
  openvpn_is_active || fail "OpenVPN service is not active: $OPENVPN_SERVICE"
  tunnel_interface_exists || fail "Tunnel interface is not present: $NET_TUN"
  dns_is_ready || fail "DNS lookup failed: $CHECK_HOST"
  tunnel_is_up || fail "Tunnel ping failed: $CHECK_HOST via $NET_TUN"
}

guard_vpn()
{
  ELAPSED=0

  while [ "$ELAPSED" -lt "$READINESS_TIMEOUT" ]; do
    if openvpn_is_active && tunnel_interface_exists && dns_is_ready && tunnel_is_up; then
      return 0
    fi

    "$SLEEP" "$WAIT_INTERVAL"
    ELAPSED=$((ELAPSED + WAIT_INTERVAL))
  done

  return 1
}

wait_for_vpn_or_fail()
{
  guard_vpn || fail "VPN readiness failed after ${READINESS_TIMEOUT}s: $OPENVPN_SERVICE, $NET_TUN, DNS, or tunnel ping is not ready"
}

try_openvpn_recovery()
{
  ATTEMPT=1

  while [ "$ATTEMPT" -le "$OPENVPN_RESTART_ATTEMPTS" ]; do
    printf '*** [Restarting OpenVPN attempt %s/%s: %s @ %s] ***\n' "$ATTEMPT" "$OPENVPN_RESTART_ATTEMPTS" "$("$HOSTNAME")" "$("$DATE")" >> "$LOGFILE"
    "$SYSTEMCTL" restart "$OPENVPN_SERVICE" || return 1

    if guard_vpn; then
      return 0
    fi

    ATTEMPT=$((ATTEMPT + 1))
  done

  return 1
}

apply_ufw_defaults()
{
  "$UFW" default deny outgoing
  "$UFW" default deny incoming
  "$UFW" --force enable
  "$UFW" reload
}

allow_vpn_endpoint()
{
  if [ -n "$VPN_ENDPOINT" ]; then
    "$UFW" allow out on "$NET_DEV" to "$VPN_ENDPOINT" port "$PORT"
    "$UFW" allow in on "$NET_DEV" from "$VPN_ENDPOINT" port "$PORT"
  else
    "$UFW" allow out on "$NET_DEV" to any port "$PORT"
    "$UFW" allow in on "$NET_DEV" from any port "$PORT"
  fi
}

configure_firewall()
{
  apply_ufw_defaults

  "$UFW" allow out on "$NET_TUN"
  "$UFW" allow in on "$NET_TUN"

  allow_vpn_endpoint

  "$UFW" allow out on "$NET_TUN" to any port 53
  "$UFW" allow in on "$NET_TUN" to any port 53

  "$UFW" allow out on "$NET_DEV" from any to "$LOCAL_NET"
  "$UFW" allow in on "$NET_DEV" from "$LOCAL_NET" to any

  "$UFW" reload
}

stop_protected_service()
{
  if [ -n "$SERVICE" ]; then
    "$SYSTEMCTL" stop "$SERVICE" || fail "Could not stop protected service: $SERVICE"
  fi
}

start_protected_service()
{
  if [ -n "$SERVICE" ]; then
    "$SYSTEMCTL" start "$SERVICE" || fail "Could not start protected service: $SERVICE"
  fi
}

verify_protected_service_stopped()
{
  if [ -n "$SERVICE" ] && "$SYSTEMCTL" is-active --quiet "$SERVICE"; then
    fail "Protected service is still active: $SERVICE"
  fi
}

prepare_protected_start()
{
  stop_protected_service
  verify_protected_service_stopped
  verify_ufw_ipv6
}

start_protected_after_vpn()
{
  wait_for_vpn_or_fail
  start_protected_service
}

recover_vpn_or_reboot()
{
  stop_protected_service
  verify_protected_service_stopped

  if try_openvpn_recovery; then
    health_check
    start_protected_service
    printf '*** [OpenVPN recovery succeeded: %s @ %s] ***\n' "$("$HOSTNAME")" "$("$DATE")" >> "$LOGFILE"
    printf '%s\n' "-----------------------------------------------------------------" >> "$LOGFILE"
    return 0
  fi

  apply_ufw_defaults
  printf '*** [VPN health failed, rebooting for OpenVPN recovery: %s @ %s] ***\n' "$("$HOSTNAME")" "$("$DATE")" >> "$LOGFILE"
  printf '%s\n' "-----------------------------------------------------------------" >> "$LOGFILE"
  "$REBOOT"
}

monitor_vpn()
{
  while true; do
    if ! tunnel_is_up; then
      recover_vpn_or_reboot
    fi
    "$SLEEP" "$CHECK_INTERVAL"
  done
}

write_service_file()
{
  "$CAT" > "$SERVICE_FILE" <<EOF
[Unit]
Description=OpenVPN UFW killswitch monitor
After=network-online.target
Wants=network-online.target
After=$OPENVPN_SERVICE

[Service]
Type=simple
ExecStart=$INSTALL_PATH check
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
}

install_service()
{
  "$CP" "$0" "$INSTALL_PATH" || fail "Could not install script to $INSTALL_PATH"
  "$CHMOD" 755 "$INSTALL_PATH" || fail "Could not make $INSTALL_PATH executable"
  write_service_file

  if [ -n "$SERVICE" ]; then
    "$SYSTEMCTL" disable "$SERVICE" >/dev/null 2>&1 || fail "Could not disable protected service autostart: $SERVICE"
  fi

  "$SYSTEMCTL" daemon-reload || fail "Could not reload systemd"

  printf '%s\n' "Installed $INSTALL_PATH"
  printf '%s\n' "Installed $SERVICE_FILE"
  if [ -n "$SERVICE" ]; then
    printf '%s\n' "Disabled independent autostart for $SERVICE"
  fi
  printf '%s\n' "Reloaded systemd"
  printf '%s\n' "Run 'systemctl enable --now killswitch.service' when you are ready to start monitoring"
}

INPUT=$1

if [ -z "$INPUT" ]; then
  info
  exit 1
fi

case "$INPUT" in
  up)
    require_setup
    require_guard_paths
    prepare_protected_start
    wait_for_vpn_or_fail
    configure_firewall
    health_check
    start_protected_service
    ;;
  check)
    require_setup
    require_monitor_paths
    ensure_log_dir
    prepare_protected_start
    start_protected_after_vpn
    monitor_vpn
    ;;
  down)
    require_setup
    require_monitor_paths
    stop_protected_service
    verify_protected_service_stopped
    apply_ufw_defaults
    ;;
  health)
    require_setup
    require_guard_paths
    health_check
    ;;
  guard)
    require_setup
    require_guard_paths
    wait_for_vpn_or_fail
    ;;
  install)
    require_setup
    require_paths "$ID" coreutils
    require_root
    require_install_paths
    install_service
    ;;
  *)
    info
    ;;
esac

exit 0;
