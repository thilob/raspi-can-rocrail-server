#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Raspberry Pi + Waveshare 2-CH Isolated CAN HAT (MCP2515) -> Märklin Gleisbox
# - CAN bitrate: 250000
# - Boot-ready via systemd oneshot: can-marklin@can0.service
# - Idempotent: no duplicate config lines, safe updates
#
# Usage:
#   sudo ./setup_can_marklin.sh
#   sudo ./setup_can_marklin.sh --only-can0
#   sudo ./setup_can_marklin.sh --keep-networkd
#   sudo ./setup_can_marklin.sh --dry-run
###############################################################################

BITRATE="250000"
OSC="16000000"          # Default; your runtime shows clock 8000000, but overlay oscillator is board-specific.
SPI_MAX="10000000"

INT_CAN0="23"
INT_CAN1="25"

ONLY_CAN0="0"
DRY_RUN="0"
KEEP_NETWORKD="0"       # default: remove networkd CAN configs to avoid "Invalid argument"

LOG_PREFIX="[CAN-SETUP]"

log()  { echo "${LOG_PREFIX} $*"; }
warn() { echo "${LOG_PREFIX} WARN: $*" >&2; }
die()  { echo "${LOG_PREFIX} ERROR: $*" >&2; exit 1; }

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: $*"
  else
    eval "$@"
  fi
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    die "Bitte als root ausführen: sudo $0 ${*:-}"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --only-can0) ONLY_CAN0="1"; shift ;;
      --dry-run) DRY_RUN="1"; shift ;;
      --keep-networkd) KEEP_NETWORKD="1"; shift ;;
      -h|--help)
        cat <<EOF
Usage: sudo $0 [--only-can0] [--keep-networkd] [--dry-run]

--only-can0        Konfiguriert nur can0 (can1 wird entfernt/ignoriert)
--keep-networkd    Belässt systemd-networkd CAN-Konfig-Dateien (Standard: entfernen, um Fehlermeldungen zu vermeiden)
--dry-run          Zeigt nur, was geändert würde
EOF
        exit 0
        ;;
      *) die "Unbekannter Parameter: $1" ;;
    esac
  done
}

detect_boot_config() {
  if [[ -f /boot/firmware/config.txt ]]; then
    echo "/boot/firmware/config.txt"
  elif [[ -f /boot/config.txt ]]; then
    echo "/boot/config.txt"
  else
    die "Konnte config.txt nicht finden (weder /boot/firmware/config.txt noch /boot/config.txt)."
  fi
}

backup_file_once() {
  local file="$1"
  local backup="${file}.bak"
  if [[ -f "$file" && ! -f "$backup" ]]; then
    log "Lege Backup an: $backup"
    run "cp -a \"$file\" \"$backup\""
  fi
}

ensure_unique_exact_line() {
  local file="$1"
  local line="$2"

  run "touch \"$file\""

  if grep -Fxq "$line" "$file"; then
    run "awk -v target='$line' '\$0==target {c++; if (c>1) next} {print}' \"$file\" > \"${file}.tmp\""
    run "mv \"${file}.tmp\" \"$file\""
  else
    run "printf '%s\n' \"$line\" >> \"$file\""
  fi
}

remove_lines_matching() {
  local file="$1"
  local regex="$2"
  run "touch \"$file\""
  run "awk -v re='$regex' '\$0 ~ re {next} {print}' \"$file\" > \"${file}.tmp\""
  run "mv \"${file}.tmp\" \"$file\""
}

ensure_overlay() {
  local file="$1"
  local can="$2"
  local intr="$3"

  local canonical="dtoverlay=mcp2515-${can},oscillator=${OSC},interrupt=${intr},spimaxfrequency=${SPI_MAX}"

  # Replace any previous overlay line for that interface with canonical one
  remove_lines_matching "$file" "^dtoverlay=mcp2515-${can}(,|$)"
  ensure_unique_exact_line "$file" "$canonical"
}

setup_modules_load() {
  local file="/etc/modules-load.d/can.conf"
  run "touch \"$file\""

  ensure_unique_exact_line "$file" "can"
  ensure_unique_exact_line "$file" "can_raw"
  ensure_unique_exact_line "$file" "mcp251x"

  # Deduplicate whole file
  run "awk '!seen[\$0]++' \"$file\" > \"${file}.tmp\""
  run "mv \"${file}.tmp\" \"$file\""
}

ensure_apt_packages() {
  if ! command -v apt-get >/dev/null 2>&1; then
    warn "apt-get nicht gefunden – überspringe Paketprüfung."
    return 0
  fi

  local pkgs=(can-utils)
  local missing=()

  for p in "${pkgs[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
  done

  if [[ "${#missing[@]}" -eq 0 ]]; then
    log "APT: Pakete bereits installiert (${pkgs[*]})."
    return 0
  fi

  log "APT: Installiere fehlende Pakete: ${missing[*]}"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: apt-get update && apt-get install -y ${missing[*]}"
    return 0
  fi

  apt-get update
  apt-get install -y "${missing[@]}"
}

