#!/usr/bin/env bash
set -Eeuo pipefail

CAN_IF="can0"
TIMEOUT_SEC=5
EXPECTED_BITRATE="250000"
DO_FIX="0"

log()  { echo "[CAN-HEALTH] $*"; }
warn() { echo "[CAN-HEALTH] WARN: $*" >&2; }
fail() { echo "[CAN-HEALTH] ERROR: $*" >&2; exit 1; }

trap 'rc=$?; warn "Abbruch (rc=$rc) in Zeile $LINENO: $BASH_COMMAND"; exit $rc' ERR

usage() {
  cat <<EOU
Usage:
  sudo $0 [can0|can1] [--fix] [--timeout N]

Beispiele:
  sudo $0
  sudo $0 can1
  sudo $0 can0 --fix
EOU
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      can0|can1) CAN_IF="$1"; shift ;;
      --fix) DO_FIX="1"; shift ;;
      --timeout) TIMEOUT_SEC="${2:-5}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) fail "Unbekannter Parameter: $1" ;;
    esac
  done
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || fail "Bitte als root ausführen: sudo $0 ${CAN_IF}"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Fehlt: $1"
}

details() {
  ip -details link show "$CAN_IF" 2>/dev/null || true
}

iface_exists() {
  ip link show "$CAN_IF" >/dev/null 2>&1 || fail "Interface $CAN_IF existiert nicht."
}

read_link_state() {
  details | grep -Eo 'state [A-Z]+' | awk '{print $2}' || true
}

read_can_state() {
  details | grep -Eo 'can state [A-Z_-]+' | awk '{print $3}' || true
}

read_bitrate() {
  details | grep -Eo 'bitrate [0-9]+' | awk '{print $2}' || true
}

svc_name() { echo "can-marklin@${CAN_IF}.service"; }

check_service_presence() {
  if systemctl list-unit-files --no-pager 2>/dev/null | grep -q '^can-marklin@\.service'; then
    log "Boot-Service Template gefunden: can-marklin@.service"
    return 0
  fi
  warn "Boot-Service Template NICHT gefunden (optional): can-marklin@.service"
  return 1
}

check_service_state() {
  local s
  s="$(svc_name)"

  if ! systemctl list-unit-files --no-pager 2>/dev/null | grep -q '^can-marklin@\.service'; then
    return 0
  fi

  if systemctl is-enabled "$s" >/dev/null 2>&1; then
    log "Boot-Service enabled: $s"
  else
    warn "Boot-Service NICHT enabled: $s"
    if [[ "$DO_FIX" -eq 1 ]]; then
      log "FIX: enable --now $s"
      systemctl enable --now "$s" || warn "Konnte $s nicht aktivieren."
    else
      warn "Tipp: sudo systemctl enable --now $s"
    fi
  fi

  if systemctl is-active "$s" >/dev/null 2>&1; then
    log "Boot-Service active:  $s"
  else
    warn "Boot-Service not active: $s"
    if [[ "$DO_FIX" -eq 1 ]]; then
      log "FIX: starte $s"
      systemctl start "$s" || true
    fi
  fi
}

bring_up_hint() {
  cat >&2 <<EOH
[CAN-HEALTH] Vorschlag:
  sudo ip link set ${CAN_IF} down
  sudo ip link set ${CAN_IF} up type can bitrate ${EXPECTED_BITRATE} restart-ms 100
EOH
}

fix_interface() {
  log "FIX: Setze ${CAN_IF} neu (down -> up mit bitrate ${EXPECTED_BITRATE})"
  ip link set "${CAN_IF}" down || true
  ip link set "${CAN_IF}" up type can bitrate "${EXPECTED_BITRATE}" restart-ms 100
}

check_bitrate() {
  local br
  br="$(read_bitrate)"
  if [[ -z "${br:-}" ]]; then
    warn "Bitrate nicht auslesbar (bei DOWN/STOPPED üblich)."
    return 0
  fi

  if [[ "$br" != "$EXPECTED_BITRATE" ]]; then
    warn "Bitrate ist $br (erwartet $EXPECTED_BITRATE)."
  else
    log "Bitrate korrekt: $EXPECTED_BITRATE bit/s"
  fi
}

check_states_and_maybe_fix() {
  local lstate cstate
  lstate="$(read_link_state)"
  cstate="$(read_can_state)"

  log "Link-State: ${lstate:-unbekannt}"
  log "CAN-State : ${cstate:-unbekannt}"

  if [[ "${cstate:-}" == "BUS-OFF" ]]; then
    fail "BUS-OFF! Häufig: CANH/CANL vertauscht, Terminierung falsch, kein Gegenpart aktiv."
  fi

  if [[ "${cstate:-}" == "STOPPED" || "${lstate:-}" == "DOWN" ]]; then
    warn "Interface ist DOWN/STOPPED → CAN ist nicht gestartet."
    bring_up_hint
    if [[ "$DO_FIX" -eq 1 ]]; then
      fix_interface
      log "Nach FIX:"
      ip -details link show "$CAN_IF" || true
    else
      return 10
    fi
  fi

  if [[ "${cstate:-}" == "ERROR-PASSIVE" ]]; then
    warn "ERROR-PASSIVE → Terminierung/Verkabelung/Masse prüfen."
  fi

  return 0
}

check_traffic() {
  need_cmd candump

  log "Lausche ${TIMEOUT_SEC}s auf CAN-Traffic (Gleisbox muss eingeschaltet sein)…"

  if command -v timeout >/dev/null 2>&1; then
    if timeout "${TIMEOUT_SEC}s" candump -L "$CAN_IF" 2>/dev/null | head -n 1 | grep -q .; then
      log "CAN-Traffic empfangen ✔"
    else
      warn "Kein Traffic empfangen!"
      warn "→ Gleisbox an? → CANH/CANL korrekt? → GND verbunden? → Terminierung korrekt?"
    fi
  else
    warn "'timeout' fehlt – nutze Fallback."
    local tmp pid
    tmp="$(mktemp)"
    candump -L "$CAN_IF" >"$tmp" 2>/dev/null & pid=$!
    sleep "$TIMEOUT_SEC" || true
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true

    if head -n 1 "$tmp" | grep -q .; then
      log "CAN-Traffic empfangen ✔"
    else
      warn "Kein Traffic empfangen!"
    fi
    rm -f "$tmp"
  fi
}

main() {
  parse_args "$@"
  require_root
  need_cmd ip
  iface_exists

  log "Starte Health Check für $CAN_IF"

  check_service_presence || true
  check_service_state || true

  check_bitrate
  check_states_and_maybe_fix || true

  local lstate cstate
  lstate="$(read_link_state)"
  cstate="$(read_can_state)"
  if [[ "${cstate:-}" == "STOPPED" || "${lstate:-}" == "DOWN" ]]; then
    log "Traffic-Test übersprungen (Interface nicht UP)."
    exit 0
  fi

  check_bitrate
  check_traffic
  log "Health Check abgeschlossen."
}

main "$@"



