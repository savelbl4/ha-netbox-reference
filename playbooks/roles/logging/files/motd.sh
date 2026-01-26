#!/bin/sh

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# NetBox ASCII Art
printf "  ${CYAN} _   _      _   _                ${NC}\n"
printf "  ${CYAN}| \\ | |    | | | |               ${NC}\n"
printf "  ${CYAN}|  \\| | ___| |_| |__  _____  __ ${NC}\n"
printf "  ${CYAN}| . \` |/ _ \\ __| '_ \\/ _ \\ \\/ / ${NC}\n"
printf "  ${CYAN}| |\\  |  __/ |_| |_) |(_) >  <  ${NC}\n"
printf "  ${CYAN}\\_| \\_/\\___|\\__|_.__/\\___/_/\\_\\ ${NC}\n"
printf "  ${YELLOW}Source of Truth for Network Infrastructure${NC}\n"
printf "\n"

# Basic system info
printf "  ${GREEN}• Hostname:${NC}      $(hostname -f)\n"
printf "  ${GREEN}• Uptime:${NC}        $(uptime -p | sed 's/up //')\n"
printf "  ${GREEN}• Load:${NC}          $(cat /proc/loadavg | awk '{print $1", "$2", "$3}')\n"
MEM_USED=$(free -m | awk '/Mem:/ {printf "%.1f", $3/$2*100}')
printf "  ${GREEN}• Memory Usage:${NC}  ${MEM_USED}%%\n"

# IP Addresses (only non-loopback, IPv4)
IP_ADDRESSES=$(ip -4 addr show | grep -E '^[0-9]+: .*[0-9]+:' | awk '{print $2}' | tr -d ':' | while read iface; do
    ip -4 addr show dev $iface | grep 'inet ' | awk '{print $2}' | while read ip; do
        echo " \t$iface: $ip"
    done
done)

if [ -n "$IP_ADDRESSES" ]; then
    printf "  ${GREEN}• IP Addresses:${NC}\n"
    echo "$IP_ADDRESSES"
else
    printf "  ${GREEN}• IP Addresses:${NC} None found\n"
fi

# Check if this is a master node
printf "  ${GREEN}• Service Status:${NC}\n"

# PostgreSQL/Patroni master check
if command -v psql >/dev/null 2>&1; then
  if systemctl is-active --quiet patroni; then
    if psql -U postgres -tAc "SELECT pg_is_in_recovery();" 2>/dev/null | grep -q "f"; then
        printf "\t${YELLOW}↯ PostgreSQL:${NC} ${GREEN}MASTER${NC}\n"
    else
        printf "\t${YELLOW}↯ PostgreSQL:${NC} REPLICA\n"
    fi
  else
      printf "\t${YELLOW}↯ Patroni:${NC} ${RED}INACTIVE${NC}\n"
  fi
fi

# Redis status check with authentication
if command -v redis-cli >/dev/null 2>&1; then
    # Try to get Redis info with authentication (if configured)
    REDIS_PASSWORD=$(grep -i requirepass /etc/redis/redis.conf 2>/dev/null | awk '{print $2}' | tr '"' ' ')

    if [ -n "$REDIS_PASSWORD" ]; then
        # With authentication
        REDIS_INFO=$(redis-cli -a $REDIS_PASSWORD info replication 2>/dev/null)
    else
        # Without authentication
        REDIS_INFO=$(redis-cli info replication 2>/dev/null)
    fi

    if echo "$REDIS_INFO" | grep -q "role:master"; then
        printf "\t${YELLOW}↯ Redis:${NC} ${GREEN}MASTER${NC}\n"
    elif echo "$REDIS_INFO" | grep -q "role:slave"; then
        printf "\t${YELLOW}↯ Redis:${NC} REPLICA\n"
    elif [ -n "$REDIS_INFO" ]; then
        printf "\t${YELLOW}↯ Redis:${NC} UNKNOWN ROLE\n"
    else
        printf "\t${YELLOW}↯ Redis:${NC} ${REDIS_PASSWORD:+AUTH_ERROR}${REDIS_PASSWORD:-NOT_RUNNING}\n"
    fi
fi

# NetBox service status
if systemctl is-active --quiet netbox; then
    printf "\t${YELLOW}↯ NetBox:${NC} ${GREEN}ACTIVE${NC}\n"
else
    printf "\t${YELLOW}↯ NetBox:${NC} ${RED}INACTIVE${NC}\n"
fi

if systemctl is-active --quiet netbox-rq; then
    printf "\t${YELLOW}↯ NetBox RQ:${NC} ${GREEN}ACTIVE${NC}\n"
else
    printf "\t${YELLOW}↯ NetBox RQ:${NC} ${RED}INACTIVE${NC}\n"
fi

if systemctl is-active --quiet pgbouncer; then
    printf "\t${YELLOW}↯ PgBouncer:${NC} ${GREEN}ACTIVE${NC}\n"
else
    printf "\t${YELLOW}↯ PgBouncer:${NC} ${RED}INACTIVE${NC}\n"
fi

if systemctl is-active --quiet keepalived; then
    printf "\t${YELLOW}↯ Keepalived:${NC} ${GREEN}ACTIVE${NC}\n"
else
    printf "\t${YELLOW}↯ Keepalived:${NC} ${RED}INACTIVE${NC}\n"
fi

if systemctl is-active --quiet haproxy; then
    printf "\t${YELLOW}↯ HAProxy:${NC} ${GREEN}ACTIVE${NC}\n"
else
    printf "\t${YELLOW}↯ HAProxy:${NC} ${RED}INACTIVE${NC}\n"
fi

if systemctl is-active --quiet angie; then
    printf "\t${YELLOW}↯ Angie:${NC} ${GREEN}ACTIVE${NC}\n"
else
    printf "\t${YELLOW}↯ Angie:${NC} ${RED}INACTIVE${NC}\n"
fi
printf "\n"

# Disk space warning
DISK_USAGE=$(df / --output=pcent | tail -1 | tr -d ' %')
if [ "$DISK_USAGE" -gt 90 ]; then
    printf "\n  ${RED}⚠  WARNING: Disk usage: ${DISK_USAGE}%%${NC}\n\n"
elif [ "$DISK_USAGE" -gt 80 ]; then
    printf "\n  ${YELLOW}⚠  Warning: Disk usage: ${DISK_USAGE}%%${NC}\n\n"
fi