install_can_marklin_service() {
  local svc="/etc/systemd/system/can-marklin@.service"

  local content="[Unit]
Description=Bring up %i for Märklin (250k)
After=systemd-modules-load.service
Wants=systemd-modules-load.service

[Service]
Type=oneshot
RemainAfterExit=yes
# Ensure clean reconfiguration (avoid 'Device or resource busy')
ExecStart=/sbin/ip link set %i down
ExecStart=/sbin/ip link set %i up type can bitrate ${BITRATE} restart-ms 100

[Install]
WantedBy=multi-user.target
"

  # Write only if changed
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: would write $svc"
  else
    if [[ -f "$svc" ]] && cmp -s <(printf "%s" "$content") "$svc"; then
      :
    else
      log "Schreibe systemd Service: $svc"
      printf "%s" "$content" | install -m 0644 /dev/stdin "$svc"
    fi
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: systemctl daemon-reload"
  else
    systemctl daemon-reload
  fi

  # Enable service for can0 (+ can1 optional)
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: systemctl enable --now can-marklin@can0.service"
  else
    systemctl enable --now can-marklin@can0.service
  fi

  if [[ "$ONLY_CAN0" -eq 0 ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "DRY-RUN: systemctl enable --now can-marklin@can1.service"
    else
      systemctl enable --now can-marklin@can1.service || true
    fi
  else
    # disable can1 service if present
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "DRY-RUN: systemctl disable --now can-marklin@can1.service"
    else
      systemctl disable --now can-marklin@can1.service >/dev/null 2>&1 || true
    fi
  fi
}

remove_networkd_can_configs() {
  # Optional: remove networkd CAN configs to avoid "Invalid argument" boot noise.
  if [[ "$KEEP_NETWORKD" -eq 1 ]]; then
    log "Behalte systemd-networkd CAN-Konfig (via --keep-networkd)."
    return 0
  fi

  log "Entferne systemd-networkd CAN-Konfigdateien (verhindert 'Invalid argument' beim Boot)…"
  run "rm -f /etc/systemd/network/10-can0.netdev /etc/systemd/network/10-can0.network || true"
  run "rm -f /etc/systemd/network/10-can1.netdev /etc/systemd/network/10-can1.network || true"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: systemctl restart systemd-networkd"
  else
    systemctl restart systemd-networkd >/dev/null 2>&1 || true
  fi
}

load_modules_now() {
  log "Lade Kernelmodule (sofort)…"
  run "modprobe can || true"
  run "modprobe can_raw || true"
  run "modprobe mcp251x || true"
}

show_status() {
  log "Status (sofern verfügbar):"
  if ip -details link show can0 >/dev/null 2>&1; then
    ip -details link show can0 || true
  else
    warn "can0 noch nicht vorhanden (Overlay wirkt ggf. erst nach Reboot)."
  fi

  if [[ "$ONLY_CAN0" -eq 0 ]]; then
    if ip -details link show can1 >/dev/null 2>&1; then
      ip -details link show can1 || true
    else
      warn "can1 noch nicht vorhanden (Overlay wirkt ggf. erst nach Reboot)."
    fi
  fi

  if systemctl status can-marklin@can0 >/dev/null 2>&1; then
    log "systemd Service can-marklin@can0:"
    systemctl status can-marklin@can0 --no-pager | sed -n '1,12p' || true
  fi
}

main() {
  parse_args "$@"
  require_root "$@"

  ensure_apt_packages

  local cfg
  cfg="$(detect_boot_config)"
  log "Verwende Boot-Konfig: $cfg"
  backup_file_once "$cfg"

  # Enable SPI once
  ensure_unique_exact_line "$cfg" "dtparam=spi=on"

  # Set overlays (canonical)
  ensure_overlay "$cfg" "can0" "$INT_CAN0"
  if [[ "$ONLY_CAN0" -eq 0 ]]; then
    ensure_overlay "$cfg" "can1" "$INT_CAN1"
  else
    remove_lines_matching "$cfg" "^dtoverlay=mcp2515-can1(,|$)"
  fi

  setup_modules_load
  load_modules_now

  # Install robust boot bring-up service
  install_can_marklin_service

  # Remove networkd CAN config by default (to avoid boot error message)
  remove_networkd_can_configs

  log "Setup abgeschlossen."
  log "Hinweis: Wenn Overlays neu gesetzt/geändert wurden, ist ein Reboot nötig: sudo reboot"
  show_status
}

main "$@"
