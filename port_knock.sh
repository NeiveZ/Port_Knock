#!/usr/bin/env bash
# knockscan - Port knock service detector
# Usage: ./knockscan.sh -t 192.168.1 -k 1337,80,443 -p 22

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────
R="\e[0m"; BOLD="\e[1m"
RD="\e[91m"; GR="\e[92m"; YL="\e[93m"; DG="\e[90m"

# ── Defaults ──────────────────────────────────────────────────────
TARGET=""          # Single IP or subnet prefix (e.g. 192.168.1 or 192.168.1.5)
KNOCK_PORTS=""     # Comma-separated knock sequence
TARGET_PORT=""     # Port to check after knocking
KNOCK_DELAY=100    # Delay between each knock in ms (default: 100ms)
OPEN_DELAY=2       # Seconds to wait after knock sequence before checking port
TIMEOUT=1          # Connection timeout in seconds
THREADS=20         # Max parallel hosts (subnet mode only)
OUTPUT=""          # Output file
SILENT=false       # Suppress per-host noise, show only findings

# ================================================================
#  HELP
# ================================================================

usage() {
cat << HELP
${BOLD}Usage:${R}
  $0 -t <target> -k <knock_ports> -p <target_port> [options]

${BOLD}Options:${R}
  -t, --target        Single IP or subnet prefix (required)
                      Single:  192.168.1.10
                      Subnet:  192.168.1  (scans .1 to .254)
  -k, --knock         Knock sequence, comma-separated (required)
                      e.g. 1337,80,443,8080
  -p, --port          Target port to check after knock (required)
  -d, --knock-delay   Delay between knocks in ms (default: 100)
  -w, --wait          Seconds to wait after knock before checking (default: 2)
  -T, --timeout       Connection timeout in seconds (default: 1)
  -t2, --threads      Parallel hosts in subnet mode (default: 20)
  -o, --output        Save findings to file
  --silent            Show findings only, suppress per-host logs
  -h, --help          Show this help

${BOLD}Examples:${R}
  # Test a single host
  $0 -t 192.168.1.10 -k 1337,80,443 -p 22

  # Scan a full /24 subnet
  $0 -t 192.168.1 -k 1337,80,443 -p 22

  # Custom timing, save results
  $0 -t 10.0.0 -k 500,1000,2000 -p 4444 -d 200 -w 3 -o findings.txt

  # Silent mode (findings only)
  $0 -t 192.168.1 -k 1337,80,443 -p 22 --silent
HELP
exit 0
}

# ================================================================
#  CORE FUNCTIONS
# ================================================================

log() {
    local level="$1" msg="$2"
    local ts; ts=$(date +'%H:%M:%S')
    case "$level" in
        info)  $SILENT || printf "${DG}[%s]${R} %s\n" "$ts" "$msg" ;;
        ok)    printf "${BOLD}${GR}[%s][+]${R} %s\n" "$ts" "$msg" ;;
        warn)  $SILENT || printf "${YL}[%s][!]${R} %s\n" "$ts" "$msg" ;;
        error) printf "${RD}[%s][-]${R} %s\n" "$ts" "$msg" ;;
    esac
}

# Send a single TCP packet to host:port (fire-and-forget)
# /dev/tcp failing is expected for closed ports — that IS the knock.
# We suppress errors deliberately here.
knock_port() {
    local host="$1" port="$2"
    bash -c "(echo > /dev/tcp/${host}/${port})" 2>/dev/null || true
}

# Execute the full knock sequence against a host
perform_knock() {
    local host="$1"
    local delay_sec
    delay_sec=$(echo "scale=3; $KNOCK_DELAY/1000" | bc)

    log info "  Knocking ${host}: ${KNOCK_PORTS}"

    IFS=',' read -ra ports <<< "$KNOCK_PORTS"
    for port in "${ports[@]}"; do
        knock_port "$host" "$port"
        sleep "$delay_sec"
    done
}

# Check if target port is open using nmap (preferred) or /dev/tcp fallback
check_port() {
    local host="$1"

    if command -v nmap &>/dev/null; then
        nmap -p "$TARGET_PORT" --open -T4 "$host" 2>/dev/null \
            | grep -q "${TARGET_PORT}/tcp open"
        return $?
    fi

    # /dev/tcp fallback
    timeout "$TIMEOUT" bash -c \
        "(echo > /dev/tcp/${host}/${TARGET_PORT})" 2>/dev/null
    return $?
}

# Probe the open port for a banner (TCP, not assumed HTTP)
grab_banner() {
    local host="$1"
    local banner=""

    banner=$(timeout "$TIMEOUT" bash -c \
        "echo '' | nc -w${TIMEOUT} ${host} ${TARGET_PORT} 2>/dev/null" \
        | head -3 | tr -d '\000') || true

    if [[ -z "$banner" ]] && command -v curl &>/dev/null; then
        banner=$(curl -m "$TIMEOUT" -s "http://${host}:${TARGET_PORT}" \
            | head -3) || true
    fi

    [[ -n "$banner" ]] && echo "$banner" || echo "(no banner)"
}

