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
# User configuration
SETUP="no"                            # Change to yes after updating script
NET_DEV="eth0"                        # Physical network interface
LOCAL_NET="192.168.0.0/24"            # Local network subnet
NET_TUN="tun0"                        # VPN tunnel interface
PORT=443                              # Port used by the VPN connection
SERVICE="apache2"                     # Protected service stopped on VPN loss
OPENVPN_SERVICE="openvpn-client@ipvanish.service"
CHECK_HOST="google.com"               # Connectivity check host
CHECK_INTERVAL=60                     # Seconds between checks
LOGFILE="/var/log/killswitch/vpn.log" # Log file location

# Installation targets
INSTALL_PATH="/usr/sbin/killswitch.sh"
SERVICE_FILE="/etc/systemd/system/killswitch.service"

# Command paths
UFW="/usr/sbin/ufw"
IP="/usr/sbin/ip"
PING="/usr/bin/ping"
SYSTEMCTL="/usr/bin/systemctl"
REBOOT="/usr/sbin/reboot"
MKDIR="/usr/bin/mkdir"
HOSTNAME="/usr/bin/hostname"
DATE="/usr/bin/date"
SLEEP="/usr/bin/sleep"
CP="/usr/bin/cp"
CHMOD="/usr/bin/chmod"
CAT="/usr/bin/cat"
ID="/usr/bin/id"

info()
{
  printf '%s\n\n' "Usage: killswitch.sh up/down/check/install"
  printf '%s\n\n' "killswitch.sh configures ufw based on variables in the script."
  printf '%s\n' "Options:"
  printf '%s\n' "  up       configures ufw based on the VPN device"
  printf '%s\n' "  down     disables ufw and restores normal networking"
  printf '%s\n' "  check    monitors the VPN and restarts OpenVPN if needed"
  printf '%s\n' "  install  installs, enables, and starts the systemd monitor service"
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

require_firewall_paths()
{
  require_paths "$UFW" ufw "$IP" iproute2 "$PING" iputils-ping
}

require_monitor_paths()
{
  require_paths \
    "$UFW" ufw \
    "$IP" iproute2 \
    "$PING" iputils-ping \
    "$REBOOT" systemd \
    "$MKDIR" coreutils \
    "$HOSTNAME" hostname \
    "$DATE" coreutils \
    "$SLEEP" coreutils

  require_paths "$SYSTEMCTL" systemd
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

reset_ufw()
{
  "$UFW" --force reset
}

stop_protected_service()
{
  if [ -n "$SERVICE" ]; then
    "$SYSTEMCTL" stop "$SERVICE" || fail "Could not stop protected service: $SERVICE"
  fi
}

verify_protected_service_stopped()
{
  if [ -n "$SERVICE" ] && "$SYSTEMCTL" is-active --quiet "$SERVICE"; then
    fail "Protected service is still active: $SERVICE"
  fi
}

write_service_file()
{
  "$CAT" > "$SERVICE_FILE" <<EOF
[Unit]
Description=OpenVPN UFW killswitch monitor
After=network-online.target
Wants=network-online.target
EOF

  "$CAT" >> "$SERVICE_FILE" <<EOF
After=$OPENVPN_SERVICE
Wants=$OPENVPN_SERVICE
EOF

  "$CAT" >> "$SERVICE_FILE" <<EOF

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

  "$SYSTEMCTL" daemon-reload || fail "Could not reload systemd"
  "$SYSTEMCTL" enable --now killswitch.service || fail "Could not enable and start killswitch.service"

  printf '%s\n' "Installed $INSTALL_PATH"
  printf '%s\n' "Installed $SERVICE_FILE"
  printf '%s\n' "Enabled and started killswitch.service"
}

INPUT=$1

if [ -z "$INPUT" ]; then
  info
  exit 1
fi

case "$INPUT" in
  up)
    require_setup
    require_firewall_paths

    reset_ufw

    "$UFW" default deny outgoing
    "$UFW" default deny incoming

    "$UFW" allow out on "$NET_TUN"
    "$UFW" allow in on "$NET_TUN"

    "$UFW" allow out on "$NET_DEV" to any port "$PORT"
    "$UFW" allow in on "$NET_DEV" from any port "$PORT"

    "$UFW" allow out on "$NET_TUN" to any port 53
    "$UFW" allow in on "$NET_TUN" to any port 53

    "$UFW" allow out on "$NET_DEV" from any to "$LOCAL_NET"
    "$UFW" allow in on "$NET_DEV" from "$LOCAL_NET" to any

    "$UFW" --force enable
    ;;
  check)
    require_setup
    require_monitor_paths
    ensure_log_dir

    while true; do
      if ! tunnel_is_up; then
        stop_protected_service
        verify_protected_service_stopped
        reset_ufw
        printf '*** [VPN health failed, rebooting for OpenVPN recovery: %s @ %s] ***\n' "$("$HOSTNAME")" "$("$DATE")" >> "$LOGFILE"
        printf '%s\n' "-----------------------------------------------------------------" >> "$LOGFILE"
        "$REBOOT"
      fi
      "$SLEEP" "$CHECK_INTERVAL"
    done
    ;;
  down)
    require_setup
    require_monitor_paths
    stop_protected_service
    verify_protected_service_stopped
    reset_ufw
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
