#!/bin/bash
# Root Reconciler for TunnelSats on myNode BTC
# Manages /mnt/hdd/mynode/settings/lnd_extra_config.conf (# BEGIN TUNNELSATS ... # END TUNNELSATS)
# and orchestrates tunnelsats.sh --managed mynode from root-owned paths only.

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$(id -u)" -eq 0 ]; then
    export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    TUNNELSATS_DATA_DIR="/mnt/hdd/mynode/tunnelsats"
    TUNNELSATS_CONF_PATH="${TUNNELSATS_DATA_DIR}/tunnelsatsv2.conf"
    TUNNELSATS_APP_CONFIG="${TUNNELSATS_DATA_DIR}/config.json"
    DESIRED_STATE_FILE="${TUNNELSATS_DATA_DIR}/desired-state.json"
    MYNODE_SETTINGS_DIR="/mnt/hdd/mynode/settings"
    LND_EXTRA_CONFIG="${MYNODE_SETTINGS_DIR}/lnd_extra_config.conf"
    LND_MAIN_CONFIG="/mnt/hdd/mynode/lnd/lnd.conf"
    MYNODE_GEN_LND_CONFIG="/usr/bin/mynode_gen_lnd_config.sh"
    WG_DIR="/etc/wireguard"
    WG_CONF_DST="${WG_DIR}/tunnelsatsv2.conf"
    MANAGED_INVENTORY="/etc/tunnelsats/managed.json"
    SECURE_MODE_FILE="/etc/tunnelsats/secure_mode"
    RECONCILE_STATUS_FILE="/run/tunnelsats/reconcile-status.json"
    RECONCILE_LOCK_FILE="/run/lock/tunnelsats-reconcile.lock"
    TUNNELSATS_LN_IMPL="lnd"
    SYSTEMCTL_BIN="/bin/systemctl"
    if [ ! -x "$SYSTEMCTL_BIN" ]; then
        SYSTEMCTL_BIN="/usr/bin/systemctl"
    fi
    SUDOERS_LEGACY_FILE="/etc/sudoers.d/tunnelsats-reconcile"
    RECONCILE_SBIN="/usr/local/sbin/tunnelsats-reconcile"
else
    TUNNELSATS_DATA_DIR="${TUNNELSATS_DATA_DIR:-/mnt/hdd/mynode/tunnelsats}"
    TUNNELSATS_CONF_PATH="${TUNNELSATS_CONF_PATH:-${TUNNELSATS_DATA_DIR}/tunnelsatsv2.conf}"
    TUNNELSATS_APP_CONFIG="${TUNNELSATS_APP_CONFIG:-${TUNNELSATS_DATA_DIR}/config.json}"
    DESIRED_STATE_FILE="${DESIRED_STATE_FILE:-${TUNNELSATS_DATA_DIR}/desired-state.json}"
    MYNODE_SETTINGS_DIR="${MYNODE_SETTINGS_DIR:-/mnt/hdd/mynode/settings}"
    LND_EXTRA_CONFIG="${LND_EXTRA_CONFIG:-${MYNODE_LND_EXTRA_CONF:-${MYNODE_SETTINGS_DIR}/lnd_extra_config.conf}}"
    LND_MAIN_CONFIG="${LND_MAIN_CONFIG:-${MYNODE_LND_CONF:-/mnt/hdd/mynode/lnd/lnd.conf}}"
    MYNODE_GEN_LND_CONFIG="${MYNODE_GEN_LND_CONFIG:-/usr/bin/mynode_gen_lnd_config.sh}"
    WG_DIR="${WG_DIR:-/etc/wireguard}"
    WG_CONF_DST="${WG_CONF_DST:-${WG_DIR}/tunnelsatsv2.conf}"
    MANAGED_INVENTORY="${MANAGED_INVENTORY:-/etc/tunnelsats/managed.json}"
    SECURE_MODE_FILE="${SECURE_MODE_FILE:-${TUNNELSATS_DATA_DIR}/.secure_mode_root}"
    RECONCILE_STATUS_FILE="${RECONCILE_STATUS_FILE:-${TUNNELSATS_DATA_DIR}/reconcile-status.json}"
    RECONCILE_LOCK_FILE="${RECONCILE_LOCK_FILE:-${TUNNELSATS_DATA_DIR}/reconcile.lock}"
    TUNNELSATS_LN_IMPL="lnd"
    SYSTEMCTL_BIN="${SYSTEMCTL_BIN:-systemctl}"
    SUDOERS_LEGACY_FILE="${SUDOERS_FILE:-/etc/sudoers.d/tunnelsats-reconcile}"
    RECONCILE_SBIN="${RECONCILE_SBIN:-/usr/local/sbin/tunnelsats-reconcile}"
fi

BLOCK_CHANGED=0
EXTRACTED_VPN_DNS=""
EXTRACTED_VPN_PORT="9735"
EXTRACTED_WG_PRIVKEY=""
EXTRACTED_WG_ADDRESS=""
EXTRACTED_WG_MTU=""
EXTRACTED_WG_PUBKEY=""
EXTRACTED_WG_PSK=""
EXTRACTED_WG_ENDPOINT=""
EXTRACTED_WG_ALLOWED_IPS=""
EXTRACTED_WG_KEEPALIVE="25"

is_root_owned_regular_script() {
    local candidate="$1"
    if [ -L "$candidate" ] || [ ! -f "$candidate" ] || [ ! -x "$candidate" ]; then
        return 1
    fi
    local owner_perm
    owner_perm="$(stat -c '%u:%g:%a' "$candidate" 2>/dev/null || echo "")"
    case "$owner_perm" in
        0:0:755|0:0:750|0:0:700|0:0:555|0:0:500) return 0 ;;
        *) return 1 ;;
    esac
}

