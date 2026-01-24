#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Raspberry Pi + Waveshare 2-CH Isolated CAN HAT (MCP2515) -> Märklin mBus
# - CAN bitrate: 250000
# - DeviceTree overlays: mcp2515-can0/can1 (16MHz), INT GPIO 23/25
# - systemd-networkd brings can0/can1 up on boot
#
# Usage:
#   sudo ./setup_can_marklin.sh
#   sudo ./setup_can_marklin.sh --only-can0
#   sudo ./setup_can_marklin.sh --dry-run
###############################################################################

# --- Defaults (Waveshare typical) ---
BITRATE="250000"
OSC="16000000"
SPI_MAX="10000000"
INT_CAN0="23"
INT_CAN1="25"

ONLY_CAN0="0"
DRY_RUN="0"

LOG_PREFIX="[CAN-SETUP]"

###############################################################################
# Helpers
###############################################################################
log() { echo "${LOG_PREFIX} $*"; }
warn() { echo "${LOG_PREFIX} WARN: $*" >&2; }
die() { echo "${LOG_PREFIX} ERROR: $*" >&2; exit 1; }

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
      -h|--help)
        cat <<EOF
Usage: sudo $0 [--only-can0] [--dry-run]

--only-can0   Konfiguriert nur can0 (entfernt can1 Setup-Dateien/Overlay-Zeile)
--dry-run     Zeigt nur, was geändert würde
EOF
        exit 0
        ;;
      *)
        die "Unbekannter Parameter: $1"
        ;;
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

# Ensure a line exists exactly once (exact match):
# - if missing -> append
# - if multiple -> keep first occurrence, remove others
ensure_unique_exact_line() {
  local file="$1"
  local line="$2"

  run "touch \"$file\""

  if grep -Fxq "$line" "$file"; then
    # Remove duplicates beyond first exact match
    run "awk -v target='$line' ' \$0==target {c++; if(c>1) next} {print}' \"$file\" > \"${file}.tmp\""
    run "mv \"${file}.tmp\" \"$file\""
  else
    run "printf '%s\n' \"$line\" >> \"$file\""
  fi
}

# Remove all lines matching regex (POSIX ERE)
remove_lines_matching() {
  local file="$1"
  local regex="$2"
  run "touch \"$file\""
  run "awk -v re='$regex' ' \$0 ~ re {next} {print}' \"$file\" > \"${file}.tmp\""
  run "mv \"${file}.tmp\" \"$file\""
}

ensure_overlay_line() {
  local file="$1"
  local can="$2"   # can0 / can1

  local intr osc spimax canonical
  if [[ "$can" == "can0" ]]; then
    intr="$INT_CAN0"
  else
    intr="$INT_CAN1"
  fi
  osc="$OSC"
  spimax="$SPI_MAX"

  canonical="dtoverlay=mcp2515-${can},oscillator=${osc},interrupt=${intr},spimaxfrequency=${spimax}"

  # Remove any existing overlay lines for this canX and set canonical once
  remove_lines_matching "$file" "^dtoverlay=mcp2515-${can}(,|$)"
  ensure_unique_exact_line "$file" "$canonical"
}

ensure_modules_load() {
  local file="/etc/modules-load.d/can.conf"
  run "touch \"$file\""

  # Ensure required modules lines exist exactly once
  ensure_unique_exact_line "$file" "can"
  ensure_unique_exact_line "$file" "can_raw"
  ensure_unique_exact_line "$file" "mcp251x"

  # Deduplicate any other duplicates in file (preserve first occurrence)
  run "awk '!seen[\$0]++' \"$file\" > \"${file}.tmp\""
  run "mv \"${file}.tmp\" \"$file\""
}

write_file_if_changed() {
  local path="$1"
  local content="$2"
  local tmp
  tmp="$(mktemp)"

  printf "%s" "$content" > "$tmp"

  if [[ -f "$path" ]] && cmp -s "$tmp" "$path"; then
    rm -f "$tmp"
    return 0
  fi

  log "Schreibe: $path"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: Inhalt würde gesetzt werden."
    rm -f "$tmp"
    return 0
  fi

  install -m 0644 "$tmp" "$path"
  rm -f "$tmp"
}

###############################################################################
# APT / OS checks
###############################################################################
is_debian_like() {
  [[ -f /etc/debian_version ]] && return 0
  return 1
}