# Full test cycle for a single host
scan_host() {
    local host="$1"

    log info "Testing ${host}..."
    perform_knock "$host"

    log info "  Waiting ${OPEN_DELAY}s for port to activate..."
    sleep "$OPEN_DELAY"

    if check_port "$host"; then
        local banner
        banner=$(grab_banner "$host")

        log ok "SERVICE FOUND at ${host}:${TARGET_PORT}"
        $SILENT || echo -e "  ${DG}banner:${R} ${banner}"

        if [[ -n "$OUTPUT" ]]; then
            printf "[FOUND] %s:%s | knock: %s | banner: %s\n" \
                "$host" "$TARGET_PORT" "$KNOCK_PORTS" "$banner" >> "$OUTPUT"
        fi
    else
        log warn "  Port ${TARGET_PORT} did not open on ${host}"
    fi
}

# ================================================================
#  ARGUMENT PARSING
# ================================================================

[[ $# -eq 0 ]] && usage

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--target)       TARGET="$2";      shift 2 ;;
        -k|--knock)        KNOCK_PORTS="$2"; shift 2 ;;
        -p|--port)         TARGET_PORT="$2"; shift 2 ;;
        -d|--knock-delay)  KNOCK_DELAY="$2"; shift 2 ;;
        -w|--wait)         OPEN_DELAY="$2";  shift 2 ;;
        -T|--timeout)      TIMEOUT="$2";     shift 2 ;;
        -t2|--threads)     THREADS="$2";     shift 2 ;;
        -o|--output)       OUTPUT="$2";      shift 2 ;;
        --silent)          SILENT=true;      shift ;;
        -h|--help)         usage ;;
        *) echo -e "${RD}[!]${R} Unknown option: $1"; usage ;;
    esac
done

# ── Validations ───────────────────────────────────────────────────

[[ -z "$TARGET"      ]] && { echo -e "${RD}[!]${R} -t is required"; exit 1; }
[[ -z "$KNOCK_PORTS" ]] && { echo -e "${RD}[!]${R} -k is required"; exit 1; }
[[ -z "$TARGET_PORT" ]] && { echo -e "${RD}[!]${R} -p is required"; exit 1; }

for dep in bc; do
    command -v "$dep" &>/dev/null || { echo -e "${RD}[!]${R} missing dependency: $dep"; exit 1; }
done

# ── Determine mode: single IP or subnet ───────────────────────────

# A valid single IP has 3 dots; a subnet prefix has 2
if echo "$TARGET" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
    MODE="single"
elif echo "$TARGET" | grep -qE '^([0-9]{1,3}\.){2}[0-9]{1,3}$'; then
    MODE="subnet"
else
    echo -e "${RD}[!]${R} Invalid target: use full IP (192.168.1.10) or subnet prefix (192.168.1)"
    exit 1
fi

# ── Prepare output file ───────────────────────────────────────────

if [[ -n "$OUTPUT" ]]; then
    printf "# knockscan | target: %s | knock: %s | port: %s | %s\n\n" \
        "$TARGET" "$KNOCK_PORTS" "$TARGET_PORT" "$(date '+%Y-%m-%d %H:%M:%S')" > "$OUTPUT"
fi

# ================================================================
#  RUN
# ================================================================

START_TIME=$(date +%s)

if [[ "$MODE" == "single" ]]; then

    log info "Mode: single host | knock: ${KNOCK_PORTS} | target port: ${TARGET_PORT}"
    echo
    scan_host "$TARGET"

else

    log info "Mode: subnet ${TARGET}.0/24 | knock: ${KNOCK_PORTS} | target port: ${TARGET_PORT} | threads: ${THREADS}"
    echo

    FOUND=0
    declare -a jobs=()

    for octet in $(seq 1 254); do
        host="${TARGET}.${octet}"

        scan_host "$host" &
        jobs+=($!)

        # Thread pool control
        while [[ ${#jobs[@]} -ge $THREADS ]]; do
            alive=()
            for pid in "${jobs[@]}"; do
                kill -0 "$pid" 2>/dev/null && alive+=("$pid")
            done
            jobs=("${alive[@]}")
            [[ ${#jobs[@]} -ge $THREADS ]] && sleep 0.1
        done
    done

    for pid in "${jobs[@]}"; do wait "$pid" 2>/dev/null || true; done

fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo
log info "Scan complete | time: ${ELAPSED}s"
[[ -n "$OUTPUT" ]] && log info "Saved: ${OUTPUT}"a