resolve_ts_sh_bin() {
    if [ "$(id -u)" -eq 0 ]; then
        local candidate
        for candidate in \
            "/usr/local/sbin/tunnelsats" \
            "/usr/share/mynode_apps/tunnelsats/root_scripts/tunnelsats.sh"; do
            if is_root_owned_regular_script "$candidate"; then
                printf '%s\n' "$candidate"
                return 0
            fi
        done
        echo "ERROR: No root-owned tunnelsats binary found in /usr/local/sbin/tunnelsats or /usr/share/mynode_apps/tunnelsats/root_scripts/tunnelsats.sh" >&2
        return 1
    fi

    if [ -n "${TS_SH_BIN:-}" ]; then
        printf '%s\n' "$TS_SH_BIN"
        return 0
    fi
    if [ -n "${TUNNELSATS_SH:-}" ]; then
        printf '%s\n' "$TUNNELSATS_SH"
        return 0
    fi
    if [ -x "${SCRIPT_DIR}/tunnelsats.sh" ]; then
        printf '%s\n' "${SCRIPT_DIR}/tunnelsats.sh"
        return 0
    fi
    if [ -x "/usr/local/sbin/tunnelsats" ]; then
        printf '%s\n' "/usr/local/sbin/tunnelsats"
        return 0
    fi
    printf '%s\n' "${SCRIPT_DIR}/tunnelsats.sh"
}

is_secure_mode() {
    if [ -f "$SECURE_MODE_FILE" ] && [ ! -L "$SECURE_MODE_FILE" ]; then
        return 0
    fi
    if [ "$(id -u)" -ne 0 ]; then
        case "${SECURE_MODE:-}" in
            true|TRUE|1|yes|YES) return 0 ;;
            false|FALSE|0|no|NO) return 1 ;;
        esac
    fi
    if [ -f "$TUNNELSATS_APP_CONFIG" ] && [ ! -L "$TUNNELSATS_APP_CONFIG" ]; then
        if python3 - "$TUNNELSATS_APP_CONFIG" <<'PY' 2>/dev/null
import json, os, stat, sys
p = sys.argv[1]
fd = os.open(p, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
try:
    st = os.fstat(fd)
    if not stat.S_ISREG(st.st_mode) or st.st_size > 65536:
        sys.exit(1)
    raw = os.read(fd, 65536).decode("utf-8")
finally:
    os.close(fd)
data = json.loads(raw)
if isinstance(data, dict) and any(data.get(k) is True for k in ("secure-mode", "secureMode", "secure_mode")):
    sys.exit(0)
sys.exit(1)
PY
        then
            return 0
        fi
    fi
    return 1
}

persist_desired_state() {
    local desired_target="$1"
    local req_id="${2:-}"
    local desired_dir
    desired_dir="$(dirname "$DESIRED_STATE_FILE")"
    if [ -z "$desired_target" ] || [ ! -d "$desired_dir" ] || [ -L "$desired_dir" ] || [ -L "$DESIRED_STATE_FILE" ]; then
        return 0
    fi
    if [ "$(id -u)" -eq 0 ] && id -u tunnelsats >/dev/null 2>&1 && command -v runuser >/dev/null 2>&1; then
        runuser -u tunnelsats -g tunnelsats -- python3 - "$DESIRED_STATE_FILE" "$desired_target" "$req_id" <<'PY' 2>/dev/null || true
import datetime, json, os, secrets, sys
dst, desired, req_id = sys.argv[1:4]
if os.path.islink(dst):
    sys.exit(0)
doc = {
    "version": 1,
    "desired": desired,
    "updatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
}
if req_id:
    doc["requestId"] = req_id
tmp = f"{dst}.tmp.{os.getpid()}.{secrets.token_hex(6)}"
fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(doc, f)
    f.write("\n")
os.chmod(tmp, 0o600)
os.replace(tmp, dst)
PY
    else
        python3 - "$DESIRED_STATE_FILE" "$desired_target" "$req_id" <<'PY' 2>/dev/null || true
import datetime, json, os, secrets, sys
dst, desired, req_id = sys.argv[1:4]
if os.path.islink(dst):
    sys.exit(0)
doc = {
    "version": 1,
    "desired": desired,
    "updatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
}
if req_id:
    doc["requestId"] = req_id
tmp = f"{dst}.tmp.{os.getpid()}.{secrets.token_hex(6)}"
fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(doc, f)
    f.write("\n")
os.chmod(tmp, 0o600)
os.replace(tmp, dst)
PY
    fi
}

write_reconcile_status() {
    local status_str="$1"
    local action_str="$2"
    local req_id="${3:-}"
    local err_msg="${4:-}"
    local status_dir
    status_dir="$(dirname "$RECONCILE_STATUS_FILE")"
    mkdir -p "$status_dir" 2>/dev/null || return 0
    if [ "$(id -u)" -eq 0 ]; then
        chmod 0755 "$status_dir" 2>/dev/null || true
    fi
    python3 - "$RECONCILE_STATUS_FILE" "$status_str" "$action_str" "$req_id" "$err_msg" <<'PY' 2>/dev/null || true
import datetime, json, os, sys
dst, st, act, req_id, err = sys.argv[1:6]
payload = {
    "status": st,
    "action": act,
    "requestId": req_id or None,
    "error": err or None,
    "updatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
}
tmp = f"{dst}.tmp.{os.getpid()}"
fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, "O_NOFOLLOW", 0), 0o644)
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(payload, f)
    f.write("\n")
os.chmod(tmp, 0o644)
os.replace(tmp, dst)
PY
    if [ "$status_str" = "ok" ]; then
        case "$action_str" in
            apply) persist_desired_state "active" "$req_id" ;;
            restore|uninstall) persist_desired_state "tor-only" "$req_id" ;;
        esac
    fi
}

refuse_if_secure_mode() {
    local action="$1"
    local req_id="${2:-}"
    if is_secure_mode; then
        write_reconcile_status "blocked_secure_mode" "$action" "$req_id" "SECURE_MODE is enabled"
        echo "ERROR: SECURE_MODE is enabled; automated reconciler '${action}' is disabled. Run the TunnelSats CLI manually over SSH." >&2
        exit 7
    fi
}

valid_dns_or_ip() {
    local host="$1"
    if [ -z "$host" ] || [ "${#host}" -gt 253 ]; then
        return 1
    fi
    if [[ ! "$host" =~ ^[A-Za-z0-9.-]+$ ]]; then
        return 1
    fi
    if [[ "$host" == .* ]] || [[ "$host" == *. ]] || [[ "$host" == *..* ]]; then
        return 1
    fi
    return 0
}