ensure_apt_packages() {
  if ! command -v apt-get >/dev/null 2>&1; then
    warn "apt-get nicht gefunden – überspringe Paketprüfung."
    return 0
  fi

  # Diagnose/Tooling. Für den Betrieb selbst nicht zwingend, aber produktiv sinnvoll.
  local pkgs=(can-utils)

  local missing=()
  for p in "${pkgs[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
  done

  if [[ "${#missing[@]}" -eq 0 ]]; then
    log "APT: Alle empfohlenen Pakete vorhanden (${pkgs[*]})."
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

###############################################################################
# systemd-networkd configuration
###############################################################################
setup_systemd_networkd_can() {
  run "mkdir -p /etc/systemd/network"

  local netdev_can0="[NetDev]
Name=can0
Kind=can

[CAN]
BitRate=${BITRATE}
RestartSec=100ms
"
  local network_can0="[Match]
Name=can0

[Network]
"
  write_file_if_changed "/etc/systemd/network/10-can0.netdev" "$netdev_can0"
  write_file_if_changed "/etc/systemd/network/10-can0.network" "$network_can0"

  if [[ "$ONLY_CAN0" -eq 0 ]]; then
    local netdev_can1="[NetDev]
Name=can1
Kind=can

[CAN]
BitRate=${BITRATE}
RestartSec=100ms
"
    local network_can1="[Match]
Name=can1

[Network]
"
    write_file_if_changed "/etc/systemd/network/10-can1.netdev" "$netdev_can1"
    write_file_if_changed "/etc/systemd/network/10-can1.network" "$network_can1"
  else
    log "Nur can0: entferne ggf. can1 networkd-Dateien"
    run "rm -f /etc/systemd/network/10-can1.netdev /etc/systemd/network/10-can1.network || true"
  fi

  # Enable & restart networkd
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: systemctl enable --now systemd-networkd; systemctl restart systemd-networkd"
    return 0
  fi

  systemctl enable --now systemd-networkd >/dev/null 2>&1 || true
  systemctl restart systemd-networkd >/dev/null 2>&1 || true
}

###############################################################################
# Runtime checks
###############################################################################
overlay_present_hint() {
  # Overlay files can be in /boot/overlays or /boot/firmware/overlays
  if [[ -d /boot/firmware/overlays ]]; then
    ls /boot/firmware/overlays/mcp2515-can*.dtbo >/dev/null 2>&1 && return 0
  fi
  if [[ -d /boot/overlays ]]; then
    ls /boot/overlays/mcp2515-can*.dtbo >/dev/null 2>&1 && return 0
  fi
  return 1
}

load_modules_now() {
  log "Lade Kernelmodule (sofort, ohne Reboot; Overlays wirken i.d.R. erst nach Reboot)…"
  run "modprobe can || true"
  run "modprobe can_raw || true"
  run "modprobe mcp251x || true"
}

show_can_status() {
  if command -v ip >/dev/null 2>&1; then
    if ip -details link show can0 >/dev/null 2>&1; then
      log "Status can0:"
      ip -details link show can0 || true
    else
      warn "can0 ist aktuell nicht vorhanden. Das ist normal, wenn die Overlays neu gesetzt wurden -> Reboot nötig."
    fi

    if [[ "$ONLY_CAN0" -eq 0 ]]; then
      if ip -details link show can1 >/dev/null 2>&1; then
        log "Status can1:"
        ip -details link show can1 || true
      else
        warn "can1 ist aktuell nicht vorhanden (evtl. Reboot nötig oder nur can0 genutzt)."
      fi
    fi
  else
    warn "'ip' nicht gefunden (iproute2 fehlt?)"
  fi
}

###############################################################################
# Main
###############################################################################
main() {
  parse_args "$@"
  require_root "$@"

  if ! is_debian_like; then
    warn "Dieses Skript ist für Debian/Raspberry Pi OS gedacht. Fortfahren auf eigenes Risiko."
  fi

  if ! overlay_present_hint; then
    warn "mcp2515-can*.dtbo Overlays nicht gefunden. Auf Raspberry Pi OS ist das normal vorhanden; auf 'plain Debian' ggf. nicht."
  fi

  ensure_apt_packages

  local cfg
  cfg="$(detect_boot_config)"
  log "Verwende Boot-Konfig: $cfg"
  backup_file_once "$cfg"

  # Boot config: SPI + overlays (canonical, no duplicates)
  ensure_unique_exact_line "$cfg" "dtparam=spi=on"

  ensure_overlay_line "$cfg" "can0"
  if [[ "$ONLY_CAN0" -eq 0 ]]; then
    ensure_overlay_line "$cfg" "can1"
  else
    remove_lines_matching "$cfg" "^dtoverlay=mcp2515-can1(,|$)"
  fi

  ensure_modules_load
  setup_systemd_networkd_can
  load_modules_now

  log "Setup abgeschlossen."
  log "Wichtig: Wenn du die Device-Tree Overlays gerade neu gesetzt/geändert hast, ist ein Reboot erforderlich,"
  log "damit can0/can1 als Geräte angelegt werden:  sudo reboot"

  show_can_status

  log "Optionaler Test (nach Reboot, Gleisbox an): candump can0"
}

main "$@"