valid_port() {
    local port="$1"
    if [[ ! "$port" =~ ^[0-9]{1,5}$ ]]; then
        return 1
    fi
    local p
    p=$((10#$port))
    if [ "$p" -lt 1 ] || [ "$p" -gt 65535 ]; then
        return 1
    fi
    return 0
}

write_bitcoin_owned_file() {
    local target="$1"
    local stage_src="$2"
    local file_mode="${3:-0644}"
    if [ -L "$target" ]; then
        echo "ERROR: Refusing to write through symlink: ${target}" >&2
        return 8
    fi
    local dir
    dir="$(dirname "$target")"
    if [ -L "$dir" ]; then
        echo "ERROR: Refusing symlinked parent directory: ${dir}" >&2
        return 8
    fi
    if [ "$(id -u)" -eq 0 ] && id -u bitcoin >/dev/null 2>&1 && command -v runuser >/dev/null 2>&1; then
        mkdir -p "$dir"
        if [ "$(stat -c '%u' "$dir" 2>/dev/null || echo 0)" -eq 0 ]; then
            chown -h bitcoin:bitcoin "$dir" 2>/dev/null || true
            chmod 0755 "$dir" 2>/dev/null || true
        fi
        runuser -u bitcoin -g bitcoin -- python3 - "$target" "$file_mode" 3< "$stage_src" <<'PY'
import os, secrets, sys
target, mode_s = sys.argv[1:3]
if os.path.islink(target):
    sys.exit(8)
with os.fdopen(3, "rb") as f_in:
    data = f_in.read()
mode = int(mode_s, 8)
tmp = f"{target}.tmp.{os.getpid()}.{secrets.token_hex(6)}"
fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), mode)
try:
    with os.fdopen(fd, "wb") as f_out:
        f_out.write(data)
        f_out.flush()
        os.fsync(f_out.fileno())
    os.chmod(tmp, mode)
    if os.path.islink(target):
        raise OSError("Target became symlink")
    os.replace(tmp, target)
except Exception:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
PY
    else
        mkdir -p "$dir"
        local tmp
        tmp="$(mktemp "${target}.tmp.XXXXXX")"
        cp "$stage_src" "$tmp"
        chmod "$file_mode" "$tmp"
        mv -f "$tmp" "$target"
    fi
}

alloc_stage_tmp() {
    local stage_dir="/run/tunnelsats"
    if [ "$(id -u)" -ne 0 ] || ! install -d -m 0755 "$stage_dir" 2>/dev/null; then
        stage_dir="${TMPDIR:-/tmp}"
    fi
    mktemp "${stage_dir}/ts-reconcile.XXXXXX"
}

block_insert() {
    local dns="${1:-}"
    local port="${2:-}"
    BLOCK_CHANGED=0
    if [ -z "$port" ] && [[ "$dns" == *:* ]]; then
        port="${dns##*:}"
        dns="${dns%:*}"
    fi
    if ! valid_dns_or_ip "$dns"; then
        echo "ERROR: Invalid VPN DNS/host '${dns}'" >&2
        return 8
    fi
    if ! valid_port "$port"; then
        echo "ERROR: Invalid VPN port '${port}'" >&2
        return 8
    fi
    port="$((10#$port))"

    if [ -L "$LND_EXTRA_CONFIG" ]; then
        echo "ERROR: Refusing symlinked LND extra config: ${LND_EXTRA_CONFIG}" >&2
        return 8
    fi

    local stage_tmp
    stage_tmp="$(alloc_stage_tmp)"

    local block
    block=$(cat <<EOF
# BEGIN TUNNELSATS
[Application Options]
listen=0.0.0.0:9735
externalhosts=${dns}:${port}
[Tor]
tor.skip-proxy-for-clearnet-targets=true
tor.streamisolation=false
[Application Options]
# END TUNNELSATS
EOF
)

    if [ -f "$LND_EXTRA_CONFIG" ]; then
        awk -v new_block="$block" '
            BEGIN { in_block = 0; replaced = 0 }
            /^[[:space:]]*#[[:space:]]*BEGIN TUNNELSATS[[:space:]]*$/ {
                if (!replaced) {
                    print new_block
                    replaced = 1
                }
                in_block = 1
                next
            }
            /^[[:space:]]*#[[:space:]]*END TUNNELSATS[[:space:]]*$/ {
                in_block = 0
                next
            }
            !in_block { print }
            END {
                if (!replaced) {
                    if (NR > 0) print ""
                    print new_block
                }
            }
        ' "$LND_EXTRA_CONFIG" > "$stage_tmp"
    else
        printf '%s\n' "$block" > "$stage_tmp"
    fi

    if [ -f "$LND_EXTRA_CONFIG" ] && cmp -s "$stage_tmp" "$LND_EXTRA_CONFIG"; then
        rm -f "$stage_tmp"
        BLOCK_CHANGED=0
        return 0
    fi

    if ! write_bitcoin_owned_file "$LND_EXTRA_CONFIG" "$stage_tmp" "0644"; then
        rm -f "$stage_tmp"
        return 8
    fi
    rm -f "$stage_tmp"
    BLOCK_CHANGED=1
}

block_remove() {
    BLOCK_CHANGED=0
    if [ -L "$LND_EXTRA_CONFIG" ]; then
        echo "ERROR: Refusing symlinked LND extra config: ${LND_EXTRA_CONFIG}" >&2
        return 8
    fi
    if [ ! -f "$LND_EXTRA_CONFIG" ]; then
        return 0
    fi
    local stage_tmp
    stage_tmp="$(alloc_stage_tmp)"
    awk '
        BEGIN { in_block = 0 }
        /^[[:space:]]*#[[:space:]]*BEGIN TUNNELSATS[[:space:]]*$/ { in_block = 1; next }
        /^[[:space:]]*#[[:space:]]*END TUNNELSATS[[:space:]]*$/ { in_block = 0; next }
        !in_block { print }
    ' "$LND_EXTRA_CONFIG" > "$stage_tmp"

    if cmp -s "$stage_tmp" "$LND_EXTRA_CONFIG"; then
        rm -f "$stage_tmp"
        BLOCK_CHANGED=0
        return 0
    fi

    if ! write_bitcoin_owned_file "$LND_EXTRA_CONFIG" "$stage_tmp" "0644"; then
        rm -f "$stage_tmp"
        return 8
    fi
    rm -f "$stage_tmp"
    BLOCK_CHANGED=1
}

block_status() {
    python3 - "$LND_EXTRA_CONFIG" <<'PY'
import json, os, stat, sys
path = sys.argv[1]
out = {
    "present": False,
    "externalhosts": None,
    "listen": None,
    "skip_proxy": False,
    "streamisolation_false": False,
    "file": path,
}
try:
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
    try:
        st = os.fstat(fd)
        if stat.S_ISREG(st.st_mode) and st.st_size <= 262144:
            text = os.read(fd, 262144).decode("utf-8", errors="replace")
        else:
            text = ""
    finally:
        os.close(fd)
except OSError:
    text = ""

in_block = False
for raw in text.splitlines():
    line = raw.strip()
    if line == "# BEGIN TUNNELSATS":
        in_block = True
        out["present"] = True
        continue
    if line == "# END TUNNELSATS":
        in_block = False
        continue
    if in_block:
        if line.startswith("externalhosts="):
            out["externalhosts"] = line.split("=", 1)[1].strip()
        elif line.startswith("listen="):
            out["listen"] = line.split("=", 1)[1].strip()
        elif line in ("tor.skip-proxy-for-clearnet-targets=true", "tor.skip-proxy-for-clearnet-targets=1"):
            out["skip_proxy"] = True
        elif line in ("tor.streamisolation=false", "tor.streamisolation=0"):
            out["streamisolation_false"] = True

print(json.dumps(out, separators=(",", ":")))
PY
}

snapshot_and_validate_wg_conf() {
    local src_path="$1"
    local snap_dst="$2"
    local parsed_env
    if ! parsed_env="$(python3 - "$src_path" "$snap_dst" <<'PY'
import ipaddress, os, re, shlex, stat, sys

src, dst = sys.argv[1], sys.argv[2]
try:
    fd = os.open(src, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
except OSError as exc:
    sys.stderr.write(f"ERROR: WireGuard config not found or is a symlink: {src} ({exc})\n")
    sys.exit(8)

try:
    st = os.fstat(fd)
    if not stat.S_ISREG(st.st_mode):
        sys.stderr.write(f"ERROR: WireGuard config must be a regular file: {src}\n")
        sys.exit(8)
    perm = stat.S_IMODE(st.st_mode)
    if perm not in (0o600, 0o400):
        sys.stderr.write(f"ERROR: WireGuard config {src} must have 0600 permissions (found {perm:o})\n")
        sys.exit(8)
    if st.st_size <= 0 or st.st_size > 16384:
        sys.stderr.write(f"ERROR: WireGuard config size out of bounds ({st.st_size} bytes)\n")
        sys.exit(8)
    raw_bytes = os.read(fd, 16385)
    if len(raw_bytes) > 16384 or b"\x00" in raw_bytes:
        sys.stderr.write("ERROR: Invalid binary or oversized WireGuard config\n")
        sys.exit(8)
finally:
    os.close(fd)

text = raw_bytes.decode("utf-8", errors="strict")
key_re = re.compile(r"^[A-Za-z0-9+/]{43}=\Z")
host_re = re.compile(
    r"^(?=.{1,253}\Z)[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
    r"(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*\Z"
)

ALLOWED_INTERFACE = {"privatekey", "address", "dns", "mtu"}
ALLOWED_PEER = {"publickey", "presharedkey", "endpoint", "allowedips", "persistentkeepalive"}
FORBIDDEN_HOOKS = {"preup", "postup", "predown", "postdown", "saveconfig", "table", "fwmark", "listenport"}

section = None
seen_sections = set()
iface = {}
peer = {}
vpn_port = "9735"
vpn_dns = ""

for raw_line in text.splitlines():
    line = raw_line.rstrip("\r")
    m_port = re.match(r"^\s*#\s*(?:VPNPort|Port Forwarding):\s*([0-9]{1,5})\s*\Z", line, re.IGNORECASE)
    if m_port:
        vpn_port = str(int(m_port.group(1)))
        continue
    m_srv = re.match(r"^\s*#\s*Server:\s*([A-Za-z0-9.-]+)\s*\Z", line, re.IGNORECASE)
    if m_srv:
        vpn_dns = m_srv.group(1)
        continue
    trimmed = line.strip()
    if not trimmed:
        continue
    if trimmed.lower().startswith("#tunnelsats-managed") or trimmed.lower().startswith("#tunnelsats-setup"):
        break
    if trimmed.startswith("#") or trimmed.startswith(";"):
        continue
    m_sec = re.match(r"^\[([A-Za-z0-9_-]+)\]\Z", trimmed)
    if m_sec:
        sec_name = m_sec.group(1).lower()
        if sec_name not in ("interface", "peer"):
            sys.stderr.write(f"ERROR: Unsupported WireGuard section [{m_sec.group(1)}]\n")
            sys.exit(8)
        if sec_name in seen_sections:
            sys.stderr.write(f"ERROR: Duplicate WireGuard section [{m_sec.group(1)}]\n")
            sys.exit(8)
        seen_sections.add(sec_name)
        section = sec_name
        continue
    if section is None or "=" not in trimmed:
        sys.stderr.write("ERROR: Malformed line or directive outside section in WireGuard config\n")
        sys.exit(8)
    raw_k, _, raw_v = trimmed.partition("=")
    k = raw_k.strip().lower()
    v = raw_v.split("#", 1)[0].strip()
    if k in FORBIDDEN_HOOKS:
        sys.stderr.write(f"ERROR: Forbidden WireGuard directive '{raw_k.strip()}' rejected\n")
        sys.exit(8)
    if section == "interface":
        if k not in ALLOWED_INTERFACE:
            sys.stderr.write(f"ERROR: Unsupported [Interface] directive '{raw_k.strip()}'\n")
            sys.exit(8)
        iface[k] = v
    elif section == "peer":
        if k not in ALLOWED_PEER:
            sys.stderr.write(f"ERROR: Unsupported [Peer] directive '{raw_k.strip()}'\n")
            sys.exit(8)
        peer[k] = v

if "interface" not in seen_sections or "peer" not in seen_sections:
    sys.stderr.write("ERROR: WireGuard config is missing [Interface] or [Peer] section\n")
    sys.exit(8)

priv = iface.get("privatekey", "")
pub = peer.get("publickey", "")
psk = peer.get("presharedkey", "")
if not key_re.fullmatch(priv) or not key_re.fullmatch(pub):
    sys.stderr.write("ERROR: WireGuard config requires valid 44-char base64 PrivateKey and PublicKey\n")
    sys.exit(8)
if psk and not key_re.fullmatch(psk):
    sys.stderr.write("ERROR: Invalid PresharedKey in WireGuard config\n")
    sys.exit(8)

raw_addr = iface.get("address", "")
if not raw_addr or "%" in raw_addr:
    sys.stderr.write("ERROR: WireGuard config has missing or invalid Address\n")
    sys.exit(8)
norm_addrs = []
for part in raw_addr.split(","):
    part = part.strip()
    if not part or "%" in part:
        sys.stderr.write("ERROR: Invalid Address entry in WireGuard config\n")
        sys.exit(8)
    try:
        ip_if = ipaddress.ip_interface(part)
    except ValueError:
        sys.stderr.write(f"ERROR: Invalid Address '{part}' in WireGuard config\n")
        sys.exit(8)
    if getattr(ip_if, "scope_id", None) is not None:
        sys.stderr.write("ERROR: IPv6 scope_id is forbidden in WireGuard Address\n")
        sys.exit(8)
    norm_addrs.append(str(ip_if))
addr_str = ", ".join(norm_addrs)

mtu_str = ""
if "mtu" in iface and iface["mtu"]:
    if not iface["mtu"].isdigit() or not (1280 <= int(iface["mtu"]) <= 1500):
        sys.stderr.write("ERROR: WireGuard MTU must be between 1280 and 1500\n")
        sys.exit(8)
    mtu_str = str(int(iface["mtu"]))

if "dns" in iface and iface["dns"]:
    for dpart in iface["dns"].split(","):
        dpart = dpart.strip()
        if not dpart or "%" in dpart:
            sys.stderr.write("ERROR: Invalid DNS entry in WireGuard config\n")
            sys.exit(8)
        try:
            ipaddress.ip_address(dpart)
        except ValueError:
            if not host_re.fullmatch(dpart):
                sys.stderr.write("ERROR: Invalid DNS entry in WireGuard config\n")
                sys.exit(8)

endpoint = peer.get("endpoint", "")
ep_host = ""
ep_port = 0
if endpoint.startswith("["):
    m_ep6 = re.fullmatch(r"\[([0-9a-fA-F:]+)\]:([0-9]{1,5})", endpoint)
    if not m_ep6:
        sys.stderr.write("ERROR: Invalid IPv6 Endpoint in WireGuard config\n")
        sys.exit(8)
    try:
        ipaddress.IPv6Address(m_ep6.group(1))
    except ValueError:
        sys.stderr.write("ERROR: Invalid IPv6 Endpoint in WireGuard config\n")
        sys.exit(8)
    ep_host = m_ep6.group(1)
    ep_port = int(m_ep6.group(2))
    endpoint_norm = f"[{ep_host}]:{ep_port}"
else:
    if endpoint.count(":") != 1:
        sys.stderr.write(f"ERROR: WireGuard config has invalid Endpoint '{endpoint}'\n")
        sys.exit(8)
    h_part, _, p_part = endpoint.partition(":")
    if not p_part.isdigit():
        sys.stderr.write("ERROR: Invalid Endpoint port in WireGuard config\n")
        sys.exit(8)
    ep_port = int(p_part)
    try:
        ipaddress.IPv4Address(h_part)
        ep_host = h_part
    except ValueError:
        if not host_re.fullmatch(h_part):
            sys.stderr.write(f"ERROR: Invalid Endpoint host '{h_part}'\n")
            sys.exit(8)
        ep_host = h_part
    endpoint_norm = f"{ep_host}:{ep_port}"

if not (1 <= ep_port <= 65535):
    sys.stderr.write("ERROR: Endpoint port out of range\n")
    sys.exit(8)

if not vpn_dns:
    vpn_dns = ep_host
if not host_re.fullmatch(vpn_dns):
    try:
        ipaddress.ip_address(vpn_dns)
    except ValueError:
        sys.stderr.write(f"ERROR: Extracted VPN host '{vpn_dns}' is invalid\n")
        sys.exit(8)

p_num = int(vpn_port)
if not (1 <= p_num <= 65535):
    sys.stderr.write(f"ERROR: Extracted VPN port '{vpn_port}' is invalid\n")
    sys.exit(8)

raw_allowed = peer.get("allowedips", "")
if not raw_allowed or "%" in raw_allowed:
    sys.stderr.write("ERROR: WireGuard config has missing or invalid AllowedIPs\n")
    sys.exit(8)
norm_allowed = []
has_v4_default = False
for npart in raw_allowed.split(","):
    npart = npart.strip()
    if not npart or "%" in npart:
        sys.stderr.write("ERROR: Invalid AllowedIPs entry\n")
        sys.exit(8)
    try:
        net = ipaddress.ip_network(npart, strict=False)
    except ValueError:
        sys.stderr.write(f"ERROR: Invalid AllowedIPs network '{npart}'\n")
        sys.exit(8)
    if str(net) == "0.0.0.0/0":
        has_v4_default = True
    norm_allowed.append(str(net))
if not has_v4_default:
    sys.stderr.write("ERROR: WireGuard config AllowedIPs must include 0.0.0.0/0\n")
    sys.exit(8)
allowed_str = ", ".join(norm_allowed)

keepalive = "25"
if "persistentkeepalive" in peer and peer["persistentkeepalive"]:
    ka = peer["persistentkeepalive"]
    if not ka.isdigit() or not (0 <= int(ka) <= 65535):
        sys.stderr.write("ERROR: Invalid PersistentKeepalive in WireGuard config\n")
        sys.exit(8)
    keepalive = str(int(ka))

canon_lines = [
    "[Interface]",
    f"PrivateKey = {priv}",
    f"Address = {addr_str}",
]
if mtu_str:
    canon_lines.append(f"MTU = {mtu_str}")
canon_lines += [
    f"# Server: {vpn_dns}",
    f"# Port Forwarding: {p_num}",
    "",
    "[Peer]",
    f"PublicKey = {pub}",
]
if psk:
    canon_lines.append(f"PresharedKey = {psk}")
canon_lines += [
    f"Endpoint = {endpoint_norm}",
    f"AllowedIPs = {allowed_str}",
    f"PersistentKeepalive = {keepalive}",
    "",
]

fd_out = os.open(dst, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, "O_NOFOLLOW", 0), 0o600)
with os.fdopen(fd_out, "w", encoding="utf-8") as f_out:
    f_out.write("\n".join(canon_lines))
os.chmod(dst, 0o600)

vals = {
    "EXTRACTED_VPN_DNS": vpn_dns,
    "EXTRACTED_VPN_PORT": str(p_num),
    "EXTRACTED_WG_PRIVKEY": priv,
    "EXTRACTED_WG_ADDRESS": addr_str,
    "EXTRACTED_WG_MTU": mtu_str,
    "EXTRACTED_WG_PUBKEY": pub,
    "EXTRACTED_WG_PSK": psk,
    "EXTRACTED_WG_ENDPOINT": endpoint_norm,
    "EXTRACTED_WG_ALLOWED_IPS": allowed_str,
    "EXTRACTED_WG_KEEPALIVE": keepalive,
}
for k, v in vals.items():
    print(f"{k}={shlex.quote(v)}")
PY
)"; then
        return 8
    fi
    eval "$parsed_env"
    return 0
}

render_managed_wg_conf() {
    local dst="$1"
    {
        printf '[Interface]\n'
        printf 'PrivateKey = %s\n' "$EXTRACTED_WG_PRIVKEY"
        printf 'Address = %s\n' "$EXTRACTED_WG_ADDRESS"
        if [ -n "$EXTRACTED_WG_MTU" ]; then
            printf 'MTU = %s\n' "$EXTRACTED_WG_MTU"
        fi
        printf '# Server: %s\n' "$EXTRACTED_VPN_DNS"
        printf '# Port Forwarding: %s\n\n' "$EXTRACTED_VPN_PORT"
        printf '[Peer]\n'
        printf 'PublicKey = %s\n' "$EXTRACTED_WG_PUBKEY"
        if [ -n "$EXTRACTED_WG_PSK" ]; then
            printf 'PresharedKey = %s\n' "$EXTRACTED_WG_PSK"
        fi
        printf 'Endpoint = %s\n' "$EXTRACTED_WG_ENDPOINT"
        printf 'AllowedIPs = %s\n' "$EXTRACTED_WG_ALLOWED_IPS"
        printf 'PersistentKeepalive = %s\n\n' "$EXTRACTED_WG_KEEPALIVE"
        cat <<'EOF'
#Tunnelsats-Managed (generated by tunnelsats.sh install --managed)
[Interface]
Table = off
FwMark = 0x2000000
PostUp = sysctl -q -w net.ipv4.conf.%i.src_valid_mark=1
PostUp = ip route replace default dev %i table 51820
PreDown = ip route del default dev %i table 51820 || true
EOF
    } > "$dst"
    chmod 0600 "$dst"
}

ensure_managed_inventory_readable() {
    if [ -f "$MANAGED_INVENTORY" ] && [ ! -L "$MANAGED_INVENTORY" ]; then
        chmod 0755 "$(dirname "$MANAGED_INVENTORY")" 2>/dev/null || true
        chmod 0644 "$MANAGED_INVENTORY" 2>/dev/null || true
    fi
}

lnd_config_and_slice_converged() {
    local expected_dns="$1"
    local expected_port="$2"

    if [ ! -f "$LND_MAIN_CONFIG" ] || [ -L "$LND_MAIN_CONFIG" ]; then
        return 1
    fi
    if ! grep -Eq '^[[:space:]]*listen=0\.0\.0\.0:9735[[:space:]]*$' "$LND_MAIN_CONFIG" 2>/dev/null; then
        return 1
    fi
    if ! grep -Fqx "externalhosts=${expected_dns}:${expected_port}" "$LND_MAIN_CONFIG" 2>/dev/null; then
        return 1
    fi
    if ! grep -Eq '^[[:space:]]*tor\.skip-proxy-for-clearnet-targets=(true|1)[[:space:]]*$' "$LND_MAIN_CONFIG" 2>/dev/null; then
        return 1
    fi
    if ! grep -Eq '^[[:space:]]*tor\.streamisolation=(false|0)[[:space:]]*$' "$LND_MAIN_CONFIG" 2>/dev/null; then
        return 1
    fi

    local props
    props="$("$SYSTEMCTL_BIN" show -p ControlGroup -p DropInPaths -p NeedDaemonReload lnd.service 2>/dev/null || echo "")"
    if [ -n "$props" ]; then
        if [[ "$props" != *"tunnelsats-managed.conf"* ]]; then
            return 1
        fi
        if [[ "$props" == *"NeedDaemonReload=yes"* ]]; then
            return 1
        fi
        if "$SYSTEMCTL_BIN" is-active --quiet lnd.service 2>/dev/null; then
            if [[ "$props" != *"/tunnelsats.slice/"* ]]; then
                return 1
            fi
        fi
    fi
    return 0
}

cmd_apply() {
    local req_id="${2:-}"
    refuse_if_secure_mode "apply" "$req_id"

    local conf_path="$TUNNELSATS_CONF_PATH"
    if [ "$(id -u)" -ne 0 ] && [ -n "${1:-}" ]; then
        conf_path="$1"
    fi

    local snap_conf
    snap_conf="$(alloc_stage_tmp)"
    if ! snapshot_and_validate_wg_conf "$conf_path" "$snap_conf"; then
        rm -f "$snap_conf"
        write_reconcile_status "error" "apply" "$req_id" "WireGuard configuration validation failed"
        return 8
    fi

    if [ -f "$MANAGED_INVENTORY" ] && [ ! -L "$MANAGED_INVENTORY" ] && grep -Eq '"state"[[:space:]]*:[[:space:]]*"installed"' "$MANAGED_INVENTORY" 2>/dev/null; then
        mkdir -p "$WG_DIR"
        chmod 0700 "$WG_DIR"
        local tmp_wg wg_changed=0
        tmp_wg="$(mktemp "${WG_CONF_DST}.tmp.XXXXXX")"
        render_managed_wg_conf "$tmp_wg"
        if [ ! -f "$WG_CONF_DST" ] || ! cmp -s "$tmp_wg" "$WG_CONF_DST"; then
            mv -f "$tmp_wg" "$WG_CONF_DST"
            wg_changed=1
        else
            rm -f "$tmp_wg"
        fi
        rm -f "$snap_conf"
        ensure_managed_inventory_readable

        if ! "$SYSTEMCTL_BIN" is-active --quiet tunnelsats-killswitch.service 2>/dev/null; then
            if ! "$SYSTEMCTL_BIN" restart tunnelsats-killswitch.service; then
                write_reconcile_status "error" "apply" "$req_id" "tunnelsats-killswitch.service failed to start"
                return 1
            fi
        fi

        if [ "$wg_changed" -eq 1 ] || ! "$SYSTEMCTL_BIN" is-active --quiet wg-quick@tunnelsatsv2.service 2>/dev/null; then
            if ! "$SYSTEMCTL_BIN" restart wg-quick@tunnelsatsv2.service; then
                write_reconcile_status "error" "apply" "$req_id" "wg-quick@tunnelsatsv2.service failed to start"
                return 1
            fi
        fi

        block_insert "$EXTRACTED_VPN_DNS" "$EXTRACTED_VPN_PORT"
        if [ "$BLOCK_CHANGED" -eq 1 ] || ! lnd_config_and_slice_converged "$EXTRACTED_VPN_DNS" "$EXTRACTED_VPN_PORT"; then
            if [ -x "$MYNODE_GEN_LND_CONFIG" ]; then
                "$MYNODE_GEN_LND_CONFIG" || true
            fi
            if "$SYSTEMCTL_BIN" is-active --quiet lnd.service 2>/dev/null; then
                if ! "$SYSTEMCTL_BIN" restart lnd.service; then
                    write_reconcile_status "error" "apply" "$req_id" "lnd.service failed to restart"
                    return 1
                fi
            fi
        fi
    else
        local ts_bin
        ts_bin="$(resolve_ts_sh_bin)"
        # Arm tunnelsats.slice + killswitch FIRST before writing hybrid clearnet settings to lnd_extra_config.conf
        if ! "$ts_bin" install --managed mynode --impl "$TUNNELSATS_LN_IMPL" --non-interactive --yes --config "$snap_conf"; then
            rm -f "$snap_conf"
            write_reconcile_status "error" "apply" "$req_id" "tunnelsats managed install failed"
            exit 1
        fi
        rm -f "$snap_conf"
        ensure_managed_inventory_readable

        block_insert "$EXTRACTED_VPN_DNS" "$EXTRACTED_VPN_PORT"
        if [ -x "$MYNODE_GEN_LND_CONFIG" ]; then
            "$MYNODE_GEN_LND_CONFIG" || true
        fi
        if "$SYSTEMCTL_BIN" is-active --quiet lnd.service 2>/dev/null; then
            if ! "$SYSTEMCTL_BIN" restart lnd.service; then
                write_reconcile_status "error" "apply" "$req_id" "lnd.service failed to restart"
                return 1
            fi
        fi
    fi

    rm -f "$SUDOERS_LEGACY_FILE" 2>/dev/null || true
    write_reconcile_status "ok" "apply" "$req_id" ""
    python3 - "$EXTRACTED_VPN_DNS" "$EXTRACTED_VPN_PORT" "$LND_EXTRA_CONFIG" <<'PY'
import json, sys
print(json.dumps({
    "status": "applied",
    "vpn_dns": sys.argv[1],
    "vpn_port": int(sys.argv[2]),
    "lnd_extra_config": sys.argv[3],
}, separators=(",", ":")))
PY
}

cmd_restore_internal() {
    local mode="$1"
    local req_id="${2:-}"
    local ts_bin=""
    ts_bin="$(resolve_ts_sh_bin 2>/dev/null || echo "")"

    # 1. Remove the hybrid clearnet block from lnd_extra_config.conf FIRST so lnd.conf is clean Tor-only
    block_remove
    local extra_was_changed="$BLOCK_CHANGED"

    if [ "$extra_was_changed" -eq 1 ]; then
        if [ -x "$MYNODE_GEN_LND_CONFIG" ]; then
            "$MYNODE_GEN_LND_CONFIG" || true
        elif [ -f "$LND_MAIN_CONFIG" ] && [ ! -L "$LND_MAIN_CONFIG" ]; then
            local stage_lnd
            stage_lnd="$(alloc_stage_tmp)"
            awk '
                BEGIN { in_block = 0 }
                /^[[:space:]]*#[[:space:]]*BEGIN TUNNELSATS[[:space:]]*$/ { in_block = 1; next }
                /^[[:space:]]*#[[:space:]]*END TUNNELSATS[[:space:]]*$/ { in_block = 0; next }
                !in_block { print }
            ' "$LND_MAIN_CONFIG" > "$stage_lnd"
            write_bitcoin_owned_file "$LND_MAIN_CONFIG" "$stage_lnd" "0644" || true
            rm -f "$stage_lnd"
        fi
    fi

    # 2. Remove the managed dataplane (exit code 3 = not installed)
    local rc=3
    if [ -n "$ts_bin" ] && [ -f "$ts_bin" ] && [ ! -L "$ts_bin" ]; then
        rc=0
        bash "$ts_bin" uninstall --managed --non-interactive --yes || rc=$?
        if [ "$rc" -ne 0 ] && [ "$rc" -ne 3 ]; then
            write_reconcile_status "error" "$mode" "$req_id" "tunnelsats uninstall exited with code ${rc}"
            echo "ERROR: tunnelsats uninstall --managed exited with code ${rc}" >&2
            exit "$rc"
        fi
    fi

    # 3. Only restart lnd.service if tunnelsats.sh did not already restart it (rc == 3) AND lnd_extra_config changed
    if [ "$rc" -eq 3 ] && [ "$extra_was_changed" -eq 1 ]; then
        if "$SYSTEMCTL_BIN" is-active --quiet lnd.service 2>/dev/null; then
            "$SYSTEMCTL_BIN" restart lnd.service || true
        fi
    fi

    rm -f "$SUDOERS_LEGACY_FILE" 2>/dev/null || true

    if [ "$mode" = "uninstall" ]; then
        rm -f "$RECONCILE_SBIN" /usr/local/sbin/tunnelsats /opt/mynode/ts-mynode 2>/dev/null || true
        write_reconcile_status "ok" "uninstall" "$req_id" ""
        python3 - "$LND_EXTRA_CONFIG" <<'PY'
import json, sys
print(json.dumps({"status": "uninstalled", "lnd_extra_config": sys.argv[1]}, separators=(",", ":")))
PY
    else
        write_reconcile_status "ok" "restore" "$req_id" ""
        python3 - "$LND_EXTRA_CONFIG" <<'PY'
import json, sys
print(json.dumps({"status": "restored", "lnd_extra_config": sys.argv[1]}, separators=(",", ":")))
PY
    fi
}

cmd_status() {
    local secure_str="false"
    if is_secure_mode; then
        secure_str="true"
    fi
    local managed_str="false"
    if [ -f "$MANAGED_INVENTORY" ] && [ ! -L "$MANAGED_INVENTORY" ] && grep -Eq '"state"[[:space:]]*:[[:space:]]*"installed"' "$MANAGED_INVENTORY" 2>/dev/null; then
        managed_str="true"
    fi
    local blk_json
    blk_json="$(block_status)"
    local ts_bin=""
    ts_bin="$(resolve_ts_sh_bin 2>/dev/null || echo "")"
    local verify_json="null"
    if [ -n "$ts_bin" ] && [ -f "$ts_bin" ] && [ ! -L "$ts_bin" ]; then
        verify_json="$(bash "$ts_bin" verify --no-probe --json 2>/dev/null || echo "null")"
        if [ -z "$verify_json" ] || [[ "$verify_json" != \{* ]]; then
            verify_json="null"
        fi
    fi
    printf '{"secure_mode":%s,"managed_installed":%s,"lnd_extra_config":%s,"dataplane":%s}\n' \
        "$secure_str" "$managed_str" "$blk_json" "$verify_json"
}

read_desired_state() {
    python3 - "$DESIRED_STATE_FILE" "$TUNNELSATS_APP_CONFIG" "$TUNNELSATS_CONF_PATH" <<'PY' 2>/dev/null || echo "none|"
import json, os, stat, sys
desired_path, app_cfg_path, conf_path = sys.argv[1:4]

def safe_read_json(p):
    try:
        fd = os.open(p, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
    except OSError:
        return None
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_size <= 0 or st.st_size > 65536:
            return None
        return json.loads(os.read(fd, 65536).decode("utf-8"))
    except Exception:
        return None
    finally:
        os.close(fd)

doc = safe_read_json(desired_path)
if isinstance(doc, dict) and doc.get("desired") in ("active", "tor-only"):
    req = doc.get("requestId")
    req_s = req if isinstance(req, str) and len(req) <= 64 and req.isalnum() else ""
    print(f"{doc['desired']}|{req_s}")
    sys.exit(0)

cfg = safe_read_json(app_cfg_path)
if isinstance(cfg, dict) and cfg.get("enabled") is False:
    print("tor-only|")
    sys.exit(0)

if os.path.isfile(conf_path) and not os.path.islink(conf_path):
    print("active|")
else:
    print("none|")
PY
}

cmd_sync() {
    if is_secure_mode; then
        write_reconcile_status "blocked_secure_mode" "sync" "" "SECURE_MODE is enabled"
        return 0
    fi
    local state_pair desired req_id
    state_pair="$(read_desired_state)"
    desired="${state_pair%%|*}"
    req_id="${state_pair#*|}"
    case "$desired" in
        active)
            if [ -f "$TUNNELSATS_CONF_PATH" ] && [ ! -L "$TUNNELSATS_CONF_PATH" ]; then
                cmd_apply "" "$req_id" >/dev/null
            fi
            ;;
        tor-only)
            local has_managed=0 has_block=0
            if [ -f "$MANAGED_INVENTORY" ] && [ ! -L "$MANAGED_INVENTORY" ]; then
                has_managed=1
            fi
            if [ -f "$LND_EXTRA_CONFIG" ] && [ ! -L "$LND_EXTRA_CONFIG" ] && grep -Eq '^[[:space:]]*#[[:space:]]*BEGIN TUNNELSATS[[:space:]]*$' "$LND_EXTRA_CONFIG" 2>/dev/null; then
                has_block=1
            fi
            if [ "$has_managed" -eq 1 ] || [ "$has_block" -eq 1 ]; then
                cmd_restore_internal "restore" "$req_id" >/dev/null
            else
                write_reconcile_status "ok" "restore" "$req_id" ""
            fi
            ;;
        *)
            write_reconcile_status "idle" "sync" "$req_id" ""
            ;;
    esac
}

cmd_enable_secure_mode() {
    mkdir -p "$(dirname "$SECURE_MODE_FILE")"
    if [ "$(id -u)" -eq 0 ]; then
        chmod 0755 "$(dirname "$SECURE_MODE_FILE")" 2>/dev/null || true
    fi
    local tmp
    tmp="$(mktemp "${SECURE_MODE_FILE}.tmp.XXXXXX")"
    printf 'true\n' > "$tmp"
    chmod 0644 "$tmp"
    mv -f "$tmp" "$SECURE_MODE_FILE"
    rm -f "$SUDOERS_LEGACY_FILE" 2>/dev/null || true
    if "$SYSTEMCTL_BIN" list-unit-files tunnelsats-reconcile.path >/dev/null 2>&1; then
        "$SYSTEMCTL_BIN" disable --now tunnelsats-reconcile.path 2>/dev/null || true
    fi
    write_reconcile_status "secure_mode_enabled" "enable-secure-mode" "" ""
    printf '{"status":"secure_mode_enabled","secure_mode":true}\n'
}

cmd_disable_secure_mode() {
    rm -f "$SECURE_MODE_FILE" "$SUDOERS_LEGACY_FILE" 2>/dev/null || true
    write_reconcile_status "secure_mode_disabled" "disable-secure-mode" "" ""
    printf '{"status":"secure_mode_disabled","secure_mode":false}\n'
}

run_with_lock() {
    local lock_dir
    lock_dir="$(dirname "$RECONCILE_LOCK_FILE")"
    mkdir -p "$lock_dir" 2>/dev/null || true
    if command -v flock >/dev/null 2>&1; then
        exec 9>"$RECONCILE_LOCK_FILE"
        if ! flock -w 30 9; then
            echo "ERROR: Another TunnelSats reconciler operation is already in progress." >&2
            exit 9
        fi
    fi
    "$@"
}

SUBCOMMAND="${1:-}"
case "$SUBCOMMAND" in
    block-insert)
        refuse_if_secure_mode "block-insert"
        block_insert "${2:-}" "${3:-}"
        ;;
    block-remove)
        refuse_if_secure_mode "block-remove"
        block_remove
        ;;
    block-status)
        block_status
        ;;
    apply)
        run_with_lock cmd_apply "${2:-}"
        ;;
    restore)
        refuse_if_secure_mode "restore"
        run_with_lock cmd_restore_internal "restore"
        ;;
    uninstall)
        run_with_lock cmd_restore_internal "uninstall"
        ;;
    status)
        cmd_status
        ;;
    sync|boot-sync)
        run_with_lock cmd_sync
        ;;
    enable-secure-mode)
        run_with_lock cmd_enable_secure_mode
        ;;
    disable-secure-mode)
        run_with_lock cmd_disable_secure_mode
        ;;
    *)
        echo "Usage: $0 {apply|restore|uninstall|status|sync|boot-sync|enable-secure-mode|disable-secure-mode|block-insert <dns> <port>|block-remove|block-status}" >&2
        exit 2
        ;;
esac
