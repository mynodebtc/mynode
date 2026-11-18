#!/bin/bash
# TunnelSats Unified Setup Tool - [Verification Entry]
# Consolidates install, pre-check, uninstall, and status commands
#
# Usage: sudo bash tunnelsats.sh [command] [options]

set -e  # Exit on error

# ---------------------------------------------------------------------------
# GLOBAL VARIABLES
# ---------------------------------------------------------------------------

VERSION="3.2"
# Version of the machine-readable CLI contract (--json documents, exit codes, error codes).
# Bumped only for incompatible changes; platforms such as RaspiBlitz pin it.
TS_CONTRACT=1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS_SCRIPT_PATH="${SCRIPT_DIR}/${BASH_SOURCE[0]##*/}"
CONFIG_FILE=""
PLATFORM=""
LN_IMPL=""
node_user=""
restarted_systemd_service=""
stopped_docker_containers=""
stopped_wireguard_interface=""
# Lightning daemon container selected by setup_docker_network to own the tunnel IP (may be stopped)
tunnel_target_container=""
WG_CONFIG_BACKUP=""

# Command line state (set by ts_parse_cli)
TS_COMMAND=""
TS_JSON=0
TS_NONINTERACTIVE=0
TS_OPT_YES=0
TS_OPT_PLATFORM=""
TS_OPT_IMPL=""
TS_OPT_PACKAGES=""
# Managed mode: --managed [profile], --uid-backstop (install), --no-probe (verify)
TS_OPT_MANAGED=0
TS_OPT_PROFILE=""
TS_OPT_UID_BACKSTOP=0
TS_OPT_NO_PROBE=0
# managed-arm --fallback-uid <uid>: the Lightning uid, from the kill switch unit's ExecStart
TS_OPT_FALLBACK_UID=""
# install --managed raspiblitz --network <chain>: the chain of the Lightning instance (default mainnet)
TS_OPT_NETWORK=""
TS_OPT_KEEP_CONFIG=0
TS_OPT_LEGACY_ARTIFACTS=0
TS_WANT_HELP=0
TS_USAGE_ERROR=""
TS_OPTS_GIVEN=()
TS_ARGV=()
# Identifiers accepted by --platform and --impl (the values used internally for PLATFORM and LN_IMPL)
TS_PLATFORMS="raspiblitz umbrel mynode baremetal"
TS_IMPLS="lnd cln lit"
# Values accepted by --network
TS_NETWORKS="mainnet testnet signet"
# JSON output: the document goes to TS_OUT_FD (the original stdout, saved before logs move to stderr)
TS_OUT_FD=1
TS_JSON_EMITTED=0

# Injection points for external commands and for the filesystem root of detection reads.
# Defaults are the plain command names and the real root; tests point them at stubs and fixture trees.
WG_BIN="${WG_BIN:-wg}"
WG_QUICK_BIN="${WG_QUICK_BIN:-wg-quick}"
NFT_BIN="${NFT_BIN:-nft}"
IP_BIN="${IP_BIN:-ip}"
SYSTEMCTL_BIN="${SYSTEMCTL_BIN:-systemctl}"
SYSTEMD_RUN_BIN="${SYSTEMD_RUN_BIN:-systemd-run}"
GETENT_BIN="${GETENT_BIN:-getent}"
CURL_BIN="${CURL_BIN:-curl}"
UNSHARE_BIN="${UNSHARE_BIN:-unshare}"
PERL_BIN="${PERL_BIN:-perl}"
# uninstall: lncli (empty: the lncli next to the Lightning unit's daemon, else lncli on the PATH) and
# runuser, which runs it as the node user
LNCLI_BIN="${LNCLI_BIN:-}"
RUNUSER_BIN="${RUNUSER_BIN:-runuser}"
TS_FS_ROOT="${TS_FS_ROOT:-}"

# Shared Lightning daemon container resolvers (used by the installer and the generated network monitor)
LND_CONTAINER_REGEX='(^|[[:space:]]|[-_])(lightning[-_])?lnd([-._]lnd)?([-._][0-9]+)?$'
CLN_CONTAINER_REGEX='(core-lightning.*lightningd|lightning.*cln|lightningd|(^|[[:space:]])(core-lightning|clightning)([-._][0-9]+)?$)'
LN_CONTAINER_EXCLUDE_REGEX='[-_](app|web|ui)([-_]|$)'
TUNNEL_CONTAINER_IP="10.9.9.9"
# Prints "attached <static-ip> <live-ip>" when attached to docker-tunnelsats, empty otherwise.
# Static IPAM config is included because stopped containers report an empty live IPAddress.
TUNNEL_NET_INSPECT_FMT='{{with index .NetworkSettings.Networks "docker-tunnelsats"}}attached {{if .IPAMConfig}}{{.IPAMConfig.IPv4Address}}{{end}} {{.IPAddress}}{{end}}'

# ---------------------------------------------------------------------------
# COLOR & FORMATTING FUNCTIONS
# ---------------------------------------------------------------------------

# ANSI Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color


print_line() {
    local char="${1:-━}"
    local count="${2:-42}"
    printf "%0.s${char}" $(seq 1 $count)
    echo ""
}

print_header() {
    local subtitle="$1"
    local title="Tunnel⚡Sats Setup Tool v${VERSION}"
    local width=42
    
    # Calculate visible length (⚡ counts as 2 columns but 1 character)
    local title_len=${#title}
    if [[ "$title" == *"⚡"* ]]; then
        title_len=$((title_len + 1))
    fi
    
    local title_padding=$(( (width - title_len) / 2 ))
    local sub_padding=$(( (width - ${#subtitle}) / 2 ))
    
    echo -e "${BOLD}${BLUE}"
    printf "╔"; printf '═%.0s' $(seq 1 $width); echo "╗"
printf "║%*s%s%*s║\n" "$title_padding" "" "$title" $((width - title_padding - title_len)) ""
printf "║%*s%s%*s║\n" "$sub_padding" "" "$subtitle" $((width - sub_padding - ${#subtitle})) ""
    printf "╚"; printf '═%.0s' $(seq 1 $width); echo "╝"
    echo -e "${NC}"
}



print_success() {
    echo -e "${GREEN}✓${NC} $1" >&2
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠${NC}  $1" >&2
}

print_info() {
    echo -e "${BLUE}→${NC} $1" >&2
}

print_step() {
    echo -e "${BOLD}[$1/$2]${NC} $3" >&2
}

# No ANSI colours when NO_COLOR is set (https://no-color.org), in --json mode, or when stdout or
# stderr is not a terminal. Called once by parse_args before anything is printed.
ts_init_colors() {
    if [[ -n "${NO_COLOR:-}" ]] || [[ "$TS_JSON" -eq 1 ]] || [[ ! -t 1 ]] || [[ ! -t 2 ]]; then
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        BOLD=''
        NC=''
    fi
}

# ---------------------------------------------------------------------------
# CLI CONTRACT 1: NON-INTERACTIVE MODE, JSON OUTPUT AND ERROR CODES
# --json prints exactly one JSON document on stdout; every human log goes to stderr.
# Exit codes: 0 success, 1 failure, 2 usage error or interaction required.
# Error codes: E_USAGE, E_JSON_UNSUPPORTED, E_INTERACTION_REQUIRED (exit 2),
#              E_SHA256_UNAVAILABLE, E_INTERNAL (exit 1).
# ---------------------------------------------------------------------------

# Prints a UTF-8 locale bash can switch to (C.UTF-8 on Debian 12), or C if none is available.
ts_json_utf8_locale() {
    local loc
    for loc in C.UTF-8 C.utf8 en_US.UTF-8; do
        if ( LC_ALL="$loc"; s=$'\xc3\xa4'; [[ ${#s} -eq 1 ]] ) 2>/dev/null; then
            echo "$loc"
            return 0
        fi
    done
    echo "C"
}

# Stores the byte length of $1 in TS_BYTE_LEN (no subshell).
ts_byte_len() {
    local LC_ALL=C
    TS_BYTE_LEN=${#1}
}

# Multibyte UTF-8 forms allowed by RFC 3629: no overlong forms, no surrogates, nothing above
# U+10FFFF. Matched byte-wise (C locale), because glibc groups some invalid sequences, for example
# F4 90 80 80 (above U+10FFFF), into one character.
TS_UTF8_MULTIBYTE_RE=$'^([\xc2-\xdf][\x80-\xbf]|\xe0[\xa0-\xbf][\x80-\xbf]|[\xe1-\xec\xee\xef][\x80-\xbf][\x80-\xbf]|\xed[\x80-\x9f][\x80-\xbf]|\xf0[\x90-\xbf][\x80-\xbf][\x80-\xbf]|[\xf1-\xf3][\x80-\xbf][\x80-\xbf][\x80-\xbf]|\xf4[\x80-\x8f][\x80-\xbf][\x80-\xbf])$'

# Succeeds if $1 is exactly one valid multibyte UTF-8 character.
ts_utf8_valid_multibyte() {
    local LC_ALL=C
    [[ "$1" =~ $TS_UTF8_MULTIBYTE_RE ]]
}

# Succeeds if $1 is printable ASCII without quote or backslash (needs no escaping at all).
ts_json_plain_ascii() {
    local LC_ALL=C
    [[ "$1" != *[![:print:]]* ]] && [[ "$1" != *[\"\\]* ]]
}

# Escapes $1 for use inside a JSON string literal and stores the result in TS_JSON_ESCAPED.
# Works character-wise in a UTF-8 locale: quote and backslash are escaped, control characters
# become \b \f \n \r \t or \u00XX, valid UTF-8 characters (checked byte-wise against RFC 3629) pass
# through unchanged (JSON allows raw UTF-8), and every byte that is not part of a valid UTF-8
# character becomes \ufffd, so the document is always valid JSON, even for hostile input. Without a
# UTF-8 locale every non-ASCII byte becomes \ufffd (pure ASCII output). Needs no external tool.
ts_json_escape() {
    local s="$1" out="" ch code i b
    if ts_json_plain_ascii "$s"; then
        TS_JSON_ESCAPED="$s"
        return 0
    fi
    local LC_ALL
    case "${TS_JSON_LOCALE:-}" in
        C|C.UTF-8|C.utf8|en_US.UTF-8) ;;
        *) TS_JSON_LOCALE=$(ts_json_utf8_locale) ;;
    esac
    LC_ALL="$TS_JSON_LOCALE"
    for ((i = 0; i < ${#s}; i++)); do
        ch="${s:i:1}"
        case "$ch" in
            '"') out+='\"' ;;
            '\') out+='\\' ;;
            $'\n') out+='\n' ;;
            $'\r') out+='\r' ;;
            $'\t') out+='\t' ;;
            $'\b') out+='\b' ;;
            $'\f') out+='\f' ;;
            *)
                ts_byte_len "$ch"
                if [[ "$TS_BYTE_LEN" -gt 1 ]]; then
                    if ts_utf8_valid_multibyte "$ch"; then
                        out+="$ch"
                    else
                        # An invalid sequence the locale grouped into one character: every byte
                        # is replaced, as for any other invalid byte
                        for ((b = 0; b < TS_BYTE_LEN; b++)); do
                            out+='\ufffd'
                        done
                    fi
                elif [[ "$ch" == [[:print:]] ]]; then
                    out+="$ch"
                elif [[ "$ch" == [[:cntrl:]] ]]; then
                    printf -v code '%04x' "'$ch"
                    out+="\\u${code}"
                else
                    out+='\ufffd'
                fi
                ;;
        esac
    done
    TS_JSON_ESCAPED="$out"
}

# JSON value builders. Each one stores a JSON literal in TS_R (no subshells).
ts_j_str() {
    ts_json_escape "$1"
    TS_R="\"${TS_JSON_ESCAPED}\""
}

ts_j_str_or_null() {
    if [[ -n "$1" ]]; then
        ts_j_str "$1"
    else
        TS_R="null"
    fi
}

ts_j_int_or_null() {
    if [[ "$1" =~ ^[0-9]{1,15}$ ]]; then
        TS_R="$((10#$1))"
    else
        TS_R="null"
    fi
}

ts_j_bool_or_null() {
    case "$1" in
        true|1) TS_R="true" ;;
        false|0) TS_R="false" ;;
        *) TS_R="null" ;;
    esac
}

# Array of JSON literals: ts_j_arr "$lit1" "$lit2" ...
ts_j_arr() {
    local IFS=","
    TS_R="[$*]"
}

# Object from pairs "<type>:<key>" "<value>". Types: s string, sn string (null if empty),
# i integer (null if not a number), b boolean (null if unknown), r raw JSON literal.
ts_j_obj() {
    local out="" sep="" spec val
    while [[ $# -ge 2 ]]; do
        spec="$1"
        val="$2"
        shift 2
        case "${spec%%:*}" in
            s) ts_j_str "$val" ;;
            sn) ts_j_str_or_null "$val" ;;
            i) ts_j_int_or_null "$val" ;;
            b) ts_j_bool_or_null "$val" ;;
            *) TS_R="$val" ;;
        esac
        out+="${sep}\"${spec#*:}\":${TS_R}"
        sep=","
    done
    TS_R="{${out}}"
}

# Error object: $1 = code, $2 = class, $3 = message, $4 = optional flag that answers a prompt.
ts_j_error() {
    if [[ -n "${4:-}" ]]; then
        ts_j_obj s:code "$1" s:class "$2" s:message "$3" s:flag "$4"
    else
        ts_j_obj s:code "$1" s:class "$2" s:message "$3"
    fi
}

# Prints the contract-1 document: $1 = exit code, $2 = errors array literal, $3 = extra members
# (raw '"key":value' pairs, may be empty). Must run in the main shell: a document printed from a
# subshell is not recorded, and the exit guard would then print a second one.
ts_json_document() {
    local rc="$1" errors="${2:-[]}" extra="${3:-}" ok="false" cmd ver doc
    if [[ "$rc" -eq 0 ]]; then
        ok="true"
    fi
    ts_j_str_or_null "$TS_COMMAND"
    cmd="$TS_R"
    ts_j_str "$VERSION"
    ver="$TS_R"
    doc="{\"contract\":${TS_CONTRACT},\"command\":${cmd},\"tool_version\":${ver},\"ok\":${ok},\"exit_code\":${rc},\"errors\":${errors}"
    if [[ -n "$extra" ]]; then
        doc+=",${extra}"
    fi
    doc+="}"
    printf '%s\n' "$doc" >&"$TS_OUT_FD"
    TS_JSON_EMITTED=1
}

# EXIT trap in --json mode: guarantees exactly one document even if a command aborts early.
ts_json_exit_guard() {
    local rc=$?
    trap - EXIT
    if [[ "$TS_JSON_EMITTED" -ne 1 ]]; then
        if [[ "$rc" -eq 0 ]]; then
            rc=1
        fi
        ts_j_error E_INTERNAL internal "'${TS_COMMAND}' ended without a result (exit code ${rc})"
        ts_json_document "$rc" "[${TS_R}]"
    fi
    exit "$rc"
}

# Reports an error on stderr (and as the JSON document in --json mode) and exits.
# $1 = exit code, $2 = error code, $3 = class, $4 = message, $5 = optional flag, $6 = optional hint.
ts_fail() {
    local rc="$1" code="$2" class="$3" message="$4" flag="${5:-}" hint="${6:-}" shown
    # print_error uses echo -e: neutralise backslashes and control characters from user input
    shown="${message//\\/\\\\}"
    shown="${shown//[[:cntrl:]]/?}"
    print_error "${shown} [${code}]"
    if [[ -n "$hint" ]]; then
        echo "$hint" >&2
    fi
    if [[ "$TS_JSON" -eq 1 ]]; then
        ts_j_error "$code" "$class" "$message" "$flag"
        ts_json_document "$rc" "[${TS_R}]"
    fi
    exit "$rc"
}

ts_usage_error() {
    ts_fail 2 E_USAGE usage "$1" "" "Run 'tunnelsats.sh help' for usage."
}

# Fails with E_INTERACTION_REQUIRED (exit 2): $1 = flag (with a value placeholder) that answers
# the prompt, $2 = prompt text, $3 = optional reason.
ts_interaction_required() {
    local flag="$1" prompt="$2" reason="${3:-non-interactive mode never prompts}"
    while [[ "$prompt" == *[[:space:]] ]]; do
        prompt="${prompt%?}"
    done
    ts_fail 2 E_INTERACTION_REQUIRED interaction "Cannot answer \"${prompt}\": ${reason}. Pass ${flag}." "${flag%% *}"
}

# Fails in non-interactive mode before a selection menu is printed. $1 = flag, $2 = prompt.
ts_require_interaction() {
    if [[ "$TS_NONINTERACTIVE" -eq 1 ]]; then
        ts_interaction_required "$1" "$2"
    fi
    return 0
}

# Reads the answer to an interactive prompt into the variable named $1.
#   $2 = flag that answers the prompt without interaction (named in the error)
#   $3 = prompt, shown exactly as before (read -p shows it only when stdin is a terminal)
#   $4 = optional answer to use at end of input. Without it, end of input fails like a missing
#        answer in non-interactive mode instead of silently aborting through set -e.
# Non-interactive mode never reads: it fails with E_INTERACTION_REQUIRED (exit 2).
# Piped answers keep working: a non-TTY stdin does not imply non-interactive mode.
ts_ask() {
    local __ts_var="$1" __ts_flag="$2" __ts_prompt="$3" __ts_reply=""
    ts_require_interaction "$__ts_flag" "$__ts_prompt"
    if ! read -r -p "$__ts_prompt" __ts_reply && [[ -z "$__ts_reply" ]]; then
        if [[ $# -ge 4 ]]; then
            print_warning "No answer received (end of input); using '${4}'"
            __ts_reply="$4"
        else
            ts_interaction_required "$__ts_flag" "$__ts_prompt" "no answer received (end of input)"
        fi
    fi
    printf -v "$__ts_var" '%s' "$__ts_reply"
}

# Yes/no confirmation answered by --yes: sets the variable named $1 to "y" when --yes was given,
# otherwise asks $2 like ts_ask (and fails in non-interactive mode).
ts_confirm() {
    if [[ "$TS_OPT_YES" -eq 1 ]]; then
        printf -v "$1" '%s' "y"
        return 0
    fi
    ts_ask "$1" "--yes" "$2"
}

# Succeeds if word $1 is in the space-separated list $2.
ts_in_list() {
    local item
    # $2 is split into words on purpose
    # shellcheck disable=SC2086
    for item in $2; do
        if [[ "$item" == "$1" ]]; then
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# NODE CONFIGURATION INSTRUCTIONS HELPER
# Used by cmd_install (post-install) and cmd_status (troubleshooting)
# ---------------------------------------------------------------------------

print_node_config_instructions() {
    local vpn_dns="$1"
    local vpn_port="$2"
    local context="${3:-install}"  # 'install' or 'status'
    
    if [[ "$LN_IMPL" == "lnd" ]]; then
        if [[ "$PLATFORM" == "umbrel" ]]; then
             echo -e "Edit: ${BOLD}${BLUE}~/umbrel/app-data/lightning/data/lnd/lnd.conf${NC}"
             if [[ "$context" == "install" ]]; then
                 echo -e "${YELLOW}Note: If 'tor.streamisolation' or 'tor.skip-proxy...' are already enabled in UI,${NC}"
                 echo -e "${YELLOW}      do NOT duplicate them.${NC}"
             fi
             echo ""
             echo "#########################################"
             echo -e "${BOLD}${BLUE}[Application Options]${NC}"
             echo -e "${YELLOW}externalhosts=${vpn_dns}:${vpn_port}${NC}"
             echo ""
             echo -e "${BOLD}${BLUE}[Tor]${NC}"
             echo -e "${YELLOW}tor.streamisolation=false${NC}"
             echo -e "${YELLOW}tor.skip-proxy-for-clearnet-targets=true${NC}"
             echo "#########################################"
        else
             local lnd_user="${node_user:-bitcoin}"
             local lnd_path="/home/$lnd_user/.lnd/lnd.conf"
             
             # Forensic path guessing for Bare Metal
             [[ ! -f "$lnd_path" ]] && [[ -f "/home/bitcoin/.lnd/lnd.conf" ]] && lnd_path="/home/bitcoin/.lnd/lnd.conf"
             [[ ! -f "$lnd_path" ]] && [[ -f "/home/lnd/.lnd/lnd.conf" ]] && lnd_path="/home/lnd/.lnd/lnd.conf"
             [[ ! -f "$lnd_path" ]] && [[ -f "/data/lnd/lnd.conf" ]] && lnd_path="/data/lnd/lnd.conf"
             [[ ! -f "$lnd_path" ]] && [[ -f "/mnt/hdd/lnd/lnd.conf" ]] && lnd_path="/mnt/hdd/lnd/lnd.conf"
             [[ "$PLATFORM" == "mynode" ]] && lnd_path="/mnt/hdd/mynode/settings/lnd_extra_config.conf"
             # The managed raspiblitz install knows the file the unit reads (TS_NODE_CONF_FILE)
             [[ -n "${TS_NODE_CONF_FILE:-}" ]] && lnd_path="$TS_NODE_CONF_FILE"
             
             echo -e "Edit: ${BOLD}${BLUE}sudo nano $lnd_path${NC}"
             if [[ "$PLATFORM" == "mynode" ]]; then
                 echo -e "${YELLOW}Note: MyNode regenerates /mnt/hdd/mynode/lnd/lnd.conf on restart from${NC}"
                 echo -e "${YELLOW}      /mnt/hdd/mynode/settings/lnd_extra_config.conf (also editable in the${NC}"
                 echo -e "${YELLOW}      MyNode Web GUI under LND -> Config -> Additional LND Config).${NC}"
             fi
             if [[ "$context" == "install" ]]; then
                 echo -e "${YELLOW}Note: Place settings in their respective sections. Do NOT duplicate categories.${NC}"
             fi
             echo ""
             echo "#########################################"
             echo -e "${BOLD}${BLUE}[Application Options]${NC}"
             echo -e "${YELLOW}listen=0.0.0.0:9735${NC}"
             echo -e "${YELLOW}externalhosts=${vpn_dns}:${vpn_port}${NC}"
             echo ""
             echo -e "${BOLD}${BLUE}[Tor]${NC}"
             echo -e "${YELLOW}tor.streamisolation=false${NC}"
             echo -e "${YELLOW}tor.skip-proxy-for-clearnet-targets=true${NC}"
             echo "#########################################"
        fi
        
    elif [[ "$LN_IMPL" == "cln" ]]; then
        if [[ "$PLATFORM" == "umbrel" ]]; then
             echo -e "1. Edit: ${BOLD}${BLUE}sudo nano ~/umbrel/app-data/core-lightning/data/lightningd/bitcoin/config${NC}"
             echo "#########################################"
             echo -e "${YELLOW}bind-addr=0.0.0.0:9735${NC}"
             echo -e "${YELLOW}announce-addr=${vpn_dns}:${vpn_port}${NC}"
             echo -e "${YELLOW}always-use-proxy=false${NC}"
             echo "#########################################"
             echo ""
             echo "2. Edit: nano ~/umbrel/app-data/core-lightning/exports.sh"
             echo "#########################################"
             echo -e "${BOLD}export APP_CORE_LIGHTNING_DAEMON_PORT=\"9735\"${NC}"
             echo "#########################################"
             echo ""
             echo "3. Edit: ~/umbrel/app-data/core-lightning/docker-compose.yml"
             echo "   Comment out '--bind-addr' if present."
        else
             echo -e "Edit: ${BOLD}${BLUE}${TS_NODE_CONF_FILE:-config}${NC}"
             echo ""
             echo "#########################################"
             echo -e "${YELLOW}bind-addr=0.0.0.0:9735${NC}"
             echo -e "${YELLOW}announce-addr=${vpn_dns}:${vpn_port}${NC}"
             echo -e "${YELLOW}always-use-proxy=false${NC}"
             echo "#########################################"
        fi
        
    elif [[ "$LN_IMPL" == "lit" ]]; then
         local lit_path="$HOME/.lit/lit.conf"
         # Check both lit.service and litd.service for config path
         local lit_service_file=""
         [[ -f "/etc/systemd/system/litd.service" ]] && lit_service_file="/etc/systemd/system/litd.service"
         [[ -f "/etc/systemd/system/lit.service" ]] && lit_service_file="/etc/systemd/system/lit.service"
         if [[ -n "$lit_service_file" ]]; then
             local extracted_path=$(grep "LIT_CONFIG_FILE" "$lit_service_file" | sed 's/.*LIT_CONFIG_FILE=//' | tr -d '"' | tr -d "'" | xargs)
             [[ -n "$extracted_path" ]] && lit_path="$extracted_path"
         fi
         echo -e "Edit: ${BOLD}${BLUE}$lit_path${NC}"
         echo ""
         echo "#########################################"
         echo -e "${BOLD}${BLUE}[Application Options]${NC}"
         echo -e "${YELLOW}externalhosts=${vpn_dns}:${vpn_port}${NC}"
         echo ""
         echo -e "${BOLD}${BLUE}[Tor]${NC}"
         echo -e "${YELLOW}tor.streamisolation=false${NC}"
         echo -e "${YELLOW}tor.skip-proxy-for-clearnet-targets=true${NC}"
         echo "#########################################"
    fi
}

# ---------------------------------------------------------------------------
# COMMON UTILITY FUNCTIONS
# ---------------------------------------------------------------------------


check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        print_error "This script must be run as root"
        echo "Please run: sudo $0 $@"
        exit 1
    fi
}

ufw_rule_marker_file() {
    local interface="$1"
    local safe_interface="${interface//[^[:alnum:]_.-]/_}"
    echo "/etc/wireguard/.tunnelsats-ufw-9735-${safe_interface}.created"
}

is_port_allowed_in_ufw() {
    local interface="$1"
    local port="$2"
    local ufw_status_out="$3"
    
    if [[ -z "$ufw_status_out" ]]; then
        if ! command -v ufw >/dev/null 2>&1; then
            return 1
        fi
        ufw_status_out=$(ufw status 2>/dev/null)
    fi
    
    if ! echo "$ufw_status_out" | grep -q "Status: active"; then
        return 0 # If UFW is not active, the port is allowed/unfiltered
    fi
    
    local ufw_rules
    ufw_rules=$(echo "$ufw_status_out" | grep -Ei "(^|[[:space:]])${port}(/|[[:space:]]|$)" || true)
    if [[ -z "$ufw_rules" ]]; then
        return 1
    fi
    
    while IFS= read -r line; do
        if [[ ! "$line" =~ "ALLOW" ]]; then
            continue
        fi

        if [[ "$line" =~ ALLOW[[:space:]]+OUT ]]; then
            continue
        fi
        
        if [[ "$line" =~ "on " ]]; then
            if [[ "$line" =~ [[:space:]]on[[:space:]]+([^[:space:]]+) ]]; then
                local rule_interface="${BASH_REMATCH[1]}"
                if [[ "$rule_interface" == "$interface" ]]; then
                    return 0
                fi
            fi
        else
            # Global rule
            return 0
        fi
    done <<< "$ufw_rules"
    
    return 1
}

check_ufw_configuration() {
    local interface="$1"
    
    # Check if ufw command exists
    if ! command -v ufw >/dev/null 2>&1; then
        return 0
    fi
    
    local ufw_status_out
    ufw_status_out=$(ufw status 2>/dev/null)
    # Check if ufw is active
    if ! echo "$ufw_status_out" | grep -q "Status: active"; then
        print_info "UFW is installed but inactive (not filtering traffic)."
        return 0
    fi
    
    if is_port_allowed_in_ufw "$interface" "9735" "$ufw_status_out"; then
        print_success "UFW is active and inbound traffic on port 9735 is allowed."
        return 0
    else
        print_info "UFW is active but port 9735 is not allowed on $interface. Adding rule..."
        if ufw allow in on "$interface" to any port 9735 proto tcp comment "TunnelSats" &>/dev/null; then
            touch "$(ufw_rule_marker_file "$interface")" 2>/dev/null || true
            print_success "Added UFW rule: allow inbound TCP 9735 on $interface"
            return 0
        else
            print_error "Failed to add UFW rule for port 9735 on $interface"
            return 0 # Return 0 so it doesn't trigger set -e abort
        fi
    fi
}
valid_ipv4() {
    local ip=$1
    local stat=1
    
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && \
           ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

# Succeeds if file name $1 is an installed TunnelSats WireGuard config that wg-quick can load:
# tunnelsatsv2.conf or tunnelsats-<name>.conf, with an interface name of at most 15 characters.
ts_valid_installed_config_name() {
    local name="$1" iface="${1%.conf}"
    [[ "$name" =~ ^tunnelsats(v2|-[A-Za-z0-9_=+.-]+)\.conf$ ]] && [[ ${#iface} -le 15 ]]
}

# Installed TunnelSats WireGuard configs and the one in use. One rule for detect, status, restart
# and uninstall, so they never pick different tunnels:
#   1. an explicit config (--config) wins
#   2. else <dir>/tunnelsatsv2.conf (the canonical name)
#   3. else the only <dir>/tunnelsats-*.conf
#   4. else nothing is picked: "ambiguous" (several candidates) or "none"
# $1 = explicit config or "", $2 = filesystem root prefix (detect passes TS_FS_ROOT), $3 = WireGuard
# directory below the root (default /etc/wireguard). Sets TS_WG_SELECTION (explicit, canonical,
# single, ambiguous, none, permission_denied), TS_WG_SELECTED (path below the root, empty unless a
# config is picked) and TS_WG_CANDIDATES (every TunnelSats config found, sorted byte-wise).
ts_select_wg_config() {
    local LC_ALL=C
    local explicit="$1" root="${2:-}" wg_dir="${3:-/etc/wireguard}" entry name unreadable=0 parent
    local dir="${root}${wg_dir}"
    TS_WG_SELECTION="none"
    TS_WG_SELECTED=""
    TS_WG_CANDIDATES=()
    if [[ -e "$dir" ]]; then
        if [[ ! -r "$dir" ]] || [[ ! -x "$dir" ]]; then
            unreadable=1
        fi
    else
        # Absent, or hidden behind a parent directory that may not be searched: then nobody can
        # tell whether a config exists, so this is permission_denied, not none
        parent="$dir"
        while [[ "$parent" == */* ]]; do
            parent="${parent%/*}"
            if [[ -z "$parent" ]]; then
                break
            fi
            if [[ -e "$parent" ]]; then
                if [[ -d "$parent" ]] && [[ ! -x "$parent" ]]; then
                    unreadable=1
                fi
                break
            fi
        done
    fi
    # Glob results are sorted (byte-wise with LC_ALL=C); names must be valid interface names
    for entry in "$dir"/tunnelsats-*.conf "$dir"/tunnelsatsv2.conf; do
        name="${entry##*/}"
        if [[ -f "$entry" ]] && ts_valid_installed_config_name "$name"; then
            TS_WG_CANDIDATES+=("${wg_dir}/${name}")
        fi
    done
    if [[ -n "$explicit" ]]; then
        TS_WG_SELECTION="explicit"
        TS_WG_SELECTED="$explicit"
    elif [[ -f "${dir}/tunnelsatsv2.conf" ]]; then
        TS_WG_SELECTION="canonical"
        TS_WG_SELECTED="${wg_dir}/tunnelsatsv2.conf"
    elif [[ "$unreadable" -eq 1 ]]; then
        TS_WG_SELECTION="permission_denied"
    elif [[ ${#TS_WG_CANDIDATES[@]} -eq 1 ]]; then
        TS_WG_SELECTION="single"
        TS_WG_SELECTED="${TS_WG_CANDIDATES[0]}"
    elif [[ ${#TS_WG_CANDIDATES[@]} -gt 1 ]]; then
        TS_WG_SELECTION="ambiguous"
    fi
    return 0
}

# The installed config used by status and restart (ts_select_wg_config on ${WG_DIR:-/etc/wireguard}).
# Several candidates are a question: it is asked like the install config selection and answered
# by --config, so non-interactive mode fails with E_INTERACTION_REQUIRED before anything changes
# and no command ever picks one of several tunnels on its own.
# Sets TS_WG_RESOLVED; returns 1 if no TunnelSats config is installed.
ts_resolve_wg_config() {
    local selected=""
    TS_WG_RESOLVED=""
    ts_select_wg_config "$CONFIG_FILE" "" "${WG_DIR:-/etc/wireguard}"
    case "$TS_WG_SELECTION" in
        explicit|canonical|single)
            TS_WG_RESOLVED="$TS_WG_SELECTED"
            ;;
        ambiguous)
            print_warning "Several TunnelSats configs are installed and none is named tunnelsatsv2.conf."
            selected=$(select_config_interactive "${TS_WG_CANDIDATES[@]}") || exit $?
            TS_WG_RESOLVED="$selected"
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

# Parse metadata from config file (supports old and new formats)
# Usage: parse_config_metadata <config_file> <field>
# Fields: port, expiry, pubkey
parse_config_metadata() {
    local config_file="$1"
    local field="$2"
    
    if [[ ! -f "$config_file" ]]; then
        return 1
    fi
    
    case "$field" in
        port)
            # Old format: #VPNPort = 48049; website: # Port Forwarding: 24556; StartOS: # VPNPort: 31337
            # The whole number after the label is returned, never truncated, and callers check the
            # range 1-65535 (ts_normalize_port). A value that does not start with a digit is returned
            # as written, so that it is reported as invalid instead of looking like a missing port.
            local port=$(sed -nE 's/^[[:space:]]*#[[:space:]]*(VPNPort|Port Forwarding)[[:space:]]*[:=]?[[:space:]]*//Ip' "$config_file" | head -1 | sed -E 's/^([0-9]+)([^0-9.,].*)?$/\1/; s/[[:space:]]+$//')
            echo "$port"
            ;;
        expiry)
            # Old format: #ValidUntil (UTC time) = 2025-06-29T08:18:33.839Z
            # Website, API and StartOS format: # Valid Until: 2026-01-07T08:18:33.839Z
            # The label is matched explicitly, so the colons inside the timestamp are kept.
            local expiry=$(sed -nE 's|^[[:space:]]*#[[:space:]]*Valid[[:space:]]*Until([[:space:]]*\(UTC time\))?[[:space:]]*[:=][[:space:]]*||Ip' "$config_file" | head -1 | sed -E 's/[[:space:]]+$//')
            echo "$expiry"
            ;;
        pubkey)
            # Old format: #myPubKey = 6gTYyE8eFW7579zIOlvEgehrhGb01SrqC5dgQupxlAU=
            # New format: # myPubKey: <user's-public-key>
            # A hint only: the key in use is derived from PrivateKey (ts_derive_wg_pubkey).
            local pubkey=$(sed -nE 's|^[[:space:]]*#[[:space:]]*myPubKey[[:space:]]*[:=][[:space:]]*([A-Za-z0-9+/]{43}=).*|\1|Ip' "$config_file" | head -1)
            echo "$pubkey"
            ;;
        *)
            return 1
            ;;
    esac
}

# Prints port $1 as a plain decimal number if it is a valid port (1-65535); fails otherwise.
# Leading zeros are accepted. Long digit strings are rejected before any arithmetic, so a huge
# value cannot wrap around into the valid range.
ts_normalize_port() {
    if [[ "$1" =~ ^0*([1-9][0-9]{0,4})$ ]] && (( 10#${BASH_REMATCH[1]} <= 65535 )); then
        echo "$((10#${BASH_REMATCH[1]}))"
        return 0
    fi
    return 1
}

# Forwarded VPN port of config $1 for the installer: prints the port (1-65535), or nothing if the
# config has no port comment. An invalid value is never truncated or used: it is reported with a
# warning on stderr and treated like a missing comment.
ts_config_vpn_port() {
    local raw="" port="" shown=""
    raw=$(parse_config_metadata "$1" port) || raw=""
    if [[ -z "$raw" ]]; then
        return 0
    fi
    if port=$(ts_normalize_port "$raw"); then
        echo "$port"
        return 0
    fi
    # print_warning uses echo -e: neutralise backslashes and control characters from the file
    shown="${raw:0:32}"
    shown="${shown//\\/\\\\}"
    shown="${shown//[[:cntrl:]]/?}"
    print_warning "Ignoring invalid forwarded port '${shown}' in ${1##*/} (expected 1-65535)"
    return 0
}

# ---------------------------------------------------------------------------
# CONFIG FILE DETECTION
# ---------------------------------------------------------------------------

find_config_files() {
    local search_dir="${1:-.}"
    local found_files=()
    
    # Priority 1: tunnelsats_*.conf files (sorted, so the selection menu is stable)
    while IFS= read -r -d '' file; do
        found_files+=("$file")
    done < <(find "$search_dir" -maxdepth 1 -name "tunnelsats_*.conf" -type f -print0 2>/dev/null | LC_ALL=C sort -z)
    
    # Priority 2: If none found, look for any .conf files
    if [[ ${#found_files[@]} -eq 0 ]]; then
        while IFS= read -r -d '' file; do
            # Exclude system config files
            if [[ ! "$file" =~ /(nftables|sysctl|resolv)\.conf$ ]]; then
                found_files+=("$file")
            fi
        done < <(find "$search_dir" -maxdepth 1 -name "*.conf" -type f -print0 2>/dev/null | LC_ALL=C sort -z)
    fi
    
    # Return the array
    [[ ${#found_files[@]} -gt 0 ]] && printf '%s\n' "${found_files[@]}"
}

select_config_interactive() {
    local files=("$@")
    echo "" >&2
    print_info "Found ${#files[@]} WireGuard configuration file(s):"
    echo "" >&2
    
    for i in "${!files[@]}"; do
        echo "  $((i+1))) ${files[$i]##*/}" >&2
    done
    
    echo "" >&2
    # read -p prompts to stderr by default, but we need to ensure inputs don't clutter result
    ts_ask selection "--config <file>" "Select config [1-${#files[@]}]: "
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && \
       [[ "$selection" -ge 1 ]] && \
       [[ "$selection" -le "${#files[@]}" ]]; then
        echo "${files[$((selection-1))]}"
    else
        print_error "Invalid selection"
        exit 1
    fi
}

detect_config_file() {
    local config_arg="$1"
    
    # Priority 1: If --config explicitly provided via argument, verify and use it
    if [[ -n "$config_arg" ]]; then
        if [[ -f "$config_arg" ]]; then
            print_success "Using specified config: ${config_arg##*/}"
            echo "$config_arg"
            return 0
        else
            print_error "Config file not found: $config_arg"
            exit 1
        fi
    fi
    
    # Priority 2: Auto-detect config files in current directory
    mapfile -t found_files < <(find_config_files "$SCRIPT_DIR")
    
    if [[ ${#found_files[@]} -eq 0 ]]; then
        print_error "No WireGuard config files found"
        echo "" >&2
        echo "Expected files:" >&2
        echo "  • tunnelsats_<server>.conf (e.g., tunnelsats_us-east.conf)" >&2
        echo "  • Any .conf file in the current directory" >&2
        echo "  • Or specify a config path with --config <file>" >&2
        echo "" >&2
        echo "Please specify your config file and try again." >&2
        exit 1
        
    elif [[ ${#found_files[@]} -eq 1 ]]; then
        print_success "Auto-detected config: ${found_files[0]##*/}"
        echo "${found_files[0]}"
        return 0
        
    else
        # Multiple configs - interactive selection (--config answers it). A failed selection
        # (invalid answer, end of input, non-interactive mode) must stop here: this function runs
        # in a command substitution, where set -e is not inherited.
        local selected
        selected=$(select_config_interactive "${found_files[@]}") || exit $?
        echo "$selected"
        return 0
    fi
}

# ---------------------------------------------------------------------------
# COMMAND HANDLERS
# ---------------------------------------------------------------------------

cmd_help() {
    print_header "Usage Guide"
    
    cat << 'EOF'
Usage: sudo bash tunnelsats.sh [COMMAND] [OPTIONS]

Commands:
  install                   Install WireGuard VPN configuration
  install --config <file>   Install with specific config file
  install --managed baremetal
                            Managed mode (preview) for bare-metal systemd nodes: a
                            persistent kill switch that does not depend on the
                            tunnel, and Lightning in its own systemd slice
  install --managed raspiblitz --impl lnd|cln [--network mainnet|testnet|signet]
                            The same on RaspiBlitz, for the Lightning instance that
                            --impl and --network name (lnd.service, tlnd.service, ...)
  install --managed mynode [--impl lnd|lit]
                            The same on myNode, with a pre-start LND config guard
                            that keeps hybrid settings across myNode restarts
  adopt --managed baremetal|raspiblitz|mynode
                            Replace an existing standard (legacy) install with the
                            managed dataplane in one step
  pre-check                 Check system compatibility
  uninstall                 Remove TunnelSats installation
  uninstall --managed       Remove a managed install exactly as it was installed
  status                    Show subscription and connection status
  verify                    Check the managed dataplane: kernel state plus probes
                            from inside the Lightning slice (on a standard install:
                            tunnel and kill switch facts, verdict "unmanaged")
  restart                   Restart the WireGuard tunnel interface
  detect                    Read-only report: platform, Lightning units, existing
                            install, config, capabilities, conflicts (no root needed)
  version                   Show version, CLI contract and script sha256
  help                      Show this help message

Options (accepted before or after the command):
  --config <file>           WireGuard config to use (install, adopt, status, restart)
  --platform <id>           raspiblitz, umbrel, mynode or baremetal
                            (install, adopt, uninstall, status, restart)
  --impl <id>               lnd, cln or lit (install, adopt, uninstall, status, restart)
  --yes                     Answer yes to confirmation prompts
  --remove-packages         uninstall: also remove nftables and wireguard-tools
                            (and cgroup-tools)
  --keep-packages           uninstall: keep system packages without asking
  --keep-config             uninstall: keep /etc/wireguard/tunnelsats*.conf on disk
  --legacy-artifacts        uninstall --managed: also clean legacy v2/v3 artifacts
                            (or clean a legacy install when no managed record exists)
  --managed [profile]       install, adopt (profile baremetal, raspiblitz or mynode),
                            uninstall: managed mode
  --network <chain>         install/adopt --managed raspiblitz: mainnet (default),
                            testnet or signet
  --uid-backstop            install/adopt --managed: also route the Lightning user's
                            traffic into the tunnel by uid (see docs/managed-mode.md)
  --no-probe                verify: kernel checks only, no network probes
  --non-interactive         Never prompt: a question that no option answers fails
                            with exit code 2 before any change is made
  --json                    One JSON document on stdout, logs on stderr (version,
                            detect, verify, and install, adopt, uninstall --managed);
                            implies --non-interactive

Exit codes: 0 success, 1 failure, 2 usage error or interaction required
            verify and managed mode also use 3 not installed, 4 unsafe,
            5 degraded (kill switch holds, tunnel down), 6 capability missing,
            7 refused, 8 invalid config, 9 unmanaged (verify on a standard install)

Examples:
  # Run compatibility check first
  sudo bash tunnelsats.sh pre-check
  
  # Install with auto-detection
  sudo bash tunnelsats.sh install
  
  # Install with specific config
  sudo bash tunnelsats.sh install --config tunnelsats_us-east.conf
  
  # Install without prompts (for scripts and node platforms)
  sudo bash tunnelsats.sh install --non-interactive --config tunnelsats_us-east.conf --platform raspiblitz --impl lnd
  
  # Managed mode on a bare-metal node (preview), then check it
  sudo bash tunnelsats.sh install --managed baremetal --config tunnelsats_us-east.conf
  sudo tunnelsats verify

  # Managed mode on RaspiBlitz, for its mainnet LND
  sudo bash tunnelsats.sh install --managed raspiblitz --impl lnd --config tunnelsats_us-east.conf

  # Check status
  sudo bash tunnelsats.sh status
  
  # Restart WireGuard tunnel
  sudo bash tunnelsats.sh restart

  # Clean uninstall
  sudo bash tunnelsats.sh uninstall

  # Inspect the node without changing anything
  bash tunnelsats.sh detect --json

For more information:
  Website: https://tunnelsats.com
  Guide: https://tunnelsats.com/guide
  Managed mode: https://github.com/Tunnelsats/tunnelsats/blob/main/docs/managed-mode.md
  Support: https://tunnelsats.com/join-telegram

EOF
}

cmd_pre_check() {
    print_header "Compatibility Check"
    
    echo "Checking system requirements..."
    echo ""
    
    local rating=0
    
    # Check kernel version (min 5.10.102+ required)
    print_step 1 3 "Checking kernel version..."
    local kernelMajor=$(uname -r | cut -d '.' -f1)
    local kernelMinor=$(uname -r | cut -d '.' -f2)
    local kernelPatch=$(uname -r | cut -d '.' -f3 | cut -d '-' -f1 | tr -cd '0-9')
    
    # Defaults in case of parsing failure
    kernelMajor=${kernelMajor:-0}
    kernelMinor=${kernelMinor:-0}
    kernelPatch=${kernelPatch:-0}
    
    if [[ $kernelMajor -gt 5 ]] || \
       [[ $kernelMajor -ge 5 && ( ($kernelMinor -ge 10 && $kernelPatch -ge 102) || $kernelMinor -ge 11 ) ]]; then
        print_success "Kernel $(uname -r) is compatible"
        ((rating+=1))
    else
        print_error "Kernel 5.10.102+ required (found $(uname -r))"
    fi
    echo ""
    
    # Check nftables version (min 0.9.6+ required)
    print_step 2 3 "Checking nftables version..."
    local nftablesVersion=""
    if command -v nft &>/dev/null; then
        nftablesVersion=$(nft -v | awk '{print $2}' | cut -d 'v' -f2)
    elif command -v apt-cache &>/dev/null; then
        nftablesVersion=$(apt-cache policy nftables | grep Candidate | awk '{print $2}' | cut -d '-' -f1)
    else
        nftablesVersion="0.0.0"
    fi
    
    if [[ -z "$nftablesVersion" ]]; then nftablesVersion="0.0.0"; fi

    local nftMajor=$(echo "$nftablesVersion" | cut -d '.' -f1)
    local nftMinor=$(echo "$nftablesVersion" | cut -d '.' -f2)
    local nftPatch=$(echo "$nftablesVersion" | cut -d '.' -f3)
    
    nftMajor=${nftMajor:-0}
    nftMinor=${nftMinor:-0}
    nftPatch=${nftPatch:-0}
    
    if [[ $nftMajor -ge 1 ]] || \
       [[ $nftMajor -eq 0 && $nftMinor -ge 9 && $nftPatch -ge 6 ]] || \
       [[ $nftMajor -eq 0 && $nftMinor -ge 10 ]]; then
        print_success "nftables $nftablesVersion is compatible"
        ((rating+=1))
    else
        print_error "nftables 0.9.6+ required (found $nftablesVersion)"
    fi
    echo ""
    
    # Check for systemd services or docker
    print_step 3 3 "Looking for Lightning implementation..."
    if [[ -f /etc/systemd/system/lnd.service ]]; then
        print_success "Found lnd.service"
        ((rating+=1))
    elif [[ -f /etc/systemd/system/lightningd.service ]]; then
        print_success "Found lightningd.service"
        ((rating+=1))
    else
        print_info "Checking for Docker containers..."
        local dockerProcess=$(docker ps --format 'table {{.Image}} {{.Names}} {{.Ports}}' 2>/dev/null | grep -E "0.0.0.0:9735|0.0.0.0:9736" | awk '{print $2}' || echo "")
        if [[ ${dockerProcess} == *lnd* ]]; then
            print_success "Found LND container"
            ((rating+=1))
        elif [[ ${dockerProcess} == *clightning* ]] || [[ ${dockerProcess} == *core-lightning* ]]; then
            print_success "Found CLN container"
            ((rating+=1))
        else
            print_error "No suitable Lightning implementation found"
        fi
    fi
    echo ""
    
    # Display result
    print_line
    echo -e "${BOLD}Compatibility Rating: $rating/3${NC}"
    print_line
    echo ""
    
    if [[ $rating -eq 3 ]]; then
        print_success "Your system is fully compatible with TunnelSats!"
        echo ""
        echo "Ready to install? Run:"
        echo -e "  ${GREEN}sudo bash tunnelsats.sh install${NC}"
    elif [[ $rating -gt 0 && $rating -lt 3 ]]; then
        print_warning "Your system is likely compatible, but some requirements are missing"
        echo "Review the checks above and install missing components"
    else
        print_error "Your system is not compatible with TunnelSats"
        echo "Please review the requirements at https://tunnelsats.com/guide"
    fi
    echo ""
}

# Helper functions for install command

check_umbrel_version() {
    local version_file="${UMBREL_VERSION_FILE:-/opt/umbreld/package.json}"
    if [[ -f "$version_file" ]]; then
        local version
        if command -v jq &>/dev/null; then
            version=$(jq -r '.version // empty' "$version_file" 2>/dev/null || true)
        else
            version=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$version_file" 2>/dev/null | head -n 1 || true)
        fi
        if [[ -z "$version" ]]; then
            echo "Warning: could not determine Umbrel OS version from $version_file" >&2
            return 0
        fi
        if [[ -n "$version" ]]; then
            local major
            local minor
            major=$(echo "$version" | cut -d. -f1 | sed 's/^[^0-9]*//; s/[^0-9].*$//')
            minor=$(echo "$version" | cut -d. -f2 | sed 's/^[^0-9]*//; s/[^0-9].*$//')
            
            major=${major:-0}
            minor=${minor:-0}
            
            if (( 10#$major > 1 || (10#$major == 1 && 10#$minor >= 6) )); then
                echo "" >&2
                print_error "TunnelSats CLI setup is discontinued for Umbrel OS versions 1.6 and above."
                echo -e "Please install TunnelSats natively through the Umbrel Community App Store:" >&2
                echo -e "  ${BLUE}URL: https://github.com/Tunnelsats/ts-umbrel-app${NC}" >&2
                echo -e "  ${YELLOW}(Umbrel > App Store > Settings > Add App Store)${NC}" >&2
                echo -e "More details: https://github.com/Tunnelsats/tunnelsats/discussions/193" >&2
                echo "" >&2
                exit 1
            fi
        fi
    fi
}

# Platform markers in detection order: "<platform> <d|f> <path>" (directory or file).
TS_PLATFORM_MARKERS=(
    "raspiblitz d /home/admin/config.scripts"
    "umbrel d /home/umbrel/umbrel"
    "umbrel d /umbrel"
    "umbrel f /usr/bin/umbrel"
    "mynode d /usr/share/mynode"
)

# Prints the platform suggested by the first matching marker (nothing if none matches).
# $1 = optional filesystem root prefix (detect passes TS_FS_ROOT).
ts_guess_platform() {
    local root="${1:-}" marker platform rest kind path
    for marker in "${TS_PLATFORM_MARKERS[@]}"; do
        platform="${marker%% *}"
        rest="${marker#* }"
        kind="${rest%% *}"
        path="${rest#* }"
        if { [[ "$kind" == "d" ]] && [[ -d "${root}${path}" ]]; } || { [[ "$kind" == "f" ]] && [[ -f "${root}${path}" ]]; }; then
            echo "$platform"
            return 0
        fi
    done
    return 0
}

detect_platform() {
    local guess=""
    guess=$(ts_guess_platform)

    # --platform answers both questions below without interaction
    if [[ -n "$TS_OPT_PLATFORM" ]]; then
        if [[ -n "$guess" ]] && [[ "$guess" != "$TS_OPT_PLATFORM" ]]; then
            print_warning "Using --platform ${TS_OPT_PLATFORM} (detected: ${guess})"
        fi
        PLATFORM="$TS_OPT_PLATFORM"
        return 0
    fi

    if [[ -n "$guess" ]]; then
        ts_ask use_guess "--platform <id>" "Detected Platform: ${guess}. Correct? [Y/n]: "
        if [[ "$use_guess" =~ ^[Yy]$ ]] || [[ -z "$use_guess" ]]; then
            PLATFORM="$guess"
            return 0
        fi
    fi

    ts_require_interaction "--platform <id>" "Select [1-4]: "
    echo "What Lightning node package are you running?" >&2
    echo "  1) RaspiBlitz" >&2
    echo "  2) Umbrel" >&2
    echo "  3) myNode" >&2
    echo "  4) RaspiBolt / Bare Metal" >&2
    echo "" >&2
    ts_ask answer "--platform <id>" "Select [1-4]: "
    
    case $answer in
        1) PLATFORM="raspiblitz" ;;
        2) 
            PLATFORM="umbrel"
            ;;
        3) PLATFORM="mynode" ;;
        4) PLATFORM="baremetal" ;;
        *) print_error "Invalid selection"; exit 1 ;;
    esac
    return 0
}

get_lightning_docker_containers() {
    # Returns container IDs matching the lightning daemon for $LN_IMPL
    # $1 (optional): extra flags for docker ps (e.g. "-a" to list stopped containers as well)
    local extra_flags="${1:-}"
    if ! command -v docker >/dev/null 2>&1; then
        return 0
    fi
    local regex
    if [[ "$LN_IMPL" == "cln" ]]; then
        regex="$CLN_CONTAINER_REGEX"
    elif [[ "$LN_IMPL" == "lnd" ]]; then
        regex="$LND_CONTAINER_REGEX"
    else
        # If LN_IMPL is not set, match either implementation
        regex="${LND_CONTAINER_REGEX}|${CLN_CONTAINER_REGEX}"
    fi
    docker ps $extra_flags --format "{{.ID}} {{.Names}}" 2>/dev/null | \
        grep -Ei "$regex" | \
        grep -Eiv "$LN_CONTAINER_EXCLUDE_REGEX" | \
        awk '{print $1}'
}

# Selects exactly one Lightning daemon container to own the static tunnel IP (10.9.9.9).
# Preference: the daemon stopped for this restart > running daemons > newest stopped daemon.
# Fails (return 1) if multiple candidates would compete for the same static IP.
select_tunnel_target_container() {
    local candidates=""
    if [[ -n "$stopped_docker_containers" ]]; then
        candidates="$stopped_docker_containers"
    else
        candidates=$(get_lightning_docker_containers)
    fi
    if [[ -z "$candidates" ]]; then
        # No daemon running: keep the stopped container that already owns the tunnel IP (sticky owner),
        # otherwise fall back to the newest one (docker ps -a lists newest first).
        local c
        for c in $(get_lightning_docker_containers "-a"); do
            if [[ " $(docker inspect -f "$TUNNEL_NET_INSPECT_FMT" "$c" 2>/dev/null || true) " == *" ${TUNNEL_CONTAINER_IP} "* ]]; then
                candidates="$c"
                break
            fi
        done
        [[ -z "$candidates" ]] && candidates=$(get_lightning_docker_containers "-a" | head -n 1)
    fi
    local count
    count=$(printf '%s\n' $candidates | grep -c . || true)
    if [[ "$count" -gt 1 ]]; then
        print_error "Multiple running ${LN_IMPL} daemon containers found ($(echo $candidates)). Only one can own the tunnel IP ${TUNNEL_CONTAINER_IP}."
        return 1
    fi
    echo "$candidates"
}

# Ensures exactly the given container holds 10.9.9.9 on docker-tunnelsats.
# Reattaches it if attached with another address and releases the static IP from stale (stopped) containers.
attach_container_to_tunnel_network() {
    local cid="$1"
    local state
    state=$(docker inspect -f "$TUNNEL_NET_INSPECT_FMT" "$cid" 2>/dev/null || true)
    if [[ " $state " == *" ${TUNNEL_CONTAINER_IP} "* ]]; then
        return 0
    fi

    if [[ -n "$state" ]]; then
        print_info "Container ($cid) is attached to docker-tunnelsats with a different address; reattaching with ${TUNNEL_CONTAINER_IP}..."
        if ! docker network disconnect -f docker-tunnelsats "$cid" >/dev/null 2>&1; then
            print_error "Failed to detach container ($cid) from docker-tunnelsats"
            return 1
        fi
    fi

    local other other_state
    for other in $(get_lightning_docker_containers "-a"); do
        [[ "$other" == "$cid" ]] && continue
        other_state=$(docker inspect -f "$TUNNEL_NET_INSPECT_FMT" "$other" 2>/dev/null || true)
        [[ " $other_state " == *" ${TUNNEL_CONTAINER_IP} "* ]] || continue
        if [[ "$(docker inspect -f '{{.State.Running}}' "$other" 2>/dev/null)" == "true" ]]; then
            print_error "Running container ($other) already holds ${TUNNEL_CONTAINER_IP} on docker-tunnelsats. Refusing to evict it."
            return 1
        fi
        print_info "Releasing ${TUNNEL_CONTAINER_IP} from stale stopped container ($other)..."
        if ! docker network disconnect -f docker-tunnelsats "$other" >/dev/null 2>&1; then
            print_error "Failed to detach stale container ($other) from docker-tunnelsats"
            return 1
        fi
    done

    print_info "Connecting container ($cid) to docker-tunnelsats network (${TUNNEL_CONTAINER_IP})..."
    if ! docker network connect --ip "$TUNNEL_CONTAINER_IP" docker-tunnelsats "$cid" >/dev/null 2>&1; then
        print_error "Failed to connect container ($cid) to docker-tunnelsats network"
        return 1
    fi
    return 0
}


# Succeeds if LIT runs in integrated mode (it manages its own LND).
# $1 = optional filesystem root prefix (detect passes TS_FS_ROOT).
ts_lit_integrated_mode() {
    local root="${1:-}"
    local s_file="${root}/etc/systemd/system/litd.service"
    [[ ! -f "$s_file" ]] && s_file="${root}/etc/systemd/system/lit.service"
    grep -qi "lnd-mode=integrated" "$s_file" 2>/dev/null || grep -qi "lnd-mode.*integrated" "${root}/etc/lit/lit.conf" 2>/dev/null || grep -qi "lnd-mode.*integrated" "${root}${HOME}/.lit/lit.conf" 2>/dev/null
}

# Prints the Lightning implementation suggested by systemd units (lnd, cln, lit or nothing).
# $1 = optional filesystem root prefix (detect passes TS_FS_ROOT).
ts_guess_ln_impl_systemd() {
    local root="${1:-}"
    local sd="${root}/etc/systemd/system"
    if [[ -f "$sd/lnd.service" ]] || "$SYSTEMCTL_BIN" is-active --quiet lnd 2>/dev/null; then
        echo "lnd"
    elif [[ -f "$sd/lightningd.service" ]] || "$SYSTEMCTL_BIN" is-active --quiet lightningd 2>/dev/null; then
        echo "cln"
    elif [[ -f "$sd/litd.service" ]] || [[ -f "$sd/lit.service" ]] || "$SYSTEMCTL_BIN" is-active --quiet litd 2>/dev/null || "$SYSTEMCTL_BIN" is-active --quiet lit 2>/dev/null; then
        # Verify if Integrated Mode
        if ts_lit_integrated_mode "$root"; then
            echo "lit"
        fi
    fi
    return 0
}

detect_ln_implementation() {
    local guess=""
    if [[ "$PLATFORM" == "umbrel" ]]; then
        local lnd_containers
        lnd_containers=$(LN_IMPL=lnd get_lightning_docker_containers)
        local cln_containers
        cln_containers=$(LN_IMPL=cln get_lightning_docker_containers)
        if [[ -n "$lnd_containers" ]]; then
            guess="lnd"
        elif [[ -n "$cln_containers" ]]; then
            guess="cln"
        fi
    else
        guess=$(ts_guess_ln_impl_systemd)
    fi

    if [[ -n "$guess" ]]; then
        if [[ -n "$TS_OPT_IMPL" ]]; then
            # --impl answers the confirmation: yes if it names the detected implementation
            if [[ "$TS_OPT_IMPL" == "$guess" ]]; then
                use_guess="Y"
            else
                use_guess="n"
            fi
        else
            ts_ask use_guess "--impl <id>" "Detected Implementation: ${guess^^}. Correct? [Y/n]: "
        fi
        if [[ "$use_guess" =~ ^[Yy]$ ]] || [[ -z "$use_guess" ]]; then
            LN_IMPL="$guess"
            # Detect node user for non-Docker
            if [[ "$PLATFORM" != "umbrel" ]]; then
                local s_file=""
                [[ "$LN_IMPL" == "lnd" ]] && s_file="/etc/systemd/system/lnd.service"
                [[ "$LN_IMPL" == "cln" ]] && s_file="/etc/systemd/system/lightningd.service"
                if [[ "$LN_IMPL" == "lit" ]]; then
                    s_file="/etc/systemd/system/litd.service"
                    [[ ! -f "$s_file" ]] && s_file="/etc/systemd/system/lit.service"
                fi
                if [[ -f "$s_file" ]]; then
                    node_user=$(grep "^User=" "$s_file" | cut -d'=' -f2 | xargs)
                fi
                [[ -z "$node_user" ]] && [[ "$PLATFORM" == "raspiblitz" ]] && node_user="bitcoin"
                [[ -z "$node_user" ]] && node_user=$(whoami)
            fi
            return 0
        fi
    fi

    local range="1-2"
    if [[ "$PLATFORM" == "baremetal" ]]; then
        range="1-3"
    fi
    if [[ -n "$TS_OPT_IMPL" ]]; then
        # --impl answers the selection exactly like the matching menu entry
        if [[ -n "$guess" ]]; then
            print_warning "Using --impl ${TS_OPT_IMPL} (detected: ${guess})"
        fi
        case "$TS_OPT_IMPL" in
            lnd) choice="1" ;;
            cln) choice="2" ;;
            lit)
                if [[ "$PLATFORM" != "baremetal" ]]; then
                    ts_usage_error "--impl lit is only available on platform baremetal (platform: ${PLATFORM})"
                fi
                choice="3"
                ;;
        esac
    else
        ts_require_interaction "--impl <id>" "Select [$range]: "
        echo "Which Lightning implementation do you want to tunnel?" >&2
        echo "  1) LND" >&2
        echo "  2) CLN (Core Lightning)" >&2
        if [[ "$PLATFORM" == "baremetal" ]]; then
            echo "  3) LIT (integrated mode)" >&2
        fi
        echo "" >&2
        ts_ask choice "--impl <id>" "Select [$range]: "
    fi
    
    case $choice in
        1) 
            LN_IMPL="lnd"
            [[ -z "$node_user" ]] && node_user="bitcoin"
            ;;
        2) 
            LN_IMPL="cln"
            [[ -z "$node_user" ]] && node_user="bitcoin"
            ;;
        3) 
            if [[ "$PLATFORM" == "baremetal" ]]; then
                LN_IMPL="lit"
                
                # Verify Integrated Mode or warn
                if ! ts_lit_integrated_mode; then
                    print_warning "LIT Integrated mode not detected in config."
                    ts_confirm lit_confirm "Are you sure LIT is managing its own LND? [y/N]: "
                    if [[ ! "$lit_confirm" =~ ^[Yy]$ ]]; then
                        print_info "Please restart and select LND instead."
                        exit 0
                    fi
                fi
                local s_file="/etc/systemd/system/litd.service"
                [[ ! -f "$s_file" ]] && s_file="/etc/systemd/system/lit.service"
                node_user=$(grep "^User=" "$s_file" 2>/dev/null | cut -d'=' -f2 | xargs)
                [[ -z "$node_user" ]] && node_user="bitcoin"
            else
                print_error "LIT only available on bare metal"
                exit 1
            fi
            ;;
        *) print_error "Invalid selection"; exit 1 ;;
    esac
    return 0
}

install_dependencies() {
    print_info "Updating package repositories..."
    apt-get update > /dev/null 2>&1
    
    # Install WireGuard
    if ! command -v wg &>/dev/null; then
        print_info "Installing WireGuard..."
        apt-get install -y wireguard > /dev/null 2>&1 && \
            print_success "WireGuard installed" || \
            { print_error "Failed to install WireGuard"; exit 1; }
    else
        print_success "WireGuard already installed"
    fi
    
    # Install nftables
    if ! command -v nft &>/dev/null; then
        print_info "Installing nftables..."
        apt-get install -y nftables > /dev/null 2>&1 && \
            print_success "nftables installed" || \
            { print_error "Failed to install nftables"; exit 1; }
    else
        print_success "nftables already installed"
    fi
    
    # Install cgroup-tools (non-Docker only)
    if [[ "$PLATFORM" != "umbrel" ]]; then
        if ! command -v cgcreate &>/dev/null; then
            print_info "Installing cgroup-tools..."
            apt-get install -y cgroup-tools > /dev/null 2>&1 && \
                print_success "cgroup-tools installed" || \
                { print_error "Failed to install cgroup-tools"; exit 1; }
        else
            print_success "cgroup-tools already installed"
        fi
    fi
    
    # Install resolvconf
    if ! command -v resolvconf &>/dev/null; then
        print_info "Installing resolvconf..."
        if apt-get install -y resolvconf > /dev/null 2>&1; then
            mkdir -p "${WG_DIR:-/etc/wireguard}" 2>/dev/null || true
            : > "${WG_DIR:-/etc/wireguard}/.tunnelsats-resolvconf.installed" 2>/dev/null || true
            print_success "resolvconf installed"
        else
            print_error "Failed to install resolvconf"
            exit 1
        fi
    else
        print_success "resolvconf already installed"
    fi
}

# Sanitize WireGuard config by stripping any prior TunnelSats setup hooks,
# duplicate [Interface] sections, or stale routing directives.
# Preserves only the canonical base config (keys, endpoint, addresses, and comments).
sanitize_wireguard_config() {
    local input_file="$1"
    local output_file="$2"
    
    if [[ ! -f "$input_file" ]]; then
        print_error "Input config file does not exist: $input_file"
        return 1
    fi

    # Backup existing destination if present
    if [[ -f "$output_file" ]]; then
        local backup_file
        if ! backup_file=$(mktemp "${output_file}.bak.XXXXXX"); then
            print_error "Failed to create backup file for: $output_file"
            return 1
        fi
        if ! cp "$output_file" "$backup_file"; then
            print_error "Failed to backup existing config to: $backup_file"
            rm -f "$backup_file"
            return 1
        fi
        WG_CONFIG_BACKUP="$backup_file"
    fi

    # Extract base config:
    # 1. Stop processing at any TunnelSats marker (#Tunnelsats-Setup)
    # 2. Drop any secondary [Interface] blocks that appear after [Peer]
    # 3. Strip any PreUp, PostUp, PreDown, PostDown, FwMark, or Table directives (tolerant of indentation and casing)
    local clean_content
    clean_content=$(awk '
        BEGIN { in_peer=0; found_marker=0; in_secondary=0 }
        {
            raw = $0
            lower = tolower(raw)
            trimmed = lower
            sub(/^[[:space:]]+/, "", trimmed)
        }
        trimmed ~ /^#tunnelsats-setup/ { found_marker=1 }
        found_marker { next }
        trimmed ~ /^\[peer\]/ { in_peer=1; in_secondary=0 }
        in_peer && (trimmed ~ /^\[interface\]/) { in_secondary=1; next }
        in_secondary && (trimmed ~ /^\[/) { in_secondary=0 }
        in_secondary { next }
        trimmed ~ /^(preup|postup|predown|postdown|fwmark|table|saveconfig|listenport)[[:space:]]*=/ { next }
        { print raw }
    ' "$input_file")

    # Safety validation: PrivateKey and Endpoint must exist
    if ! echo "$clean_content" | grep -qiE "^[[:space:]]*PrivateKey[[:space:]]*="; then
        print_error "Config sanitization failed: PrivateKey missing from config"
        return 1
    fi
    if ! echo "$clean_content" | grep -qiE "^[[:space:]]*Endpoint[[:space:]]*="; then
        print_error "Config sanitization failed: Endpoint missing from config"
        return 1
    fi

    # Ensure PersistentKeepalive is set to maintain NAT state across firewalls/routers
    if ! echo "$clean_content" | grep -qiE "^[[:space:]]*PersistentKeepalive[[:space:]]*="; then
        print_info "PersistentKeepalive not found; ensuring PersistentKeepalive = 25 under [Peer]..."
        clean_content=$(printf '%s\nPersistentKeepalive = 25\n' "$clean_content")
    elif echo "$clean_content" | grep -qiE "^[[:space:]]*PersistentKeepalive[[:space:]]*=[[:space:]]*0\b"; then
        print_warning "PersistentKeepalive is set to 0. Updating to 25 to prevent NAT state drops..."
        clean_content=$(echo "$clean_content" | sed -E 's/^[[:space:]]*[Pp][Ee][Rr][Ss][Ii][Ss][Tt][Ee][Nn][Tt][Kk][Ee][Ee][Pp][Aa][Ll][Ii][Vv][Ee][[:space:]]*=[[:space:]]*0\b/PersistentKeepalive = 25/')
    fi

    # Trim trailing blank lines
    clean_content=$(echo "$clean_content" | sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba')

    # Write sanitized content safely via temporary file
    local temp_out
    if ! temp_out=$(mktemp); then
        print_error "Failed to create temporary file for sanitized config"
        return 1
    fi
    if ! printf '%s\n' "$clean_content" > "$temp_out"; then
        print_error "Failed to write sanitized config to temporary file"
        rm -f "$temp_out"
        return 1
    fi
    if ! mv "$temp_out" "$output_file"; then
        print_error "Failed to move sanitized config to destination: $output_file"
        rm -f "$temp_out"
        return 1
    fi
    return 0
}

resolve_wg_target_path() {
    # Determine target filename - preserve dynamic names or use tunnelsatsv2.conf as fallback
    local source_filename
    source_filename=$(basename "$CONFIG_FILE")
    if [[ "$source_filename" == tunnelsats-*.conf ]]; then
        # New format with server name - preserve it
        echo "/etc/wireguard/$source_filename"
    else
        # Old format or generic - use tunnelsatsv2.conf for backward compatibility
        echo "/etc/wireguard/tunnelsatsv2.conf"
    fi
}

configure_wireguard() {
    print_info "Copying config to /etc/wireguard/..."
    
    local target_path
    target_path=$(resolve_wg_target_path)
    local target_filename
    target_filename=$(basename "$target_path")
    
    # Store target path for use in service setup (and for rollback of the config backup)
    WG_CONFIG_PATH="$target_path"
    WG_INTERFACE=$(basename "$target_path" .conf)
    
    # Sanitize and copy config, stripping any previous routing/hook residue
    print_info "Sanitizing WireGuard configuration..."
    if ! sanitize_wireguard_config "$CONFIG_FILE" "$target_path"; then
        print_error "Failed to sanitize WireGuard configuration"
        exit 1
    fi
    
    print_success "Config sanitized and copied to $target_filename"
    
    # Verify config has Endpoint
    if ! grep -q "Endpoint" "$target_path"; then
        print_error "Config missing Endpoint entry"
        exit 1
    fi

    # Check if IPv6 is disabled on the host (check procfs and sysctl)
    local ipv6_disabled=0
    if [ ! -f "${TS_FS_ROOT:-}/proc/net/if_inet6" ]; then
        ipv6_disabled=1
    elif [ "$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)" == "1" ]; then
        ipv6_disabled=1
    fi

    if [ "$ipv6_disabled" -eq 1 ]; then
        print_warning "IPv6 appears to be disabled on this host."
        if grep -q "::/0" "$target_path"; then
            print_info "Stripping IPv6 (::/0) from AllowedIPs to prevent wg-quick failure..."
            # Strip ::/0, handles cases like "0.0.0.0/0, ::/0" or "::/0, 0.0.0.0/0"
            sed -i 's/,\s*::\/0//g' "$target_path"
            sed -i 's/::\/0,\s*//g' "$target_path"
            # If the line is ONLY AllowedIPs = ::/0, removing it might leave an invalid config.
            # We'll comment it out if it would otherwise be empty, though unlikely in Tunnelsats.
            sed -i 's/^AllowedIPs\s*=\s*::\/0/#AllowedIPs = ::\/0 (removed: ipv6 disabled)/g' "$target_path"
        fi
    fi
    
    # Fetch all local networks and exclude them from kill switch
    local localNetworks=$(ip route | grep -v default | awk '{print $1}' | grep -v "$WG_INTERFACE" | grep -v "10.9.0" | tr '\n' ',' | sed 's/,$//')
    if [ -z "$localNetworks" ]; then
        localNetworks="10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16"
    fi
    
    # Ownership-scoped table 51820 guard executed by the PostUp/PostDown hooks below
    local route_guard
    route_guard=$(route_guard_path)
    if ! write_route_guard_script; then
        print_error "Failed to write routing guard: ${route_guard}"
        exit 1
    fi

    # Apply network rules based on platform
    if [[ "$PLATFORM" == "umbrel" ]]; then
        print_info "Applying Docker network rules..."
        if [ "$ipv6_disabled" -eq 0 ]; then
            touch "${WG_DIR:-/etc/wireguard}/.tunnelsats-ipv6-disabled" 2>/dev/null || true
        fi
        
        # Pre-resolve subnet to avoid command failure in PostUp
        # Pre-resolve subnet and bridge_id to avoid command failure in PostUp
        local dockersubnet=""
        local bridge_id=""
        local inspect_output

        if inspect_output=$(docker network inspect "docker-tunnelsats" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}} {{.Id}}' 2>/dev/null); then
            local bridge_id_full
            read -r dockersubnet bridge_id_full <<< "$inspect_output"
            bridge_id=${bridge_id_full:0:12}
        fi

        [[ -z "$dockersubnet" ]] && dockersubnet="10.9.9.0/25" # Fallback to standard

        # Dynamically determine the bridge interface for the tunnelsats network
        local bridge_name
        [[ -z "$bridge_id" ]] && bridge_name="br-6c3d330ad9f5" || bridge_name="br-$bridge_id"
        
        local vpn_port=$(ts_config_vpn_port "$target_path")
        [[ -z "$vpn_port" ]] && vpn_port=9735 # fallback (no valid port comment)

        local inputDocker="

#Tunnelsats-Setupv2-Docker

[Interface]
DNS = 8.8.8.8
Table = off

PreUp = sysctl -w net.ipv6.conf.all.disable_ipv6=1; sysctl -w net.ipv6.conf.default.disable_ipv6=1
PreUp = $route_guard arm $dockersubnet
PostUp = $route_guard check %i $dockersubnet
PostUp = for n in 1 2 3 4 5 6 7 8 9 10; do ip rule del priority 21820 from all table main suppress_prefixlength 0 2>/dev/null || break; done
PostUp = for n in 1 2 3 4 5 6 7 8 9 10; do ip rule del priority 21821 from $dockersubnet table 51820 2>/dev/null || break; done
PostUp = $route_guard clean %i

PostUp = ip route add blackhole default metric 3 table 51820
PostUp = ip route add default dev %i metric 2 table 51820
PostUp = ip rule add from all table main suppress_prefixlength 0 priority 21820
PostUp = ip rule add from $dockersubnet table 51820 priority 21821
PostUp = ip route add 10.9.0.0/24 dev %i proto kernel scope link; ping -c1 10.9.0.1

PostUp = iptables -t nat -I PREROUTING -i %i -p tcp --dport $vpn_port -j DNAT --to-destination 10.9.9.9:9735
PostUp = iptables -I FORWARD -i %i -o $bridge_name -j ACCEPT
PostUp = iptables -I FORWARD -i $bridge_name -o %i -j ACCEPT
PostUp = ip6tables -I FORWARD -i $bridge_name -j DROP 2>/dev/null || true
PostUp = ip6tables -I FORWARD -o $bridge_name -j DROP 2>/dev/null || true

PostUp = sysctl -w net.ipv4.conf.all.rp_filter=0
PostUp = sysctl -w net.ipv6.conf.all.disable_ipv6=1
PostUp = sysctl -w net.ipv6.conf.default.disable_ipv6=1
PostUp = $route_guard release $dockersubnet

PostDown = iptables -t nat -D PREROUTING -i %i -p tcp --dport $vpn_port -j DNAT --to-destination 10.9.9.9:9735
PostDown = iptables -D FORWARD -i %i -o $bridge_name -j ACCEPT
PostDown = iptables -D FORWARD -i $bridge_name -o %i -j ACCEPT
PostDown = ip6tables -D FORWARD -i $bridge_name -j DROP 2>/dev/null || true
PostDown = ip6tables -D FORWARD -o $bridge_name -j DROP 2>/dev/null || true

PostDown = ip rule del priority 21820 from all table main suppress_prefixlength 0 2>/dev/null || true
PostDown = ip rule del priority 21821 from $dockersubnet table 51820 2>/dev/null || true
PostDown = $route_guard clean %i || true
PostDown = sysctl -w net.ipv4.conf.all.rp_filter=1
"
        echo -e "$inputDocker" >> "$target_path"
        
    else
        print_info "Applying non-Docker network rules..."
        
        local killswitchNonDocker=""
        local killswitchNonDocker6=""
        # Node uid for the guard's blackhole ip rule fallback (emergency block without nft)
        local failclosed_host_uid
        failclosed_host_uid=$(resolve_failclosed_host_uid)
        if [[ "$failclosed_host_uid" =~ ^[1-9][0-9]{0,9}$ ]]; then
            killswitchNonDocker6=" ; add rule inet %i out6 meta skuid ${failclosed_host_uid} ip6 daddr != { ::1/128, fc00::/7, fe80::/10 } counter drop"
        fi
        # Enable cgroup-aware killswitch for all non-Docker systemd platforms
        if [[ "$PLATFORM" == "raspiblitz" || "$PLATFORM" == "baremetal" || "$PLATFORM" == "mynode" ]]; then
            # Cgroup-aware killswitch: Only drop if user is node_user AND packet is in the tunnelsats cgroup (1118498)
            # This allows other services (like bitcoind) sharing the same user to reach clearnet/tor normally
            killswitchNonDocker="PostUp = nft \"insert rule ip %i nat skuid ${node_user} meta cgroup 1118498 fib daddr type != local ip daddr != { $localNetworks } meta oifname != %i counter drop\"\n"
        fi
        
        local inputNonDocker="

#Tunnelsats-Setupv2-Non-Docker

[Interface]
FwMark = 0x2000000
Table = off


PreUp = $route_guard arm 10.9.9.0/25 $failclosed_host_uid
PostUp = $route_guard check %i 10.9.9.0/25 $failclosed_host_uid
PostUp = for n in 1 2 3 4 5 6 7 8 9 10; do ip rule del priority 21820 from all table main suppress_prefixlength 0 2>/dev/null || break; done
PostUp = for n in 1 2 3 4 5 6 7 8 9 10; do ip rule del priority 21821 from all fwmark 0x1000000/0xff000000 table 51820 2>/dev/null || break; done
PostUp = $route_guard clean %i

PostUp = ip route add default dev %i table 51820;
PostUp = ip rule add from all table main suppress_prefixlength 0 priority 21820
PostUp = ip rule add from all fwmark 0x1000000/0xff000000 table 51820 priority 21821
PostUp = ip route add  10.9.0.0/24 dev %i  proto kernel scope link; ping -c1 10.9.0.1
PostUp = sysctl -w net.ipv4.conf.all.rp_filter=0

PostUp = nft add table ip %i
PostUp = nft add chain ip %i prerouting '{ type filter hook prerouting priority mangle -1; policy accept; }'; nft add rule ip %i prerouting meta mark set ct mark
PostUp = nft add chain ip %i mangle '{ type route hook output priority mangle -1; policy accept; }'; nft add rule ip %i mangle tcp sport != { 8080, 10009 } meta mark and 0xff000000 != 0x2000000 meta cgroup 1118498 meta mark set 0x1000000
PostUp = nft \"add chain ip %i nat { type nat hook postrouting priority srcnat -1; policy accept; } ; insert rule ip %i nat fib daddr type != local ip daddr != { $localNetworks } oifname != %i ct mark and 0xff000000 == 0x1000000 drop ; add rule ip %i nat oifname %i ct mark and 0xff000000 == 0x1000000 masquerade\"
${killswitchNonDocker}PostUp = nft \"add chain ip %i postroutingmangle { type filter hook postrouting priority mangle -1; policy accept; } ; add rule ip %i postroutingmangle meta mark and 0xff000000 == 0x1000000 ct mark set meta mark and 0x00ffffff xor 0x1000000\"
PostUp = nft \"add chain ip %i input { type filter hook input priority filter -1; policy accept; } ; add rule ip %i input iifname %i ct state established,related counter accept ; add rule ip %i input iifname %i tcp dport != 9735 counter drop ; add rule ip %i input iifname %i udp dport != 9735 counter drop\"
PostUp = nft add table inet %i
PostUp = nft \"add chain inet %i out6 { type filter hook output priority filter - 1; policy accept; } ; add rule inet %i out6 meta cgroup 1118498 ip6 daddr != { ::1/128, fc00::/7, fe80::/10 } counter drop${killswitchNonDocker6}\"
PostUp = $route_guard release 10.9.9.0/25 $failclosed_host_uid


PostDown = nft delete table ip %i
PostDown = nft delete table inet %i 2>/dev/null || true
PostDown = ip rule del priority 21820 from all table main suppress_prefixlength 0 2>/dev/null || true
PostDown = ip rule del priority 21821 from all fwmark 0x1000000/0xff000000 table 51820 2>/dev/null || true
PostDown = $route_guard clean %i || true
PostDown = sysctl -w net.ipv4.conf.all.rp_filter=1
"
        echo -e "$inputNonDocker" >> "$target_path"
    fi
    
    # Verify rules were applied
    if grep -q "Tunnelsats-Setupv2" "$target_path"; then
        print_success "Network rules applied"
    else
        print_error "Network rules not applied"
        exit 1
    fi
}

setup_cgroups() {
    print_info "Creating cgroup for traffic splitting..."
    local failclosed_host_uid
    failclosed_host_uid=$(resolve_failclosed_host_uid)
    local wg_unit="wg-quick@${WG_INTERFACE:-tunnelsatsv2}.service"
    
    # Create cgroup script
    cat > /etc/wireguard/tunnelsats-create-cgroup.sh << EOF
#!/bin/sh
set -e
modprobe cls_cgroup || true
dir_netcls="/sys/fs/cgroup/net_cls"
splitted_processes="/sys/fs/cgroup/net_cls/splitted_processes"

if [ ! -d "\$dir_netcls" ]; then
    mkdir -p "\$dir_netcls" 2>/dev/null || true
    if mount -t cgroup -o net_cls none "\$dir_netcls" 2>/dev/null; then
        echo "> Successfully added cgroup net_cls subsystem"
    else
        rmdir "\$dir_netcls" 2>/dev/null || true
    fi
fi

if [ -d "\$dir_netcls" ] && [ -e "\$dir_netcls/net_cls.classid" ]; then
    if [ ! -d "\$splitted_processes" ]; then
        mkdir /sys/fs/cgroup/net_cls/splitted_processes
        echo 1118498 > /sys/fs/cgroup/net_cls/splitted_processes/net_cls.classid
        chmod 666 /sys/fs/cgroup/net_cls/splitted_processes/tasks
        echo "> Successfully added Mark for net_cls subsystem"
    else
        echo "> Mark for net_cls subsystem already present"
    fi
fi

if [ -x /etc/wireguard/tunnelsats-route-guard.sh ] && ! systemctl is-active --quiet "${wg_unit}" 2>/dev/null; then
    /etc/wireguard/tunnelsats-route-guard.sh arm 10.9.9.0/25 "${failclosed_host_uid}" || true
fi
EOF
    
    chmod +x /etc/wireguard/tunnelsats-create-cgroup.sh
    /etc/wireguard/tunnelsats-create-cgroup.sh
    
    # Create systemd service for cgroup
    cat > /etc/systemd/system/tunnelsats-create-cgroup.service << EOF
[Unit]
Description=Creating cgroup for Splitting lightning traffic
Before=${wg_unit}
StartLimitInterval=200
StartLimitBurst=5
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/etc/wireguard/tunnelsats-create-cgroup.sh
[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable tunnelsats-create-cgroup.service &>/dev/null
   systemctl start tunnelsats-create-cgroup.service
    
    print_success "Cgroups configured"
}

# Deletes a TunnelSats-owned policy rule only while `ip rule show` contains a line matching
# the full selector regex ($1). Remaining args are passed to `ip rule del`. Bounded to avoid spinning.
delete_owned_ip_rule() {
    local pattern="$1"
    shift
    local attempt
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        ip rule show 2>/dev/null | grep -Eq "$pattern" || return 0
        if ! ip rule del "$@" 2>/dev/null; then
            print_warning "Failed to delete TunnelSats policy rule: ip rule del $*"
            return 1
        fi
    done
    return 0
}

check_and_cleanup_routing_table() {
    local iface="${1:-$WG_INTERFACE}"

    # 1. Detect conflicting WireGuard interfaces owning table 51820
    if command -v wg >/dev/null 2>&1; then
        local other_wg
        for other_wg in $(wg show interfaces 2>/dev/null); do
            if [[ -n "$iface" ]] && [[ "$other_wg" != "$iface" ]]; then
                if ip route show table 51820 2>/dev/null | grep -q "dev ${other_wg}\b"; then
                    print_error "Routing table 51820 contains routes owned by another active WireGuard interface (${other_wg}). Conflicting ownership detected. Aborting."
                    exit 1
                fi
            fi
        done
    fi

    # 2. Check for foreign routes in table 51820 (anything not owned by TunnelSats).
    #    An unreadable table is unverified state and aborts (fail-closed).
    local foreign_routes=""
    if ! foreign_routes=$(ts_table51820_foreign_routes "$iface"); then
        print_error "Routing table 51820 could not be verified. Aborting to prevent inconsistent routing."
        exit 1
    fi
    if [[ -n "$foreign_routes" ]]; then
        print_error "Routing table 51820 contains routes owned by another interface/service:"
        echo "$foreign_routes"
        print_error "Conflicting routing ownership detected. Aborting cleanup to protect other networking services."
        exit 1
    fi

    # 3./4. Remove TunnelSats-owned policy rules and routes only
    if ! cleanup_owned_routing_state "$iface"; then
        print_error "Failed to remove stale TunnelSats policy rules. Aborting to prevent inconsistent routing."
        exit 1
    fi
}

# Removes TunnelSats-owned policy rules and TunnelSats-owned routes in table 51820.
# Never flushes the table and never touches foreign rules/routes, so it is also safe for uninstall
# when another service uses table 51820. Returns 1 if an owned policy rule could not be removed.
cleanup_owned_routing_state() {
    local iface="${1:-$WG_INTERFACE}"

    # Rules are matched by priority AND full selector/table,
    # so foreign rules that happen to reuse priority 21820/21821 are never touched.
    local dsubnet="${dockersubnet:-$(resolve_failclosed_subnet)}"
    local dsubnet_re
    dsubnet_re=$(printf '%s' "$dsubnet" | sed 's/\./\\./g')
    local rule_cleanup_failed=0
    delete_owned_ip_rule "^21820:[[:space:]]+from all lookup main suppress_prefixlength 0([[:space:]]|$)" \
        priority 21820 from all table main suppress_prefixlength 0 || rule_cleanup_failed=1
    delete_owned_ip_rule "^21821:[[:space:]]+from ${dsubnet_re} lookup 51820([[:space:]]|$)" \
        priority 21821 from "$dsubnet" table 51820 || rule_cleanup_failed=1
    delete_owned_ip_rule "^21821:[[:space:]]+from all fwmark 0x1000000/0xff000000 lookup 51820([[:space:]]|$)" \
        priority 21821 from all fwmark 0x1000000/0xff000000 table 51820 || rule_cleanup_failed=1

    # Also clean up legacy TunnelSats-specific selectors (any priority) targeting table 51820
    delete_owned_ip_rule "from ${dsubnet_re} lookup 51820([[:space:]]|$)" \
        from "$dsubnet" table 51820 || rule_cleanup_failed=1
    delete_owned_ip_rule "from all fwmark 0x1000000/0xff000000 lookup 51820([[:space:]]|$)" \
        from all fwmark 0x1000000/0xff000000 table 51820 || rule_cleanup_failed=1

    # Routes: only the ones TunnelSats installs (never `ip route flush table 51820`)
    ts_table51820_remove_owned "$iface"

    [[ "$rule_cleanup_failed" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# OWNERSHIP-SCOPED ROUTING TABLE 51820 PRIMITIVES
# These functions are embedded verbatim (declare -f) into the generated wg-quick route guard
# (write_route_guard_script), so the installer and the runtime PostUp/PostDown hooks share one
# implementation. Keep them self-contained: no globals, no print_* helpers.
#
# TunnelSats-owned routes in table 51820 are exactly:
#   - the Docker kill-switch route "blackhole default metric 3"
#   - routes via the TunnelSats WireGuard interface ("... dev <iface> ...")
# Everything else in table 51820 belongs to another service and must never be removed.
# ---------------------------------------------------------------------------

# Prints the IPv4 routes of table 51820. A table that does not exist yet is reported as empty.
# Returns 1 if the table cannot be read; callers must treat that as unverified and fail closed.
ts_table51820_routes() {
    local out rc
    out=$(ip route show table 51820 2>&1) && rc=0 || rc=$?
    if [ "$rc" -ne 0 ]; then
        case "$out" in
            *"FIB table does not exist"*) return 0 ;;
        esac
        echo "TunnelSats: unable to read routing table 51820: ${out}" >&2
        return 1
    fi
    if [ -n "$out" ]; then
        printf '%s\n' "$out"
    fi
    return 0
}

# Reads routes of table 51820 on stdin and prints those TunnelSats does not own ($1 = the
# TunnelSats interface; with an empty $1 only the kill-switch blackhole counts as owned).
# Shared by the route guard (embedded verbatim) and detect, so both judge ownership identically.
ts_table51820_filter_foreign() {
    awk -v ifc="$1" '
        NF == 0 { next }
        NF == 4 && $1 == "blackhole" && $2 == "default" && $3 == "metric" && $4 == "3" { next }
        {
            for (i = 1; i < NF; i++) {
                if ($i == "dev" && ifc != "" && $(i + 1) == ifc) { next }
            }
            print
        }'
}

# Prints the routes in table 51820 that TunnelSats does not own ($1 = TunnelSats interface).
# Returns 1 if the table cannot be read.
ts_table51820_foreign_routes() {
    local iface="$1" routes
    routes=$(ts_table51820_routes) || return 1
    [ -n "$routes" ] || return 0
    printf '%s\n' "$routes" | ts_table51820_filter_foreign "$iface"
}

# Removes only the routes TunnelSats installs into table 51820. Never flushes the table.
# Bounded loops; a missing route or device simply ends the loop.
ts_table51820_remove_owned() {
    local iface="$1" n
    for n in 1 2 3 4 5 6 7 8 9 10; do
        ip route del blackhole default metric 3 table 51820 2>/dev/null || break
    done
    if [ -n "$iface" ]; then
        for n in 1 2 3 4 5 6 7 8 9 10; do
            ip route del default dev "$iface" table 51820 2>/dev/null || break
        done
    fi
    return 0
}

# Emergency fail-closed block for Lightning traffic while no verified tunnel exists (#205).
# Primary: nft drop table "ip tunnelsats_failclosed" for host traffic in the TunnelSats cgroup and
# forwarded traffic from the Docker tunnel subnet. Fallback when nft is missing or rejects a rule
# (e.g. nf_tables failed to load at boot): blackhole policy rules that need no netfilter at all,
# evaluated before the main table, so no Lightning traffic can take the main-table default route:
#   21818: from <Docker tunnel subnet> blackhole    (forwarded container traffic)
#   21819: uidrange <node uid> blackhole           (host Lightning daemon, non-Docker only)
# Local destinations keep working through the local table (priority 0), like the nft drop's
# "fib daddr type != local". Every state is verified with a real read (nft list / ip rule show)
# before it is reported as armed.

# $1 = Docker tunnel subnet, $2 = optional host uid. Succeeds only if a real read of the ruleset shows all drop rules.
ts_failclosed_nft_verified() {
    local subnet="$1" host_uid="${2:-}" out subnet_re
    command -v nft >/dev/null 2>&1 || return 1
    out=$(nft list table inet tunnelsats_failclosed 2>/dev/null) || return 1
    subnet_re=$(printf '%s' "$subnet" | sed 's/[.]/\\./g')
    printf '%s\n' "$out" | grep -Eq 'meta cgroup 1118498 .*drop' || return 1
    case "$host_uid" in
        ""|0|*[!0-9]*) ;;
        *) printf '%s\n' "$out" | grep -Eq "meta skuid ${host_uid} .*drop" || return 1 ;;
    esac
    printf '%s\n' "$out" | grep -Eq "ip saddr ${subnet_re} .*drop" || return 1
    return 0
}

# Arms the nft drop ($1 = Docker tunnel subnet, $2 = optional host uid). Returns 1 unless the drop is verified in place.
ts_arm_failclosed_nft() {
    local subnet="$1" host_uid="${2:-}" failed=0
    if ! command -v nft >/dev/null 2>&1; then
        echo "TunnelSats: nft not available; nft emergency drop could NOT be armed" >&2
        return 1
    fi
    # Already armed and verified (e.g. a repeated refusal): do not stack duplicate rules.
    ts_failclosed_nft_verified "$subnet" "$host_uid" && return 0
    nft add table inet tunnelsats_failclosed || failed=1
    nft "add chain inet tunnelsats_failclosed output { type filter hook output priority -100; policy accept; }" || failed=1
    nft "add rule inet tunnelsats_failclosed output meta cgroup 1118498 fib daddr type != local counter drop" || failed=1
    case "$host_uid" in
        ""|0|*[!0-9]*) ;;
        *) nft "add rule inet tunnelsats_failclosed output meta skuid ${host_uid} fib daddr type != local counter drop" || failed=1 ;;
    esac
    nft "add chain inet tunnelsats_failclosed forward { type filter hook forward priority -100; policy accept; }" || failed=1
    nft "add rule inet tunnelsats_failclosed forward ip saddr ${subnet} fib daddr type != local counter drop" || failed=1
    if [ "$failed" -ne 0 ]; then
        echo "TunnelSats: nft rejected an emergency drop rule; nft emergency drop could NOT be armed" >&2
        return 1
    fi
    if ! ts_failclosed_nft_verified "$subnet" "$host_uid"; then
        echo "TunnelSats: nft accepted the emergency drop but it is not in the ruleset; nft emergency drop could NOT be verified" >&2
        return 1
    fi
    return 0
}

# Path to the state file recording emergency blackhole selectors TunnelSats has armed, so release
# and uninstall can still remove a previously armed rule if the node account or subnet later changes.
ts_failclosed_state_file() {
    if [ -n "${WG_DIR:-}" ]; then
        echo "${WG_DIR}/.tunnelsats-failclosed-rules"
    elif [ "${0##*/}" = "tunnelsats-route-guard.sh" ] && [ "${0%/*}" != "$0" ]; then
        echo "${0%/*}/.tunnelsats-failclosed-rules"
    else
        echo "/etc/wireguard/.tunnelsats-failclosed-rules"
    fi
}

# Records a selector ("from <subnet>" or "uidrange <uid>-<uid>") that TunnelSats itself added
# to the kernel policy rules. Returns 1 if the ownership state file cannot be updated.
ts_record_failclosed_rule() {
    local entry="$1" state_file
    state_file=$(ts_failclosed_state_file)
    grep -qxF "$entry" "$state_file" 2>/dev/null && return 0
    printf '%s\n' "$entry" >> "$state_file" 2>/dev/null
}

# $1 = Docker tunnel subnet, $2 = host uid ("" when there is no host daemon to cover).
# Succeeds only if a real read of the IPv4 (and IPv6 when available) policy rules shows every required blackhole rule.
ts_failclosed_rules_verified() {
    local subnet="$1" uid="$2" rules rules6 subnet_re ip_cmd="${IP_BIN:-ip}"
    rules=$("$ip_cmd" -4 rule show 2>/dev/null) || return 1
    subnet_re=$(printf '%s' "$subnet" | sed 's/[.]/\\./g')
    printf '%s\n' "$rules" | grep -Eq "^21818:[[:space:]]+from ${subnet_re}[[:space:]]+blackhole[[:space:]]*$" || return 1
    if [ -n "$uid" ]; then
        printf '%s\n' "$rules" | grep -Eq "^21819:[[:space:]]+from all uidrange ${uid}-${uid}[[:space:]]+blackhole[[:space:]]*$" || return 1
        if [ -e "${TS_FS_ROOT:-}/proc/net/if_inet6" ]; then
            rules6=$("$ip_cmd" -6 rule show 2>/dev/null) || return 1
            printf '%s\n' "$rules6" | grep -Eq "^21819:[[:space:]]+from all uidrange ${uid}-${uid}[[:space:]]+blackhole[[:space:]]*$" || return 1
        fi
    fi
    return 0
}

# Arms the routing-policy fallback. $1 = Docker tunnel subnet, $2 = host uid:
#   ""         Docker platform, only the subnet needs to be blocked;
#   <uid>      non-Docker platform, the node user's uid is blocked too (never root);
#   otherwise  non-Docker platform whose node uid is unknown: the host daemon cannot be
#              covered, so this reports failure even though the subnet rule is armed.
# Only rules that were absent before and added by TunnelSats are recorded in ts_failclosed_state_file,
# so a pre-existing blackhole rule owned by another service is never claimed or deleted on release.
ts_arm_failclosed_rules() {
    local subnet="$1" host_uid="$2" uid="" rules rules6 subnet_re ip_cmd="${IP_BIN:-ip}"
    case "$host_uid" in
        "") ;;
        0|*[!0-9]*)
            echo "TunnelSats: node user uid unknown or root (${host_uid}); the routing-policy fallback cannot cover the host Lightning daemon" >&2
            uid="unusable" ;;
        *) uid="$host_uid" ;;
    esac
    subnet_re=$(printf '%s' "$subnet" | sed 's/[.]/\\./g')
    rules=$("$ip_cmd" -4 rule show 2>/dev/null) || return 1
    if ! printf '%s\n' "$rules" | grep -Eq "^21818:[[:space:]]+from ${subnet_re}[[:space:]]+blackhole[[:space:]]*$"; then
        if "$ip_cmd" -4 rule add from "$subnet" blackhole priority 21818; then
            if ! ts_record_failclosed_rule "from ${subnet}"; then
                "$ip_cmd" -4 rule del priority 21818 from "$subnet" blackhole 2>/dev/null || true
                return 1
            fi
        fi
    fi
    if [ -n "$uid" ] && [ "$uid" != "unusable" ] && \
        ! printf '%s\n' "$rules" | grep -Eq "^21819:[[:space:]]+from all uidrange ${uid}-${uid}[[:space:]]+blackhole[[:space:]]*$"; then
        if "$ip_cmd" -4 rule add uidrange "${uid}-${uid}" blackhole priority 21819; then
            if ! ts_record_failclosed_rule "uidrange ${uid}-${uid}"; then
                "$ip_cmd" -4 rule del priority 21819 uidrange "${uid}-${uid}" blackhole 2>/dev/null || true
                return 1
            fi
        fi
    fi
    if [ -n "$uid" ] && [ "$uid" != "unusable" ] && [ -e "${TS_FS_ROOT:-}/proc/net/if_inet6" ]; then
        rules6=$("$ip_cmd" -6 rule show 2>/dev/null) || return 1
        if ! printf '%s\n' "$rules6" | grep -Eq "^21819:[[:space:]]+from all uidrange ${uid}-${uid}[[:space:]]+blackhole[[:space:]]*$"; then
            if "$ip_cmd" -6 rule add uidrange "${uid}-${uid}" blackhole priority 21819; then
                if ! ts_record_failclosed_rule "uidrange6 ${uid}-${uid}"; then
                    "$ip_cmd" -6 rule del priority 21819 uidrange "${uid}-${uid}" blackhole 2>/dev/null || true
                    return 1
                fi
            fi
        fi
    fi
    [ "$uid" = "unusable" ] && return 1
    ts_failclosed_rules_verified "$subnet" "$uid"
}

# Arms the emergency block ($1 = Docker tunnel subnet, $2 = host uid, see ts_arm_failclosed_rules).
# Returns 1 unless nft or the routing-policy fallback is verified in place (callers must report that).
ts_arm_failclosed() {
    local subnet="${1:-10.9.9.0/25}" host_uid="${2:-}"
    if ts_arm_failclosed_nft "$subnet" "$host_uid"; then
        return 0
    fi
    if ts_arm_failclosed_rules "$subnet" "$host_uid"; then
        echo "TunnelSats: routing-policy fallback armed and verified (blackhole ip rules 21818/21819): Lightning traffic cannot use the main table" >&2
        return 0
    fi
    echo "TunnelSats: routing-policy fallback could NOT be armed either" >&2
    return 1
}

# Removes only the emergency blackhole rules that TunnelSats itself added and recorded in
# ts_failclosed_state_file. Pre-existing or foreign rules on priorities 21818/21819 are never
# touched, while rules TunnelSats armed are removed even if the tunnel subnet or node UID later
# changed or was removed. Returns 1 if policy rules cannot be read or an owned rule remains.
ts_release_failclosed_rules() {
    local state_file entry entry_re clauses="" clauses6="" pattern pattern6 n rules rules6 line prio sel ip_cmd="${IP_BIN:-ip}"
    if ! rules=$("$ip_cmd" -4 rule show 2>/dev/null); then
        echo "TunnelSats: ERROR: unable to read IPv4 policy rules while releasing emergency blackhole rules" >&2
        return 1
    fi
    state_file=$(ts_failclosed_state_file)
    [ -f "$state_file" ] || return 0
    while IFS= read -r entry || [ -n "$entry" ]; do
        case "$entry" in
            "from "[0-9]*.[0-9]*.[0-9]*.[0-9]*/*)
                entry_re=$(printf '%s' "${entry#from }" | sed 's/[.]/\\./g')
                clauses="${clauses:+${clauses}|}21818:[[:space:]]+from ${entry_re}"
                ;;
            "uidrange "[1-9][0-9]*-[1-9][0-9]*)
                clauses="${clauses:+${clauses}|}21819:[[:space:]]+from all ${entry}"
                ;;
            "uidrange6 "[1-9][0-9]*-[1-9][0-9]*)
                clauses6="${clauses6:+${clauses6}|}21819:[[:space:]]+from all uidrange ${entry#uidrange6 }"
                ;;
        esac
    done < "$state_file"
    if [ -z "$clauses" ] && [ -z "$clauses6" ]; then
        rm -f "$state_file" 2>/dev/null || return 1
        return 0
    fi
    if [ -n "$clauses" ]; then
        pattern="^(${clauses})[[:space:]]+blackhole[[:space:]]*$"
        for n in 1 2 3 4 5 6 7 8 9 10; do
            if ! rules=$("$ip_cmd" -4 rule show 2>/dev/null); then
                echo "TunnelSats: ERROR: unable to read IPv4 policy rules while releasing emergency blackhole rules" >&2
                return 1
            fi
            line=$(printf '%s\n' "$rules" | grep -E "$pattern" | head -n 1 || true)
            [ -n "$line" ] || break
            prio=${line%%:*}
            sel=$(printf '%s\n' "$line" | sed -E 's/^[0-9]+:[[:space:]]+//; s/[[:space:]]+blackhole[[:space:]]*$//; s/^from all uidrange /uidrange /')
            # $sel is two words on purpose ("from <subnet>" / "uidrange <a>-<b>").
            # shellcheck disable=SC2086
            "$ip_cmd" -4 rule del priority "$prio" $sel blackhole 2>/dev/null || break
        done
        if ! rules=$("$ip_cmd" -4 rule show 2>/dev/null); then
            echo "TunnelSats: ERROR: unable to verify removal of emergency blackhole rules" >&2
            return 1
        fi
        if printf '%s\n' "$rules" | grep -Eq "$pattern"; then
            echo "TunnelSats: ERROR: could not remove the emergency blackhole rule(s) at priority 21818/21819; Lightning traffic stays blocked until they are removed" >&2
            return 1
        fi
    fi
    if [ -n "$clauses6" ] && [ -e "${TS_FS_ROOT:-}/proc/net/if_inet6" ]; then
        pattern6="^(${clauses6})[[:space:]]+blackhole[[:space:]]*$"
        for n in 1 2 3 4 5 6 7 8 9 10; do
            if ! rules6=$("$ip_cmd" -6 rule show 2>/dev/null); then
                echo "TunnelSats: ERROR: unable to read IPv6 policy rules while releasing emergency blackhole rules" >&2
                return 1
            fi
            line=$(printf '%s\n' "$rules6" | grep -E "$pattern6" | head -n 1 || true)
            [ -n "$line" ] || break
            prio=${line%%:*}
            sel=$(printf '%s\n' "$line" | sed -E 's/^[0-9]+:[[:space:]]+//; s/[[:space:]]+blackhole[[:space:]]*$//; s/^from all uidrange /uidrange /')
            # shellcheck disable=SC2086
            "$ip_cmd" -6 rule del priority "$prio" $sel blackhole 2>/dev/null || break
        done
        if ! rules6=$("$ip_cmd" -6 rule show 2>/dev/null); then
            echo "TunnelSats: ERROR: unable to verify removal of IPv6 emergency blackhole rules" >&2
            return 1
        fi
        if printf '%s\n' "$rules6" | grep -Eq "$pattern6"; then
            echo "TunnelSats: ERROR: could not remove the IPv6 emergency blackhole rule(s) at priority 21819; Lightning traffic stays blocked until they are removed" >&2
            return 1
        fi
    fi
    if ! rm -f "$state_file" 2>/dev/null; then
        echo "TunnelSats: ERROR: unable to remove emergency blackhole state file ${state_file}" >&2
        return 1
    fi
    return 0
}

# Removes the emergency block (nft table and fallback rules) once a tunnel is verified active.
# $1 = Docker tunnel subnet (default 10.9.9.0/25), $2 = optional host uid (retained for CLI compatibility).
# Returns 1 if the emergency block could not be verified as removed.
ts_release_failclosed() {
    local subnet="${1:-10.9.9.0/25}" host_uid="${2:-}"
    if command -v nft >/dev/null 2>&1; then
        nft delete table inet tunnelsats_failclosed 2>/dev/null || true
        nft delete table ip tunnelsats_failclosed 2>/dev/null || true
        if ts_failclosed_nft_verified "$subnet" "$host_uid" || nft list table ip tunnelsats_failclosed >/dev/null 2>&1; then
            echo "TunnelSats: ERROR: could not remove emergency nft table tunnelsats_failclosed" >&2
            return 1
        fi
    fi
    ts_release_failclosed_rules
}

# Docker tunnel subnet for ts_arm_failclosed / ts_release_failclosed: inspects docker-tunnelsats
# on Docker platforms and falls back to 10.9.9.0/25.
resolve_failclosed_subnet() {
    local subnet=""
    if [[ "$PLATFORM" == "umbrel" ]] && command -v docker >/dev/null 2>&1; then
        subnet=$(docker network inspect "docker-tunnelsats" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null | awk '{print $1}')
    fi
    echo "${subnet:-10.9.9.0/25}"
}

# Host uid argument for ts_arm_failclosed: "" on Docker platforms (no host daemon to cover),
# the node user's uid on systemd platforms, or "unresolved" if it is unknown or root (the
# fallback then reports that it cannot cover the host daemon instead of blocking root).
resolve_failclosed_host_uid() {
    if [[ "$PLATFORM" == "umbrel" ]]; then
        echo ""
        return 0
    fi
    local uid=""
    [[ -n "$node_user" ]] && uid=$(id -u "$node_user" 2>/dev/null || true)
    if [[ "$uid" =~ ^[0-9]+$ ]] && [[ "$uid" != "0" ]]; then
        echo "$uid"
    else
        echo "unresolved"
    fi
}

route_guard_path() {
    echo "${WG_DIR:-/etc/wireguard}/tunnelsats-route-guard.sh"
}

# Generates the route guard executed by the wg-quick PostUp/PostDown hooks:
#   check IFACE [SUBNET] [HOST_UID]
#                         first PostUp hook: if table 51820 holds foreign routes or cannot be
#                         read, refuse to start and arm the emergency fail-closed block (nft, or
#                         the blackhole ip rule fallback; HOST_UID as in ts_arm_failclosed_rules).
#                         exit 1 = refused, block armed and verified;
#                         exit 3 = refused, neither nft nor the fallback could be armed
#   clean IFACE           remove only TunnelSats-owned routes from table 51820
#   release [SUBNET] [HOST_UID]
#                         remove the emergency fail-closed block (last PostUp hook)
# The guard is replaced atomically (temp file + rename): a failed write leaves the previous
# guard in place, so a rolled-back config that calls it keeps working.
write_route_guard_script() {
    local guard tmp
    guard=$(route_guard_path)
    mkdir -p "$(dirname "$guard")" 2>/dev/null || true
    tmp=$(mktemp "${guard}.XXXXXX") || return 1
    if ! {
        echo '#!/bin/bash'
        echo '# Generated by tunnelsats.sh - ownership-scoped management of routing table 51820.'
        echo '# Never flushes table 51820; foreign routes are preserved and cause a fail-closed refusal.'
        declare -f ts_table51820_routes ts_table51820_filter_foreign ts_table51820_foreign_routes ts_table51820_remove_owned \
            ts_failclosed_state_file ts_record_failclosed_rule ts_failclosed_nft_verified \
            ts_arm_failclosed_nft ts_failclosed_rules_verified ts_arm_failclosed_rules \
            ts_arm_failclosed ts_release_failclosed_rules ts_release_failclosed
        cat <<'GUARD'
# Refuses the tunnel start ($1 = reason, $2 = optional details). Never returns.
refuse_start() {
    if ts_arm_failclosed "$subnet" "$host_uid"; then
        echo "TunnelSats: $1; refusing to start ${iface}. Emergency fail-closed block armed and verified: Lightning traffic is blocked." >&2
        [ -n "${2:-}" ] && printf '%s\n' "$2" >&2
        exit 1
    fi
    echo "TunnelSats: $1; refusing to start ${iface}. WARNING: emergency fail-closed block could NOT be armed (nft and the blackhole ip rule fallback both failed): Lightning traffic is NOT blocked. Stop the Lightning daemon until the tunnel is up." >&2
    [ -n "${2:-}" ] && printf '%s\n' "$2" >&2
    exit 3
}

action="${1:-}"
case "$action" in
    check)
        iface="${2:?interface required}"
        subnet="${3:-}"
        host_uid="${4:-}"
        if ! foreign=$(ts_table51820_foreign_routes "$iface"); then
            refuse_start "routing table 51820 could not be verified"
        fi
        if [ -n "$foreign" ]; then
            refuse_start "routing table 51820 contains routes not owned by ${iface}" "$foreign"
        fi
        ;;
    clean)
        ts_table51820_remove_owned "${2:?interface required}"
        ;;
    arm)
        ts_arm_failclosed "${2:-10.9.9.0/25}" "${3:-}" || exit 1
        ;;
    release)
        ts_release_failclosed "${2:-}" "${3:-}" || exit 1
        ;;
    *)
        echo "usage: $0 check IFACE [SUBNET] [HOST_UID] | clean IFACE | arm [SUBNET] [HOST_UID] | release [SUBNET] [HOST_UID]" >&2
        exit 2
        ;;
esac
exit 0
GUARD
    } > "$tmp" || ! chmod 755 "$tmp" || ! mv -f "$tmp" "$guard"; then
        rm -f "$tmp"
        return 1
    fi
    return 0
}

stop_lightning_daemon_for_safe_restart() {
    # Identify and stop running Lightning daemon BEFORE any route/network mutation,
    # independently of WireGuard unit state (fail-closed leak prevention).
    if [[ "$PLATFORM" == "umbrel" ]]; then
        local running_cids
        running_cids=$(get_lightning_docker_containers)
        if [[ "$(printf '%s\n' $running_cids | grep -c . || true)" -gt 1 ]]; then
            print_error "Multiple running ${LN_IMPL} daemon containers found ($(echo $running_cids)). Only one can own the tunnel IP ${TUNNEL_CONTAINER_IP}. Aborting before any changes."
            exit 1
        fi
        if [[ -n "$running_cids" ]]; then
            print_info "Stopping ${LN_IMPL} daemon container for leak-proof tunnel restart..."
            if ! docker stop $running_cids >/dev/null 2>&1; then
                print_error "Failed to safely stop ${LN_IMPL} container. Aborting before network/route changes to prevent traffic leaks."
                exit 1
            fi
            stopped_docker_containers="$running_cids"
            print_success "${LN_IMPL} daemon container stopped (Leak-proof mode)"
        fi
    else
        local service_name="${LN_IMPL}"
        [[ "$LN_IMPL" == "cln" ]] && service_name="lightningd"
        if [[ "$LN_IMPL" == "lit" ]]; then
            service_name="litd"
            systemctl list-units --type=service 2>/dev/null | grep -q "lit.service" && service_name="lit"
        fi

        local target_service=""
        if [[ -n "$service_name" ]] && systemctl is-active --quiet "${service_name}.service" 2>/dev/null; then
            target_service="${service_name}.service"
        elif systemctl is-active --quiet lnd.service 2>/dev/null; then
            target_service="lnd.service"
        elif systemctl is-active --quiet lightningd.service 2>/dev/null; then
            target_service="lightningd.service"
        fi

        if [[ -n "$target_service" ]]; then
            print_info "Stopping ${target_service} for leak-proof tunnel restart..."
            if systemctl stop "${target_service}"; then
                restarted_systemd_service="${target_service}"
                print_success "${target_service} stopped (Leak-proof mode)"
            else
                print_error "Failed to stop ${target_service} safely. Aborting before network/route changes to prevent traffic leaks."
                exit 1
            fi
        fi
    fi

    # If WireGuard interface is currently active, stop it before updating configuration
    if [[ -n "$WG_INTERFACE" ]] && systemctl is-active --quiet "wg-quick@${WG_INTERFACE}"; then
        print_info "Stopping active WireGuard service (${WG_INTERFACE}) before updating configuration..."
        if ! systemctl stop "wg-quick@${WG_INTERFACE}"; then
            print_error "Failed to safely stop active WireGuard service (${WG_INTERFACE}). Aborting to prevent routing conflicts."
            exit 1
        fi
        stopped_wireguard_interface="$WG_INTERFACE"
        print_success "WireGuard service stopped"
    fi
}

setup_docker_network() {
    print_info "Setting up Docker tunnelsats network..."
    
    # Create Docker network
    local dockersubnet="10.9.9.0/25"
    if ! docker network ls 2>/dev/null | grep -q "docker-tunnelsats"; then
        docker network create "docker-tunnelsats" --subnet $dockersubnet \
            -o "com.docker.network.driver.mtu"="1420" &>/dev/null && \
            print_success "Docker network created" || \
            { print_error "Failed to create Docker network"; exit 1; }
    else
        print_info "Docker network already exists"
    fi
    
    # Clean routing tables from prior failed starts, strictly scoped to TunnelSats ownership
    check_and_cleanup_routing_table "$WG_INTERFACE"
    
    # Attach exactly one resolved lightning daemon to docker-tunnelsats with the static tunnel IP.
    # Only one container can own 10.9.9.9; stale stopped leftovers must not compete for it.
    local target_cid
    if ! target_cid=$(select_tunnel_target_container); then
        exit 1
    fi
    if [[ -z "$target_cid" ]]; then
        print_error "No ${LN_IMPL} daemon container found to attach to docker-tunnelsats"
        exit 1
    fi
    if ! attach_container_to_tunnel_network "$target_cid"; then
        exit 1
    fi
    tunnel_target_container="$target_cid"

    # Create Docker network monitor script with shared container resolver regex
    local container_regex
    if [[ "$LN_IMPL" == "cln" ]]; then
        container_regex="$CLN_CONTAINER_REGEX"
    else
        container_regex="$LND_CONTAINER_REGEX"
    fi

    local wg_dir="${WG_DIR:-/etc/wireguard}"
    local systemd_dir="${SYSTEMD_DIR:-/etc/systemd/system}"
    mkdir -p "$wg_dir" "$systemd_dir" 2>/dev/null || true

    local monitor_script=""
    IFS= read -r -d '' monitor_script <<'EOF' || true
#!/bin/sh
# Generated by tunnelsats.sh - keeps exactly one Lightning daemon attached to docker-tunnelsats at __TUNNEL_IP__
sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || true
sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true
NET="docker-tunnelsats"
TUNNEL_IP="__TUNNEL_IP__"
if [ "$(docker network ls 2> /dev/null | grep -c "$NET")" -eq 0 ]; then
  if ! docker network create "$NET" --subnet "10.9.9.0/25" -o "com.docker.network.driver.mtu"="1420" > /dev/null; then
    exit 1
  fi
fi

list_ln() {
  docker ps $1 --format "{{.ID}} {{.Names}}" 2>/dev/null | grep -Ei '__CONTAINER_REGEX__' | grep -Eiv '__EXCLUDE_REGEX__' | awk '{print $1}'
}
tunnel_state() {
  docker inspect -f '__INSPECT_FMT__' "$1" 2>/dev/null
}

running=$(list_ln "")
if [ "$(printf '%s\n' $running | grep -c .)" -gt 1 ]; then
  echo "Multiple running Lightning daemon containers; refusing to share $TUNNEL_IP" >&2
  exit 1
fi
target="$running"
if [ -z "$target" ]; then
  # No daemon running (e.g. installer restart window): never move the tunnel IP away from its current owner
  for c in $(list_ln "-a"); do
    case " $(tunnel_state "$c") " in *" $TUNNEL_IP "*) exit 0 ;; esac
  done
  target=$(list_ln "-a" | head -n 1)
fi
[ -z "$target" ] && exit 0

state=$(tunnel_state "$target")
case " $state " in *" $TUNNEL_IP "*) exit 0 ;; esac
if [ -n "$state" ]; then
  docker network disconnect -f "$NET" "$target" > /dev/null 2>&1 || exit 1
fi

for other in $(list_ln "-a"); do
  [ "$other" = "$target" ] && continue
  case " $(tunnel_state "$other") " in
    *" $TUNNEL_IP "*)
      [ "$(docker inspect -f '{{.State.Running}}' "$other" 2>/dev/null)" = "true" ] && exit 1
      docker network disconnect -f "$NET" "$other" > /dev/null 2>&1 || exit 1
      ;;
  esac
done

docker network connect --ip "$TUNNEL_IP" "$NET" "$target" > /dev/null 2>&1 || exit 1
exit 0
EOF
    monitor_script="${monitor_script//__CONTAINER_REGEX__/"$container_regex"}"
    monitor_script="${monitor_script//__EXCLUDE_REGEX__/"$LN_CONTAINER_EXCLUDE_REGEX"}"
    monitor_script="${monitor_script//__INSPECT_FMT__/"$TUNNEL_NET_INSPECT_FMT"}"
    monitor_script="${monitor_script//__TUNNEL_IP__/"$TUNNEL_CONTAINER_IP"}"
    printf '%s' "$monitor_script" > "$wg_dir/tunnelsats-docker-network.sh"
    
    chmod +x "$wg_dir/tunnelsats-docker-network.sh"
    bash "$wg_dir/tunnelsats-docker-network.sh" &>/dev/null
    
    # Create systemd service and timer
    cat > "$systemd_dir/tunnelsats-docker-network.service" <<'EOF'
[Unit]
Description=Adding Lightning Container to the tunnel
StartLimitInterval=200
StartLimitBurst=5
[Service]
Type=oneshot
ExecStart=/bin/bash /etc/wireguard/tunnelsats-docker-network.sh
[Install]
WantedBy=multi-user.target
EOF
    
    cat > "$systemd_dir/tunnelsats-docker-network.timer" <<'EOF'
[Unit]
Description=5min timer for tunnelsats-docker-network.service
[Timer]
OnBootSec=60
OnUnitActiveSec=60
Persistent=true
[Install]
WantedBy=timers.target
EOF
    
    systemctl daemon-reload
    systemctl enable tunnelsats-docker-network.service &>/dev/null
    systemctl start tunnelsats-docker-network.service &>/dev/null
    systemctl enable tunnelsats-docker-network.timer &>/dev/null
    systemctl start tunnelsats-docker-network.timer &>/dev/null
    
    print_success "Docker network configured"
}

setup_dns_resolver() {
    local interface="$1"
    print_info "Configuring DNS resolver watchdog for ${interface}..."
    
    # Create resolver script
    cat > /etc/wireguard/tunnelsats-resolve-dns-wg.sh << 'EOF'
#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2015-2020 Jason A. Donenfeld <Jason@zx2c4.com>. All Rights Reserved.
set -e
shopt -s nocasematch
shopt -s extglob
export LC_ALL=C

CONFIG_FILE="$1"
[[ $CONFIG_FILE =~ ^[a-zA-Z0-9_=+.-]{1,15}$ ]] && CONFIG_FILE="/etc/wireguard/$CONFIG_FILE.conf"
[[ $CONFIG_FILE =~ /?([a-zA-Z0-9_=+.-]{1,15})\.conf$ ]]
INTERFACE="${BASH_REMATCH[1]}"

process_peer() {
    [[ $PEER_SECTION -ne 1 || -z $PUBLIC_KEY || -z $ENDPOINT ]] && return 0
    [[ $(wg show "$INTERFACE" latest-handshakes) =~ ${PUBLIC_KEY//+/\\+}\	([0-9]+) ]] || return 0
    (( ($EPOCHSECONDS - ${BASH_REMATCH[1]}) > 135 )) || return 0
    wg set "$INTERFACE" peer "$PUBLIC_KEY" endpoint "$ENDPOINT"
    reset_peer_section
}

reset_peer_section() {
    PEER_SECTION=0
    PUBLIC_KEY=""
    ENDPOINT=""
}

reset_peer_section
while read -r line || [[ -n $line ]]; do
    stripped="${line%%\#*}"
    key="${stripped%%=*}"; key="${key##*([[:space:]])}"; key="${key%%*([[:space:]])}"
    value="${stripped#*=}"; value="${value##*([[:space:]])}"; value="${value%%*([[:space:]])}"
    [[ $key == "["* ]] && { process_peer; reset_peer_section; }
    [[ $key == "[Peer]" ]] && PEER_SECTION=1
    if [[ $PEER_SECTION -eq 1 ]]; then
        case "$key" in
        PublicKey) PUBLIC_KEY="$value"; continue ;;
        Endpoint) ENDPOINT="$value"; continue ;;
        esac
    fi
done < "$CONFIG_FILE"
process_peer
EOF
    
    chmod +x /etc/wireguard/tunnelsats-resolve-dns-wg.sh
    
    # Create systemd service
    cat > /etc/systemd/system/tunnelsats-resolve-dns-wg.service << EOF
[Unit]
Description=tunnelsats-resolve-dns-wg: Trigger Resolve DNS in case Handshake is older than 2 minutes
[Service]
Type=oneshot
ExecStart=/bin/bash /etc/wireguard/tunnelsats-resolve-dns-wg.sh ${interface}
[Install]
WantedBy=multi-user.target
EOF

    # Create timer
    cat > /etc/systemd/system/tunnelsats-resolve-dns-wg.timer << EOF
[Unit]
Description=30sec timer for tunnelsats-resolve-dns-wg.service
[Timer]
OnBootSec=30
OnUnitActiveSec=30
Persistent=true
[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable tunnelsats-resolve-dns-wg.service &>/dev/null || true
    systemctl enable tunnelsats-resolve-dns-wg.timer &>/dev/null || true
    systemctl start tunnelsats-resolve-dns-wg.timer &>/dev/null || true
    
    print_success "DNS resolver watchdog configured"
}

configure_lightning() {
    print_info "Configuring ${LN_IMPL} for tunneling..."
    
    local service_file=""
    local service_dir=""
    case "$LN_IMPL" in
        lnd)
            service_file="/etc/systemd/system/lnd.service"
            service_dir="/etc/systemd/system/lnd.service.d"
            ;;
        cln)
            service_file="/etc/systemd/system/lightningd.service"
            service_dir="/etc/systemd/system/lightningd.service.d"
            ;;
        lit)
            service_file="/etc/systemd/system/litd.service"
            [[ ! -f "$service_file" ]] && service_file="/etc/systemd/system/lit.service"
            service_dir="${service_file}.d"
            ;;
    esac

    # 1. Backup original service file before any modifications
    if [[ -f "$service_file" ]] && [[ ! -f "${service_file}.bak" ]]; then
        cp "$service_file" "${service_file}.bak"
        print_success "Created backup of original service file: ${service_file}.bak"
    fi

    # 2. Deactivate RaspiBlitz config checks if present
    if [[ "$PLATFORM" == "raspiblitz" ]]; then
        if [[ "$LN_IMPL" == "lnd" ]]; then
            # Comment out the ExecStartPre check in the service file
            [[ -f "$service_file" ]] && sed -i '/lnd\.check\.sh/ s/^ExecStartPre=/#ExecStartPre=/' "$service_file" 2>/dev/null || true
            # Also disable any separate health service if present
            systemctl stop lnd-health.service &>/dev/null || true
            systemctl disable lnd-health.service &>/dev/null || true
            print_info "RaspiBlitz lnd.check deactivated in service file"
        elif [[ "$LN_IMPL" == "cln" ]]; then
            [[ -f "$service_file" ]] && sed -i '/cl\.check\.sh/ s/^ExecStartPre=/#ExecStartPre=/' "$service_file" 2>/dev/null || true
            systemctl stop cl-health.service &>/dev/null || true
            systemctl disable cl-health.service &>/dev/null || true
            print_info "RaspiBlitz cl.check deactivated in service file"
        fi
    fi
    
    # For non-Docker setups, modify systemd service to use cgexec
    if [[ "$PLATFORM" != "umbrel" ]]; then
        setup_cgroups

        # 1. Create Drop-in Dependency
        if [[ -n "$service_dir" ]]; then
            if [[ ! -d "$service_dir" ]]; then mkdir -p "$service_dir"; fi
            
            cat > "${service_dir}/tunnelsats-cgroup.conf" << EOF
#Don't edit this file its generated by tunnelsats scripts
[Unit]
Description=${LN_IMPL} service - powered by tunnelsats
Wants=tunnelsats-create-cgroup.service
After=tunnelsats-create-cgroup.service
Wants=wg-quick@${WG_INTERFACE}.service
After=wg-quick@${WG_INTERFACE}.service
EOF
        fi
        
        # 2. Modify ExecStart to use cgexec
        if [[ -f "$service_file" ]]; then
            if ! grep -q "cgexec" "$service_file"; then
                sed -i 's|ExecStart=|ExecStart=/usr/bin/cgexec -g net_cls:splitted_processes |g' "$service_file"
                print_success "${LN_IMPL} service updated to use cgroup"
            else
                print_info "${LN_IMPL} service already uses cgroup"
            fi
        fi
        
        # 3. Handle RaspiBlitz API (blitzapi) dependency if present
        if [[ -f /etc/systemd/system/blitzapi.service ]]; then
            if [[ ! -d /etc/systemd/system/blitzapi.service.d ]]; then
                mkdir -p /etc/systemd/system/blitzapi.service.d
            fi
            cat > /etc/systemd/system/blitzapi.service.d/tunnelsats-wg.conf << EOF
#Don't edit this file its generated by tunnelsats scripts
[Unit]
Description=blitzapi needs the wg service before it can start successfully
Requires=wg-quick@${WG_INTERFACE}.service
After=wg-quick@${WG_INTERFACE}.service
EOF
             print_success "Added blitzapi dependency"
        fi

        systemctl daemon-reload
    fi
    
    # Create splitting processes script (non-Docker)
    if [[ "$PLATFORM" != "umbrel" ]]; then
        cat > /etc/wireguard/tunnelsats-splitting-processes.sh << 'EOF'
#!/bin/sh
# add Lightning pid(s) to cgroup
pgrep -x lnd | xargs -I % sh -c 'echo % >> /sys/fs/cgroup/net_cls/splitted_processes/tasks' &> /dev/null
pgrep -x lightningd | xargs -I % sh -c 'echo % >> /sys/fs/cgroup/net_cls/splitted_processes/tasks' &> /dev/null
pgrep -x litd | xargs -I % sh -c 'echo % >> /sys/fs/cgroup/net_cls/splitted_processes/tasks' &> /dev/null
count=$(cat /sys/fs/cgroup/net_cls/splitted_processes/tasks | wc -l)
if [ $count -eq 0 ];then
  echo "> no available lightning processes available for tunneling"
else
  echo "> ${count} Process(es) successfully excluded"
fi
EOF
        chmod +x /etc/wireguard/tunnelsats-splitting-processes.sh
        
        # Create systemd service for splitting processes
        cat > /etc/systemd/system/tunnelsats-splitting-processes.service << EOF
[Unit]
Description=Adding Lightning Process to the tunnel
[Service]
Type=oneshot
ExecStart=/bin/bash /etc/wireguard/tunnelsats-splitting-processes.sh
[Install]
WantedBy=multi-user.target
EOF
        
        # Create timer
        cat > /etc/systemd/system/tunnelsats-splitting-processes.timer << EOF
[Unit]
Description=1min timer for tunnelsats-splitting-processes.service
[Timer]
OnBootSec=10
OnUnitActiveSec=10
Persistent=true
[Install]
WantedBy=timers.target
EOF
        
        systemctl daemon-reload
        systemctl enable tunnelsats-splitting-processes.service &>/dev/null
        systemctl start tunnelsats-splitting-processes.service &>/dev/null
        systemctl enable tunnelsats-splitting-processes.timer &>/dev/null
        systemctl start tunnelsats-splitting-processes.timer &>/dev/null
        
        print_success "Splitting processes service configured"
    fi
    
    print_success "${LN_IMPL} configured for tunneling"
}



enable_services() {
    if [[ -z "$WG_INTERFACE" ]]; then
        print_error "WireGuard interface not determined"
        exit 1
    fi

    print_info "Enabling WireGuard service (${WG_INTERFACE})..."
    
    systemctl daemon-reload > /dev/null 2>&1
    
    local out
    if out=$(systemctl enable wg-quick@${WG_INTERFACE} 2>&1); then
        print_success "WireGuard service enabled"
    else
        print_error "Failed to enable service:"
        echo "$out"
        exit 1
    fi
    
    # Ensure kernel routing table 51820 is clean before starting, scoped to TunnelSats ownership
    check_and_cleanup_routing_table "$WG_INTERFACE"

    print_info "Starting WireGuard..."
    local failclosed_subnet failclosed_uid
    failclosed_subnet=$(resolve_failclosed_subnet)
    failclosed_uid=$(resolve_failclosed_host_uid)
    if out=$(systemctl start wg-quick@${WG_INTERFACE} 2>&1); then
        print_success "WireGuard service started"
        # Ensure any temporary emergency failclosed block is cleared once tunnel is active
        if ! ts_release_failclosed "$failclosed_subnet" "$failclosed_uid"; then
            print_error "Emergency fail-closed block could NOT be released after starting WireGuard."
            exit 1
        fi
    else
        print_error "Failed to start service:"
        echo "$out"
        
        # Arm the emergency fail-closed block (nft, or the blackhole ip rule fallback) so no
        # clearnet leak is possible. Covers local host traffic and forwarded Docker traffic.
        if ! ts_arm_failclosed "$failclosed_subnet" "$failclosed_uid"; then
            print_error "Emergency fail-closed block could NOT be armed (nft and the blackhole ip rule fallback both failed): Lightning traffic is NOT blocked. Keep the Lightning daemon stopped until the tunnel is up."
        fi

        # Help user troubleshoot
        echo ""
        print_info "Checking status..."
        systemctl status wg-quick@${WG_INTERFACE} --no-pager -l || true
        if [[ -n "$restarted_systemd_service" ]] || [[ -n "$stopped_docker_containers" ]]; then
            echo ""
            print_warning "Lightning service was kept stopped to prevent clearnet IP leakage."
        fi
        exit 1
    fi

    # Restart Lightning node under the active tunnel if it was stopped for the restart
    if ! restart_stopped_lightning_daemon; then
        exit 1
    fi
}

# Restarts the Lightning daemon that stop_lightning_daemon_for_safe_restart stopped.
# Returns 1 on failure. Callers must only invoke this once a tunnel is verified active.
restart_stopped_lightning_daemon() {
    if [[ -n "$stopped_docker_containers" ]]; then
        print_info "Restarting ${LN_IMPL} daemon container under tunnel..."
        if docker start ${stopped_docker_containers} >/dev/null 2>&1; then
            print_success "${LN_IMPL} daemon container restarted"
        else
            print_error "Failed to restart ${LN_IMPL} daemon container"
            return 1
        fi
    elif [[ -n "$restarted_systemd_service" ]]; then
        print_info "Restarting ${restarted_systemd_service} under tunnel..."
        if systemctl start "${restarted_systemd_service}"; then
            print_success "${restarted_systemd_service} restarted"
        else
            print_error "Failed to restart ${restarted_systemd_service}"
            return 1
        fi
    fi
    return 0
}

# EXIT trap armed by cmd_install between the leak-proof daemon stop and enable_services.
# On failure it restores the previous WireGuard config and tunnel, verifies the tunnel against
# real kernel state, and only then restarts the daemon. Without a verified tunnel the daemon
# stays stopped (fail-closed) to avoid clearnet IP leakage.
rollback_failed_install() {
    local rc=$?
    trap - EXIT
    [[ "$rc" -eq 0 ]] && return 0

    if [[ -z "$stopped_docker_containers" ]] && [[ -z "$restarted_systemd_service" ]]; then
        exit "$rc"
    fi

    echo "" >&2
    print_warning "Installation failed before the new tunnel was started. Attempting to restore the previous tunnel..."

    if [[ -n "$WG_CONFIG_BACKUP" ]] && [[ -f "$WG_CONFIG_BACKUP" ]] && [[ -n "$WG_CONFIG_PATH" ]]; then
        if mv -f "$WG_CONFIG_BACKUP" "$WG_CONFIG_PATH"; then
            print_info "Restored previous WireGuard config: ${WG_CONFIG_PATH}"
        else
            print_error "Failed to restore previous WireGuard config from ${WG_CONFIG_BACKUP}. Lightning daemon kept stopped to prevent clearnet IP leakage."
            exit "$rc"
        fi
    fi

    local restore_iface="$stopped_wireguard_interface"
    if [[ -z "$restore_iface" ]] && [[ -n "$WG_INTERFACE" ]] && systemctl is-active --quiet "wg-quick@${WG_INTERFACE}" 2>/dev/null; then
        # The previous tunnel was never stopped (e.g. stopping it failed) and is still up
        restore_iface="$WG_INTERFACE"
    fi

    if [[ -z "$restore_iface" ]]; then
        print_warning "No previously active TunnelSats tunnel to restore. Lightning daemon kept stopped to prevent clearnet IP leakage."
        print_warning "Fix the error above and re-run the installer."
        exit "$rc"
    fi

    if ! systemctl is-active --quiet "wg-quick@${restore_iface}" 2>/dev/null; then
        if ! systemctl start "wg-quick@${restore_iface}" >/dev/null 2>&1; then
            print_error "Failed to restart previous tunnel (${restore_iface}). Lightning daemon kept stopped to prevent clearnet IP leakage."
            exit "$rc"
        fi
    fi
    if ! wg show "$restore_iface" >/dev/null 2>&1; then
        print_error "Previous tunnel (${restore_iface}) is not present in the kernel. Lightning daemon kept stopped to prevent clearnet IP leakage."
        exit "$rc"
    fi
    if ! ip rule show 2>/dev/null | grep -Eq "lookup 51820([[:space:]]|$)"; then
        print_error "TunnelSats policy routing (table 51820) is not active. Lightning daemon kept stopped to prevent clearnet IP leakage."
        exit "$rc"
    fi
    if [[ -n "$stopped_docker_containers" ]] && ! attach_container_to_tunnel_network "$stopped_docker_containers"; then
        print_error "Lightning container could not be attached to docker-tunnelsats. Lightning daemon kept stopped to prevent clearnet IP leakage."
        exit "$rc"
    fi
    print_success "Previous tunnel (${restore_iface}) restored"

    if restart_stopped_lightning_daemon; then
        print_warning "Lightning daemon restarted on the previous tunnel. The new installation did NOT complete."
    fi
    exit "$rc"
}

verify_installation() {
    if systemctl is-active --quiet wg-quick@${WG_INTERFACE}; then
        print_success "WireGuard service is running"
    else
        print_error "WireGuard service is not running"
        exit 1
    fi

    # Verify the Lightning daemon container(s) on docker-tunnelsats:
    # - containers the installer stopped and restarted must be running with live IP 10.9.9.9
    # - the selected target that was already stopped before installation stays stopped and
    #   only needs its static 10.9.9.9 attachment (it gets the tunnel IP when the user starts it)
    if [[ "$PLATFORM" == "umbrel" ]]; then
        if command -v docker >/dev/null 2>&1; then
            local target="$tunnel_target_container"
            if [[ -z "$target" ]]; then
                if ! target=$(select_tunnel_target_container); then
                    exit 1
                fi
            fi
            local verify_cids
            verify_cids=$(printf '%s\n' $stopped_docker_containers $target | awk 'NF && !seen[$0]++')
            if [[ -z "$verify_cids" ]]; then
                print_error "No Lightning daemon container found during verification"
                exit 1
            fi
            local cid
            for cid in $verify_cids; do
                local restarted_by_installer=0
                [[ " $(echo $stopped_docker_containers) " == *" ${cid} "* ]] && restarted_by_installer=1

                if docker ps -q --no-trunc | grep -q "^${cid}"; then
                    local container_ip
                    container_ip=$(docker inspect -f '{{with index .NetworkSettings.Networks "docker-tunnelsats"}}{{.IPAddress}}{{end}}' "$cid" 2>/dev/null)
                    if [[ "$container_ip" != "$TUNNEL_CONTAINER_IP" ]]; then
                        print_error "Container (${cid}) is not attached to docker-tunnelsats with expected IP ${TUNNEL_CONTAINER_IP} (found: ${container_ip:-none})"
                        exit 1
                    fi
                    print_success "Container (${cid}) verified running on docker-tunnelsats (${TUNNEL_CONTAINER_IP})"
                elif [[ "$restarted_by_installer" -eq 1 ]]; then
                    print_error "Restarted container (${cid}) is not running"
                    exit 1
                else
                    local tunnel_state
                    tunnel_state=$(docker inspect -f "$TUNNEL_NET_INSPECT_FMT" "$cid" 2>/dev/null || true)
                    if [[ " $tunnel_state " != *" ${TUNNEL_CONTAINER_IP} "* ]]; then
                        print_error "Stopped container (${cid}) is not attached to docker-tunnelsats with static IP ${TUNNEL_CONTAINER_IP}"
                        exit 1
                    fi
                    print_success "Container (${cid}) attached to docker-tunnelsats (${TUNNEL_CONTAINER_IP}); it was stopped before installation and was left stopped"
                fi
            done
        fi
    elif [[ -n "$restarted_systemd_service" ]]; then
        if ! systemctl is-active --quiet "${restarted_systemd_service}"; then
            print_error "${restarted_systemd_service} is not running after restart"
            exit 1
        fi
    fi
    
    if wg show ${WG_INTERFACE} &>/dev/null; then
        print_success "WireGuard tunnel is active"
    else
        print_warning "WireGuard tunnel not detected (may be starting)"
    fi

    # Pre-flight Listening Check (Non-Docker)
    if [[ "$PLATFORM" != "umbrel" ]] && [[ -n "$LN_IMPL" ]]; then
        local port=9735
        if ss -tulpn | grep -q "127.0.0.1:${port}"; then
            echo ""
            print_warning "POSSIBLE CONFIG ISSUE: ${LN_IMPL^^} is only listening on 127.0.0.1"
            print_warning "It will NOT accept inbound traffic from the tunnel."
            print_warning "Ensure 'listen=0.0.0.0:${port}' is set in your config."
        fi
    fi
}

# Prints, after the standard uninstall, the command that takes the former VPN address out of LND's
# node announcement: LND 0.20 and later announces the addresses it saved again at every start when its
# config sets no externalip, and this uninstall does not start LND again. $1 = 1 on Docker (Umbrel),
# $2 = the LND container (may be empty), then the TunnelSats configs; the address is the endpoint's
# IPv4 (looked up for at most TS_V_RESOLVE_TIMEOUT seconds, as in verify) with the forwarded port.
ts_print_announce_command() {
    local docker="$1" container="${2:-<lnd container>}" conf addr prefix="lncli"
    local -a addrs=()
    shift 2
    for conf in "$@"; do
        ts_v_read_endpoint "$conf"
        if [[ -n "$TS_V_ENDPOINT_IP" ]] && valid_ipv4 "$TS_V_ENDPOINT_IP" && [[ -n "$TS_V_VPN_PORT" ]]; then
            addr="${TS_V_ENDPOINT_IP}:${TS_V_VPN_PORT}"
            if ! ts_in_list "$addr" "${addrs[*]}"; then
                addrs+=("$addr")
            fi
        fi
    done
    if [[ "$docker" -eq 1 ]]; then
        prefix="docker exec ${container} lncli"
    fi
    echo "LND 0.20 and later keeps announcing the addresses it saved, the former VPN address too."
    echo "Once LND runs again, remove that address from its node announcement:"
    if [[ ${#addrs[@]} -eq 0 ]]; then
        echo -e "  ${BOLD}${prefix} peers updatenodeannouncement --address_remove <ip>:<port>${NC}"
        echo "  (the address that lncli getinfo lists under uris)"
    fi
    for addr in "${addrs[@]}"; do
        echo -e "  ${BOLD}${prefix} peers updatenodeannouncement --address_remove ${addr}${NC}"
    done
}

cmd_uninstall() {
    print_header "Uninstall Wizard"
    
    echo ""
    print_warning "This will STOP your Lightning node and remove TunnelSats!"
    echo ""
    echo "This uninstaller will:"
    echo "  • Stop Lightning services"
    echo "  • Remove TunnelSats configurations"
    echo "  • Restore backup files (LND/CLN configs)"
    echo "  • Clean up systemd services"
    echo "  • Restore hybrid mode to Tor-only"
    echo ""
    
    # Triple confirmation (--yes answers it; nothing has been changed before this point)
    while true; do
        ts_confirm answer "CAUTION! Uninstalling TunnelSats will force your lightning process to stop. Do you really want to proceed? (Y/N) "
        case $answer in
            [yY]*) echo "> OK, proceeding..."; echo; break ;;
            [nN]*) echo "> Exiting process."; exit 1 ;;
            *) echo "Just enter Y or N, please." ;;
        esac
    done
    
    # 1. Detect Platform & Implementation for Cleanup
    local umbrel_user=${SUDO_USER:-${USER}}
    detect_platform
    detect_ln_implementation
    local ln_impl="${LN_IMPL}"
    local is_docker=0
    local home_dir=""
    local lnd_container=""

    if [[ "$PLATFORM" == "umbrel" ]]; then
        is_docker=1
        home_dir="/home/$umbrel_user"
    fi

    # 2. Stop Services & Clean Dependencies
    print_step 1 6 "Stopping Lightning services..."
    
    if [[ "$ln_impl" == "lnd" ]]; then
        if [[ $is_docker -eq 1 ]]; then
             local filter_name="_lnd"
             print_info "Stopping ${ln_impl} containers..."
             local container_ids=$(docker ps --filter "name=${filter_name}" --format "{{.ID}}")
             if [[ -n "$container_ids" ]]; then
                 for id in ${container_ids}; do
                     local c_name=$(docker inspect --format '{{.Name}}' "$id" | sed 's/^\///')
                     lnd_container="${lnd_container:-$c_name}"
                     print_info "Stopping $c_name ... (this may take a few seconds)"
                     echo -n "" >&2
                     docker stop "$id" &>/dev/null
                     docker network disconnect docker-tunnelsats "$id" &>/dev/null || true
                     print_success "Stopped $c_name"
                     echo "" >&2
                 done
             else
                 print_info "No lightning containers found"
             fi
        elif [[ -f "${TS_FS_ROOT}/etc/systemd/system/lnd.service" ]]; then
             if systemctl is-active lnd.service &>/dev/null; then
                 systemctl stop lnd.service &>/dev/null && print_success "Stopped lnd.service"
             fi
        fi
        
        # Remove dependencies
        if [[ -f "${TS_FS_ROOT}/etc/systemd/system/lnd.service.d/tunnelsats-cgroup.conf" ]]; then
             rm -f "${TS_FS_ROOT}/etc/systemd/system/lnd.service.d/tunnelsats-cgroup.conf" &>/dev/null
             rmdir "${TS_FS_ROOT}/etc/systemd/system/lnd.service.d" &>/dev/null || true
             systemctl daemon-reload &>/dev/null
             print_success "Removed lnd.service dependency"
        fi
        
        # Restore original service file if backup exists
        if [[ -f "${TS_FS_ROOT}/etc/systemd/system/lnd.service.bak" ]]; then
             mv "${TS_FS_ROOT}/etc/systemd/system/lnd.service.bak" "${TS_FS_ROOT}/etc/systemd/system/lnd.service"
             print_success "Restored original lnd.service"
        fi

        # Restore RaspiBlitz health services
        systemctl enable lnd-health.service &>/dev/null || true
        systemctl start lnd-health.service &>/dev/null || true

    elif [[ "$ln_impl" == "cln" ]]; then
        if [[ $is_docker -eq 1 ]]; then
             local filter_name="core-lightning"
             print_info "Stopping ${ln_impl} containers..."
             local container_ids=$(docker ps --filter "name=${filter_name}" --format "{{.ID}}")
             if [[ -n "$container_ids" ]]; then
                 for id in ${container_ids}; do
                     local c_name=$(docker inspect --format '{{.Name}}' "$id" | sed 's/^\///')
                     print_info "Stopping $c_name ... (this may take a few seconds)"
                     echo -n "" >&2
                     docker stop "$id" &>/dev/null
                     docker network disconnect docker-tunnelsats "$id" &>/dev/null || true
                     print_success "Stopped $c_name"
                     echo "" >&2
                 done
             else
                 print_info "No lightning containers found"
             fi
        elif [[ -f "${TS_FS_ROOT}/etc/systemd/system/lightningd.service" ]]; then
             if systemctl is-active lightningd.service &>/dev/null; then
                 systemctl stop lightningd.service &>/dev/null && print_success "Stopped lightningd.service"
             fi
        fi

        # Remove dependencies
        if [[ -f "${TS_FS_ROOT}/etc/systemd/system/lightningd.service.d/tunnelsats-cgroup.conf" ]]; then
             rm -f "${TS_FS_ROOT}/etc/systemd/system/lightningd.service.d/tunnelsats-cgroup.conf" &>/dev/null
             rmdir "${TS_FS_ROOT}/etc/systemd/system/lightningd.service.d" &>/dev/null || true
             systemctl daemon-reload &>/dev/null
             print_success "Removed lightningd.service dependency"
        fi
        
        # Restore original service file if backup exists
        if [[ -f "${TS_FS_ROOT}/etc/systemd/system/lightningd.service.bak" ]]; then
             mv "${TS_FS_ROOT}/etc/systemd/system/lightningd.service.bak" "${TS_FS_ROOT}/etc/systemd/system/lightningd.service"
             print_success "Restored original lightningd.service"
        fi

        # Restore RaspiBlitz health services
        systemctl enable cl-health.service &>/dev/null || true
        systemctl start cl-health.service &>/dev/null || true

    elif [[ "$ln_impl" == "lit" ]]; then
        local lit_unit
        for lit_unit in litd.service lit.service; do
            if [[ -f "${TS_FS_ROOT}/etc/systemd/system/${lit_unit}" ]]; then
                if systemctl is-active "$lit_unit" &>/dev/null; then
                    systemctl stop "$lit_unit" &>/dev/null && print_success "Stopped ${lit_unit}"
                fi
            fi
            if [[ -f "${TS_FS_ROOT}/etc/systemd/system/${lit_unit}.d/tunnelsats-cgroup.conf" ]]; then
                rm -f "${TS_FS_ROOT}/etc/systemd/system/${lit_unit}.d/tunnelsats-cgroup.conf" &>/dev/null
                rmdir "${TS_FS_ROOT}/etc/systemd/system/${lit_unit}.d" &>/dev/null || true
                systemctl daemon-reload &>/dev/null
                print_success "Removed ${lit_unit} dependency"
            fi
            if [[ -f "${TS_FS_ROOT}/etc/systemd/system/${lit_unit}.bak" ]]; then
                mv "${TS_FS_ROOT}/etc/systemd/system/${lit_unit}.bak" "${TS_FS_ROOT}/etc/systemd/system/${lit_unit}"
                print_success "Restored original ${lit_unit}"
            fi
        done
    fi
    echo ""

    # 3. Inspect Hybrid Mode Configuration (read-only: never edit operator config files)
    print_step 2 6 "Checking configuration files..."
    local -a detected_nc_lines=()
    local nc_entry nc_num nc_key nc_val
    if [[ "$ln_impl" == "lnd" ]]; then
        local paths=(
            "${TS_FS_ROOT}/mnt/hdd/lnd/lnd.conf"
            "$home_dir/.lnd/lnd.conf"
            "${TS_FS_ROOT}/home/bitcoin/.lnd/lnd.conf"
            "$home_dir/umbrel/lnd/lnd.conf"
            "$home_dir/umbrel/app-data/lightning/data/lnd/lnd.conf"
            "${TS_FS_ROOT}/data/lnd/lnd.conf"
            "${TS_FS_ROOT}/mnt/hdd/mynode/lnd/lnd.conf"
        )
        for path in "${paths[@]}"; do
            if [[ -f "$path" ]]; then
                while IFS= read -r nc_entry; do
                    nc_num="${nc_entry%%|*}"
                    nc_entry="${nc_entry#*|}"
                    nc_key="${nc_entry%%|*}"
                    nc_val="${nc_entry#*|}"
                    if ts_m_nc_setting_hit "lnd" "$nc_key" "$nc_val"; then
                        detected_nc_lines+=("${path}:${nc_num}:${nc_key}=${nc_val}")
                    fi
                done < <(ts_m_config_settings "$path")
            fi
        done
    elif [[ "$ln_impl" == "cln" ]]; then
        local paths=(
            "${TS_FS_ROOT}/mnt/hdd/app-data/.lightning/config"
            "${TS_FS_ROOT}/home/bitcoin/.lightning/config"
            "$home_dir/umbrel/app-data/core-lightning/data/lightningd/bitcoin/config"
            "${TS_FS_ROOT}/data/lightningd/config"
        )
        for path in "${paths[@]}"; do
            if [[ -f "$path" ]]; then
                while IFS= read -r nc_entry; do
                    nc_num="${nc_entry%%|*}"
                    nc_entry="${nc_entry#*|}"
                    nc_key="${nc_entry%%|*}"
                    nc_val="${nc_entry#*|}"
                    if ts_m_nc_setting_hit "cln" "$nc_key" "$nc_val"; then
                        detected_nc_lines+=("${path}:${nc_num}:${nc_key}=${nc_val}")
                    fi
                done < <(ts_m_config_settings "$path")
                local inc_entry inc_num inc_key inc_v inc_file
                while IFS= read -r nc_entry; do
                    nc_num="${nc_entry%%|*}"
                    nc_val="${nc_entry#*|}"
                    detected_nc_lines+=("${path}:${nc_num}:include ${nc_val}")
                    inc_file="$nc_val"
                    if [[ "$inc_file" != /* ]]; then
                        inc_file="$(dirname "$path")/${inc_file}"
                    else
                        inc_file="${TS_FS_ROOT}${inc_file}"
                    fi
                    if [[ -f "$inc_file" ]]; then
                        while IFS= read -r inc_entry; do
                            inc_num="${inc_entry%%|*}"
                            inc_entry="${inc_entry#*|}"
                            inc_key="${inc_entry%%|*}"
                            inc_v="${inc_entry#*|}"
                            if ts_m_nc_setting_hit "cln" "$inc_key" "$inc_v"; then
                                detected_nc_lines+=("${inc_file}:${inc_num}:${inc_key}=${inc_v}")
                            fi
                        done < <(ts_m_config_settings "$inc_file")
                    fi
                done < <(ts_m_cln_config_includes "$path")
            fi
        done
        if [[ -f "$home_dir/umbrel/app-data/core-lightning/exports.sh" ]] && \
            grep -q 'APP_CORE_LIGHTNING_DAEMON_PORT="9735"' "$home_dir/umbrel/app-data/core-lightning/exports.sh" 2>/dev/null; then
            detected_nc_lines+=("$home_dir/umbrel/app-data/core-lightning/exports.sh:APP_CORE_LIGHTNING_DAEMON_PORT=\"9735\"")
        fi
        if [[ -f "$home_dir/umbrel/app-data/core-lightning/docker-compose.yml" ]] && \
            grep -qE "^[[:space:]]*#[[:space:]]*-[[:space:]]*['\"]*--bind-addr" "$home_dir/umbrel/app-data/core-lightning/docker-compose.yml" 2>/dev/null; then
            detected_nc_lines+=("$home_dir/umbrel/app-data/core-lightning/docker-compose.yml:commented --bind-addr")
        fi
    elif [[ "$ln_impl" == "lit" ]]; then
        local paths=(
            "$home_dir/.lit/lit.conf"
            "${TS_FS_ROOT}/home/bitcoin/.lit/lit.conf"
            "${TS_FS_ROOT}/data/lit/lit.conf"
        )
        for path in "${paths[@]}"; do
            if [[ -f "$path" ]]; then
                while IFS= read -r nc_entry; do
                    nc_num="${nc_entry%%|*}"
                    nc_entry="${nc_entry#*|}"
                    nc_key="${nc_entry%%|*}"
                    nc_val="${nc_entry#*|}"
                    if ts_m_nc_setting_hit "lit" "$nc_key" "$nc_val"; then
                        detected_nc_lines+=("${path}:${nc_num}:${nc_key}=${nc_val}")
                    fi
                done < <(ts_m_config_settings "$path")
            fi
        done
    fi
    if [[ ${#detected_nc_lines[@]} -gt 0 ]]; then
        print_warning "TunnelSats clearnet settings found in your node configuration (not edited automatically):"
        for nc_entry in "${detected_nc_lines[@]}"; do
            echo "  - ${nc_entry}"
        done
        # As uninstall --managed does: without the tunnel these settings use the regular internet
        # connection, so the stopped Lightning unit is disabled until they are removed
        local nc_unit=""
        case "$ln_impl" in
            lnd) nc_unit="lnd.service" ;;
            cln) nc_unit="lightningd.service" ;;
            lit) nc_unit="litd.service"; [[ -f "${TS_FS_ROOT}/etc/systemd/system/${nc_unit}" ]] || nc_unit="lit.service" ;;
        esac
        if [[ $is_docker -eq 0 ]] && [[ -n "$nc_unit" ]]; then
            if systemctl disable "$nc_unit" &>/dev/null; then
                print_warning "${nc_unit} stays stopped and is disabled. Remove these settings, then run: sudo systemctl enable --now ${nc_unit}"
            else
                print_error "${nc_unit} could not be disabled: remove these settings before the next boot"
            fi
        fi
    else
        print_info "No TunnelSats clearnet settings detected in standard config locations"
    fi
    echo ""

    # 4. Remove Splitting Services
    print_step 3 6 "Removing helper services..."
    if [[ $is_docker -eq 0 ]]; then
        # Check timers/services
        for svc in tunnelsats-splitting-processes.timer tunnelsats-splitting-processes.service tunnelsats-create-cgroup.service; do
             if [[ -f "${TS_FS_ROOT}/etc/systemd/system/$svc" ]]; then
                 systemctl stop "$svc" &>/dev/null || true
                 systemctl disable "$svc" &>/dev/null || true
                 rm -f "${TS_FS_ROOT}/etc/systemd/system/$svc" &>/dev/null
                 rm -f "${TS_FS_ROOT}/etc/systemd/system/multi-user.target.wants/$svc" &>/dev/null || true
                 rm -f "${TS_FS_ROOT}/etc/systemd/system/timers.target.wants/$svc" &>/dev/null || true
                 print_success "Removed $svc"
             fi
        done

        if [[ -f "${TS_FS_ROOT}/etc/systemd/system/blitzapi.service.d/tunnelsats-wg.conf" ]]; then
            rm -f "${TS_FS_ROOT}/etc/systemd/system/blitzapi.service.d/tunnelsats-wg.conf" &>/dev/null || true
            rmdir "${TS_FS_ROOT}/etc/systemd/system/blitzapi.service.d" &>/dev/null || true
            systemctl daemon-reload &>/dev/null || true
            print_success "Removed blitzapi.service dependency"
        fi

        local check_base
        for check_base in lnd.check cl.check; do
            if [[ -f "${TS_FS_ROOT}/home/admin/config.scripts/${check_base}.bak" ]]; then
                if [[ ! -f "${TS_FS_ROOT}/home/admin/config.scripts/${check_base}.sh" ]]; then
                    mv "${TS_FS_ROOT}/home/admin/config.scripts/${check_base}.bak" "${TS_FS_ROOT}/home/admin/config.scripts/${check_base}.sh" &>/dev/null || true
                    print_success "Restored ${check_base}.sh"
                else
                    rm -f "${TS_FS_ROOT}/home/admin/config.scripts/${check_base}.bak" &>/dev/null || true
                fi
            fi
        done
        
        # Remove cgroups
        if [[ -d /sys/fs/cgroup/net_cls/tor_splitting ]]; then cgdelete net_cls:/tor_splitting 2>/dev/null; fi
        if [[ -d /sys/fs/cgroup/net_cls/splitted_processes ]]; then cgdelete net_cls:/splitted_processes 2>/dev/null; fi
        
    else
        # Docker cleanup
         for svc in tunnelsats-docker-network.timer tunnelsats-docker-network.service; do
             if [[ -f "${TS_FS_ROOT}/etc/systemd/system/$svc" ]]; then
                 systemctl stop "$svc" &>/dev/null || true
                 systemctl disable "$svc" &>/dev/null || true
                 rm -f "${TS_FS_ROOT}/etc/systemd/system/$svc" &>/dev/null
                 rm -f "${TS_FS_ROOT}/etc/systemd/system/multi-user.target.wants/$svc" &>/dev/null || true
                 rm -f "${TS_FS_ROOT}/etc/systemd/system/timers.target.wants/$svc" &>/dev/null || true
                 print_success "Removed $svc"
             fi
        done
        
        # Umbrel Killswitch
        rm -f "${TS_FS_ROOT}/etc/systemd/system/umbrel.service.d/tunnelsats_killswitch.conf" &>/dev/null
        rm -f "${TS_FS_ROOT}/etc/systemd/system/umbrel-startup.service.d/tunnelsats_killswitch.conf" &>/dev/null
        rmdir "${TS_FS_ROOT}/etc/systemd/system/umbrel.service.d" &>/dev/null || true
        rmdir "${TS_FS_ROOT}/etc/systemd/system/umbrel-startup.service.d" &>/dev/null || true
        print_success "Removed Umbrel killswitch"
    fi
    echo ""

    # 5. Remove WireGuard Services
    print_step 4 6 "Removing WireGuard configuration..."
    
    # Every installed TunnelSats tunnel is removed: the configs found by ts_select_wg_config (the
    # list detect, status and restart choose from). tunnelsatsv2 is cleaned up even without a config.
    local wg_dir="${WG_DIR:-${TS_FS_ROOT}/etc/wireguard}"
    local -a target_interfaces=()
    local target_interface wg_conf announce_out=""
    ts_select_wg_config "" "" "$wg_dir"
    for wg_conf in "${TS_WG_CANDIDATES[@]}"; do
        target_interfaces+=("$(basename "$wg_conf" .conf)")
    done
    if [[ ${#target_interfaces[@]} -eq 0 ]]; then target_interfaces=("tunnelsatsv2"); fi

    if [[ "$ln_impl" == "lnd" ]] || [[ "$ln_impl" == "lit" ]]; then
        announce_out=$(ts_print_announce_command "$is_docker" "$lnd_container" "${TS_WG_CANDIDATES[@]}")
    fi

    for target_interface in "${target_interfaces[@]}"; do
        systemctl stop "wg-quick@${target_interface}" &>/dev/null || true
        systemctl disable "wg-quick@${target_interface}" &>/dev/null || true
        if [[ -L "${TS_FS_ROOT}/etc/systemd/system/multi-user.target.wants/wg-quick@${target_interface}.service" ]] || [[ -e "${TS_FS_ROOT}/etc/systemd/system/multi-user.target.wants/wg-quick@${target_interface}.service" ]]; then
            rm -f "${TS_FS_ROOT}/etc/systemd/system/multi-user.target.wants/wg-quick@${target_interface}.service" &>/dev/null || true
        fi
    done
    
    if [[ -L "${TS_FS_ROOT}/etc/systemd/system/multi-user.target.wants/wg-quick@tunnelsats.service" ]] || [[ -f "${TS_FS_ROOT}/etc/systemd/system/multi-user.target.wants/wg-quick@tunnelsats.service" ]]; then
         systemctl stop wg-quick@tunnelsats &>/dev/null || true
         systemctl disable wg-quick@tunnelsats &>/dev/null || true
         rm -f "${TS_FS_ROOT}/etc/systemd/system/multi-user.target.wants/wg-quick@tunnelsats.service" &>/dev/null || true
    fi
    
    # Remove DNS resolver
    if [[ -f "${TS_FS_ROOT}/etc/systemd/system/tunnelsats-resolve-dns-wg.service" ]]; then
         systemctl stop tunnelsats-resolve-dns-wg.service &>/dev/null
         systemctl disable tunnelsats-resolve-dns-wg.service &>/dev/null
         rm -f "${TS_FS_ROOT}/etc/systemd/system/tunnelsats-resolve-dns-wg.service"
         rm -f "${TS_FS_ROOT}/etc/systemd/system/multi-user.target.wants/tunnelsats-resolve-dns-wg.service" &>/dev/null || true
    fi
    if [[ -f "${TS_FS_ROOT}/etc/systemd/system/tunnelsats-resolve-dns-wg.timer" ]]; then
         systemctl stop tunnelsats-resolve-dns-wg.timer &>/dev/null
         systemctl disable tunnelsats-resolve-dns-wg.timer &>/dev/null
         rm -f "${TS_FS_ROOT}/etc/systemd/system/tunnelsats-resolve-dns-wg.timer"
         rm -f "${TS_FS_ROOT}/etc/systemd/system/timers.target.wants/tunnelsats-resolve-dns-wg.timer" &>/dev/null || true
    fi

    for target_interface in "${target_interfaces[@]}"; do
        rm -rf "${TS_FS_ROOT}/etc/systemd/system/wg-quick@${target_interface}.service.d" &>/dev/null
    done

    local helper_file
    for helper_file in "$wg_dir/tunnelsats-route-guard.sh" "$wg_dir/tunnelsats-create-cgroup.sh" \
        "$wg_dir/tunnelsats-splitting-processes.sh" "$wg_dir/tunnelsats-resolve-dns-wg.sh" \
        "$wg_dir/tunnelsats-docker-network.sh"; do
        if [[ -f "$helper_file" ]]; then
            rm -f "$helper_file" &>/dev/null || true
        fi
    done
    for helper_file in "$wg_dir"/tunnelsats*.conf.bak.*; do
        if [[ -f "$helper_file" ]]; then
            rm -f "$helper_file" &>/dev/null || true
        fi
    done
    if [[ "$TS_OPT_KEEP_CONFIG" -eq 1 ]]; then
        print_info "Keeping WireGuard configuration files (--keep-config)"
    else
        for wg_conf in "${TS_WG_CANDIDATES[@]}"; do
            rm -f "$wg_conf" &>/dev/null || true
        done
    fi
    print_success "WireGuard services removed"
    echo ""

    # 6. NFTables Cleanup (All Platforms)
    print_step 5 6 "Cleaning network rules..."
    for target_interface in "${target_interfaces[@]}"; do
        nft delete table ip "${target_interface}" &>/dev/null || true
        nft delete table inet "${target_interface}" &>/dev/null || true
    done
    nft delete table ip tunnelsatsv2 &>/dev/null || true
    nft delete table inet tunnelsatsv2 &>/dev/null || true
    # TunnelSats is being removed on purpose: drop any emergency fail-closed block it armed
    if ! ts_release_failclosed "$(resolve_failclosed_subnet)" "$(resolve_failclosed_host_uid)"; then
        print_warning "Some emergency fail-closed rules could not be removed. Check 'ip -4 rule show'."
    fi
    
    if [[ -f "${TS_FS_ROOT}/etc/nftablespriortunnelsats.backup" ]]; then
         if [[ ! -f "${TS_FS_ROOT}/etc/nftables.conf" ]] \
             || grep -qE 'tunnelsats|splitted_processes|0x1000000' "${TS_FS_ROOT}/etc/nftables.conf" 2>/dev/null \
             || cmp -s "${TS_FS_ROOT}/etc/nftablespriortunnelsats.backup" "${TS_FS_ROOT}/etc/nftables.conf" 2>/dev/null; then
             mv "${TS_FS_ROOT}/etc/nftablespriortunnelsats.backup" "${TS_FS_ROOT}/etc/nftables.conf"
             print_success "Restored original nftables.conf"
         else
             print_warning "Kept /etc/nftables.conf and /etc/nftablespriortunnelsats.backup (existing /etc/nftables.conf contains non-TunnelSats rules)"
         fi
    fi

    # Remove only TunnelSats-owned policy rules/routes; other users of table 51820 are preserved
    for target_interface in "${target_interfaces[@]}"; do
        if ! cleanup_owned_routing_state "$target_interface"; then
            print_warning "Some TunnelSats policy rules could not be removed. Check 'ip rule show'."
        fi
    done

    if [[ -f "$wg_dir/.tunnelsats-ipv6-disabled" ]]; then
        sysctl -w net.ipv6.conf.all.disable_ipv6=0 &>/dev/null || true
        sysctl -w net.ipv6.conf.default.disable_ipv6=0 &>/dev/null || true
        rm -f "$wg_dir/.tunnelsats-ipv6-disabled" &>/dev/null || true
    fi

    if [[ $is_docker -eq 1 ]]; then
        print_info "Cleaning Docker network..."
        
        # Disconnect containers from network
        docker inspect docker-tunnelsats 2>/dev/null | jq '.[].Containers' | grep Name | sed 's/[",]//g' | awk '{print $2}' | xargs -I % sh -c 'docker network disconnect docker-tunnelsats % 2>/dev/null'
        
        if docker network rm docker-tunnelsats &>/dev/null; then
            print_success "Removed docker-tunnelsats network"
        fi
        
        systemctl daemon-reload || true
        systemctl restart docker &>/dev/null || true
        print_success "Docker restarted"
    fi
    echo ""

    # UFW Rules Cleanup
    local ufw_marker_file
    for target_interface in "${target_interfaces[@]}"; do
        ufw_marker_file="$wg_dir/.tunnelsats-ufw-9735-${target_interface}.created"
        if [[ -f "$ufw_marker_file" ]]; then
            if command -v ufw >/dev/null 2>&1; then
                print_info "Removing TunnelSats UFW rules..."
                if ufw delete allow in on "${target_interface}" to any port 9735 proto tcp &>/dev/null; then
                    rm -f "$ufw_marker_file" &>/dev/null || true
                    print_success "Removed UFW rules for port 9735 on ${target_interface}"
                else
                    print_error "Failed to remove UFW rules for port 9735 on ${target_interface}"
                fi
            else
                rm -f "$ufw_marker_file" &>/dev/null || true
            fi
        fi
    done
    
    # 7. Restore Original Service Files
    if [[ $is_docker -eq 0 ]]; then
        print_step 6 6 "Restoring systemd service files..."
        if [[ "$ln_impl" == "lnd" && -f "${TS_FS_ROOT}/etc/systemd/system/lnd.service.bak" ]]; then
             mv "${TS_FS_ROOT}/etc/systemd/system/lnd.service.bak" "${TS_FS_ROOT}/etc/systemd/system/lnd.service"
             print_success "Restored lnd.service backup"
        fi
        if [[ "$ln_impl" == "cln" && -f "${TS_FS_ROOT}/etc/systemd/system/lightningd.service.bak" ]]; then
             mv "${TS_FS_ROOT}/etc/systemd/system/lightningd.service.bak" "${TS_FS_ROOT}/etc/systemd/system/lightningd.service"
             print_success "Restored lightningd.service backup"
        fi
        if [[ "$ln_impl" == "lit" ]]; then
            local s_file="${TS_FS_ROOT}/etc/systemd/system/litd.service"
            [[ ! -f "$s_file" ]] && s_file="${TS_FS_ROOT}/etc/systemd/system/lit.service"
            if [[ -f "${s_file}.bak" ]]; then
                mv "${s_file}.bak" "$s_file"
                print_success "Restored ${s_file} backup"
            fi
        fi
        systemctl daemon-reload
        echo ""
    fi
    
    # Optional Package Removal. This question comes after the removal steps above, so it never
    # fails: --remove-packages or --keep-packages answer it, while non-interactive mode and end
    # of input keep the packages (the safe answer).
    local has_resolvconf_marker=0
    if [[ -f "$wg_dir/.tunnelsats-resolvconf.installed" ]]; then
        has_resolvconf_marker=1
    fi
    case "$TS_OPT_PACKAGES" in
        remove) answer="Y" ;;
        keep) answer="N" ;;
        *)
            if [[ "$TS_NONINTERACTIVE" -eq 1 ]]; then
                answer="N"
                print_info "Non-interactive mode: keeping system packages (pass --remove-packages to remove them)"
            else
                echo "Do you want to uninstall system packages?"
                if [[ $is_docker -eq 1 ]]; then
                    if [[ "$has_resolvconf_marker" -eq 1 ]]; then
                        ts_ask answer "--remove-packages" "Remove nftables, resolvconf and wireguard-tools? (Y/N) " "N"
                    else
                        ts_ask answer "--remove-packages" "Remove nftables and wireguard-tools? (Y/N) " "N"
                    fi
                else
                    if [[ "$has_resolvconf_marker" -eq 1 ]]; then
                        ts_ask answer "--remove-packages" "Remove cgroup-tools, nftables, resolvconf and wireguard-tools? (Y/N) " "N"
                    else
                        ts_ask answer "--remove-packages" "Remove cgroup-tools, nftables and wireguard-tools? (Y/N) " "N"
                    fi
                fi
            fi
            ;;
    esac
    
    if [[ "$answer" =~ ^[Yy] ]]; then
         if [[ $is_docker -eq 1 ]]; then
             if [[ "$has_resolvconf_marker" -eq 1 ]]; then
                 apt-get remove -yqq nftables resolvconf wireguard-tools &>/dev/null
             else
                 apt-get remove -yqq nftables wireguard-tools &>/dev/null
             fi
         else
             if [[ "$has_resolvconf_marker" -eq 1 ]]; then
                 apt-get remove -yqq cgroup-tools nftables resolvconf wireguard-tools &>/dev/null
             else
                 apt-get remove -yqq cgroup-tools nftables wireguard-tools &>/dev/null
             fi
         fi
         if [[ "$has_resolvconf_marker" -eq 1 ]]; then
             rm -f "$wg_dir/.tunnelsats-resolvconf.installed" &>/dev/null || true
         fi
         print_success "Packages removed"
    else
         print_info "Packages kept"
    fi

    echo ""
    print_line
    print_success "TunnelSats uninstalled successfully!"
    print_line
    echo ""
    
    echo -e "${BOLD}MANUAL CLEANUP REQUIRED:${NC}"
    echo "Please check your lightning configuration files and remove any leftover"
    echo "TunnelSats settings if they were not automatically restored:"
    if [[ ${#detected_nc_lines[@]} -gt 0 ]]; then
        for nc_entry in "${detected_nc_lines[@]}"; do
            echo "  - ${nc_entry}"
        done
    fi
    if [[ "$ln_impl" == "lnd" ]]; then
        if [[ "$PLATFORM" == "umbrel" ]]; then
            echo -e "  Command: ${BOLD}nano $home_dir/umbrel/app-data/lightning/data/lnd/lnd.conf${NC}"
        fi
        echo "  - externalhosts (should be removed)"
        echo "  - tor.skip-proxy-for-clearnet-targets (should be false or removed)"
    elif [[ "$ln_impl" == "cln" ]]; then
        if [[ "$PLATFORM" == "umbrel" ]]; then
            echo -e "  Command: ${BOLD}nano $home_dir/umbrel/app-data/core-lightning/data/lightningd/bitcoin/config${NC}"
        fi
        echo "  - announce-addr (should be removed)"
        echo "  - bind-addr=0.0.0.0:9735 (should be removed)"
    elif [[ "$ln_impl" == "lit" ]]; then
        echo "  - externalhosts (should be removed)"
        echo "  - tor.skip-proxy-for-clearnet-targets (should be false or removed)"
    fi
    echo ""
    if [[ "$ln_impl" == "lnd" ]] || [[ "$ln_impl" == "lit" ]]; then
        printf '%s\n' "$announce_out"
        echo ""
    fi
    
    echo "Next: Restart your node for changes to take effect."
    echo "      (Required to fully clear persistent network rules)"
    echo ""
    echo -e "   ${BOLD}sudo reboot${NC}"
    echo ""
}

cmd_install() {
    check_root
    check_umbrel_version
    print_header "TunnelSats Installation"

    # Step 1: Configuration is already detected in parse_args
    print_step 1 6 "Configuration verified: ${CONFIG_FILE##*/}"
    echo ""
    
    # Step 2: Detect Environment
    print_step 2 6 "Analyzing environment..."
    detect_platform
    detect_ln_implementation
    
    local is_docker=0
    [[ "$PLATFORM" == "umbrel" ]] && is_docker=1
    [[ "$PLATFORM" == "mynode" ]] && is_docker=0 # myNode nodal part is bare metal
    
    print_info "Platform: ${PLATFORM}, Lightning: ${LN_IMPL}"
    echo ""

    # Step 3: Check dependencies
    print_step 3 6 "Checking dependencies..."
    # wireguard-tools and its systemd unit template
    local wg_service_template_exists=0
    [[ -f /lib/systemd/system/wg-quick@.service || -f /usr/lib/systemd/system/wg-quick@.service || -f /etc/systemd/system/wg-quick@.service ]] && wg_service_template_exists=1

    if ! command -v wg &>/dev/null || [[ $wg_service_template_exists -eq 0 ]]; then
        print_info "Installing wireguard-tools..."
        if ! apt-get update -qq &>/dev/null || ! apt-get install -yqq wireguard-tools &>/dev/null; then
            # try Debian 10 Buster workaround / myNode
            local codename=$(lsb_release -c 2>/dev/null | awk '{print $2}')
            if [[ "$codename" == "buster" && "$PLATFORM" != "umbrel" ]]; then
                print_info "Attempting Debian 10 Buster workaround..."
                apt-get install -yqq -t buster-backports wireguard-tools &>/dev/null
            fi
        fi
    fi
    if ! command -v nft &>/dev/null; then
        print_info "Installing nftables..."
        apt-get install -yqq nftables &>/dev/null
    fi
    if ! command -v jq &>/dev/null; then
        print_info "Installing jq..."
        apt-get install -yqq jq &>/dev/null
    fi
    if ! command -v resolvconf &>/dev/null; then
        print_info "Installing resolvconf..."
        if apt-get install -yqq resolvconf &>/dev/null; then
            mkdir -p "${WG_DIR:-${TS_FS_ROOT}/etc/wireguard}"
            : > "${WG_DIR:-${TS_FS_ROOT}/etc/wireguard}/.tunnelsats-resolvconf.installed"
        fi
    fi
    
    # Only install cgroup-tools for non-Docker platforms (Umbrel uses Docker networking)
    if [[ "$PLATFORM" != "umbrel" ]]; then
         if ! command -v cgexec &>/dev/null; then
            print_info "Installing cgroup-tools..."
            apt-get install -yqq cgroup-tools &>/dev/null
        fi
    fi
    echo ""

    # Step 4: Configure Lightning
    print_step 4 6 "Configuring Lightning..."
    configure_lightning
    echo ""

    # Resolve target tunnel interface up front so an already-active tunnel is stopped and tracked
    WG_INTERFACE=$(basename "$(resolve_wg_target_path)" .conf)

    # Any failure between the leak-proof stop and enable_services restores the previous tunnel
    # (verified) before restarting the daemon, or keeps the daemon stopped (fail-closed).
    trap rollback_failed_install EXIT

    # Stop running Lightning daemon BEFORE any route or network changes to prevent clearnet leakage
    stop_lightning_daemon_for_safe_restart

    # Step 5: Configure WireGuard
    print_step 5 6 "Configuring WireGuard..."
    configure_wireguard
    
    # Configure DNS Resolver Watchdog
    setup_dns_resolver "$WG_INTERFACE"
    
    # Configure Docker Network (Umbrel/Docker only)
    if [[ $is_docker -eq 1 ]]; then
        setup_docker_network
    fi
    echo ""

    # enable_services has its own fail-closed handling once the new tunnel start is attempted
    trap - EXIT

    # Step 6: Enable services
    print_step 6 6 "Enabling services..."
    enable_services
    
    # Verify installation
    verify_installation
    echo ""

    # Post-Install Health Check
    print_info "Performing post-install connectivity check..."
    if ping -c 1 -W 2 10.9.0.1 &>/dev/null; then
        print_success "VPN Gateway (10.9.0.1) is reachable!"
    else
        print_warning "Could not ping VPN Gateway (10.9.0.1)."
        print_warning "This is common after first install. A reboot usually fixes it."
    fi
    echo ""
    
    # Display success message
    print_line
    print_success "TunnelSats installed successfully!"
    print_line
    echo ""
    
    # Extract details for manual config
    local vpn_dns=$(grep "^Endpoint" "$CONFIG_FILE" | awk '{print $3}' | cut -d ':' -f 1)
    local vpn_port=$(ts_config_vpn_port "$CONFIG_FILE")
    
    echo -e "${BOLD}CRITICAL: You must update your node configuration!${NC}"
    echo "Please copy the following settings into your configuration file."
    echo ""

    print_node_config_instructions "$vpn_dns" "$vpn_port" "install"

    # Check firewall configuration if UFW is active
    if command -v ufw >/dev/null 2>&1; then
        echo ""
        print_info "Checking Firewall Configuration (UFW)..."
        check_ufw_configuration "$WG_INTERFACE" || true
    elif [[ "$PLATFORM" == "baremetal" || "$PLATFORM" == "raspiblitz" ]]; then
        echo ""
        echo -e "${BOLD}${YELLOW}UFW FIREWALL NOTICE:${NC}"
        echo "If you use UFW, ensure you allow traffic on the Lightning port (TCP 9735):"
        echo -e "  ${BOLD}sudo ufw allow 9735/tcp${NC}"
    fi

    echo ""
    echo "Then, restart your node:"
    if [[ "$PLATFORM" == "umbrel" ]]; then
        echo "   sudo reboot"
        echo "   (Or restart the Lightning app via Umbrel Dashboard: Right-click -> Restart)"
    else
        local svc="${LN_IMPL}"
        [[ "$LN_IMPL" == "cln" ]] && svc="lightningd"
        echo "   sudo systemctl restart ${svc}.service"
    fi
    echo ""
}

auto_detect_environment() {
    # Auto-detect platform
    if [[ -z "$PLATFORM" ]]; then
        if [[ -d /home/admin/config.scripts ]]; then
            PLATFORM="raspiblitz"
        elif [[ -d /home/umbrel/umbrel ]] || [[ -d /umbrel ]] || [[ -f /usr/bin/umbrel ]]; then
            PLATFORM="umbrel"
        elif [[ -d /usr/share/mynode ]]; then
            PLATFORM="mynode"
        else
            PLATFORM="baremetal"
        fi
    fi
    
    # Auto-detect implementation
    if [[ -z "$LN_IMPL" ]]; then
        if [[ "$PLATFORM" == "umbrel" ]]; then
            if docker ps --filter name=core-lightning -q | grep -q .; then
                LN_IMPL="cln"
            elif docker ps --filter name=lnd -q | grep -q .; then
                LN_IMPL="lnd"
            fi
        else
            if systemctl is-active --quiet lnd; then
                LN_IMPL="lnd"
            elif systemctl is-active --quiet lightningd; then
                LN_IMPL="cln"
            elif systemctl is-active --quiet litd || systemctl is-active --quiet lit; then
                # Only auto-detect if Integrated Mode
                local s_file="/etc/systemd/system/litd.service"
                [[ ! -f "$s_file" ]] && s_file="/etc/systemd/system/lit.service"
                if grep -qi "lnd-mode=integrated" "$s_file" 2>/dev/null || grep -qi "lnd-mode.*integrated" /etc/lit/lit.conf 2>/dev/null || grep -qi "lnd-mode.*integrated" "$HOME/.lit/lit.conf" 2>/dev/null; then
                    LN_IMPL="lit"
                fi
            fi
        fi
    fi

    # Detect node user for non-Docker
    if [[ -n "$LN_IMPL" ]] && [[ "$PLATFORM" != "umbrel" ]] && [[ -z "$node_user" ]]; then
        local s_file=""
        [[ "$LN_IMPL" == "lnd" ]] && s_file="/etc/systemd/system/lnd.service"
        [[ "$LN_IMPL" == "cln" ]] && s_file="/etc/systemd/system/lightningd.service"
        if [[ "$LN_IMPL" == "lit" ]]; then
            s_file="/etc/systemd/system/litd.service"
            [[ ! -f "$s_file" ]] && s_file="/etc/systemd/system/lit.service"
        fi
        if [[ -f "$s_file" ]]; then
            node_user=$(grep -Ei "^User[[:space:]]*=" "$s_file" | cut -d'=' -f2 | xargs)
        fi
        [[ -z "$node_user" ]] && [[ "$PLATFORM" == "raspiblitz" ]] && node_user="bitcoin"
        [[ -z "$node_user" ]] && node_user=$(whoami)
    fi
    return 0
}

cmd_status() {
    print_header "Subscription Status"
    
    echo ""
    
    # 0. Auto-detect environment if not set
    auto_detect_environment
    
    # 1. Active Config & WireGuard Status Check
    # Same selection as detect and restart (--config, tunnelsatsv2.conf, the only tunnelsats-*.conf);
    # several candidates are asked, never guessed
    local config_file
    if ! ts_resolve_wg_config; then
        print_error "No TunnelSats configuration found."
        echo "Expected locations:"
        echo "  • /etc/wireguard/tunnelsatsv2.conf"
        echo "  • /etc/wireguard/tunnelsats-*.conf"
        echo "Pass --config <file> for a config with another name."
        exit 1
    fi
    config_file="$TS_WG_RESOLVED"

    # Extract interface name
    local interface_name=$(basename "$config_file" .conf)
    
    # Get WireGuard details
    local wg_output=$(wg show ${interface_name} 2>/dev/null)
    local is_tunnel_active=0
    if [[ -n "$wg_output" ]]; then
        is_tunnel_active=1
    fi
    
    # Parse WireGuard info
    local public_key=$(echo "$wg_output" | grep "public key" | awk '{print $3}')
    local endpoint=$(echo "$wg_output" | grep "endpoint" | awk '{print $2}')
    local latest_handshake=$(echo "$wg_output" | grep "latest handshake" | sed 's/latest handshake: //')
    local transfer=$(echo "$wg_output" | grep "transfer")
    local transfer_rx=$(echo "$transfer" | awk '{print $2, $3}')
    local transfer_tx=$(echo "$transfer" | awk '{print $5, $6}')
    
    # Parse Config File Metadata
    local vpn_port=$(ts_config_vpn_port "$config_file")
    local sub_end=$(parse_config_metadata "$config_file" expiry)
    # If endpoint missing from wg_output (tunnel down), try config
    if [[ -z "$endpoint" ]]; then
         endpoint=$(grep '^Endpoint' "$config_file" | awk '{print $3}' | cut -d ':' -f 1)
    fi

    local status_msg=""
    if [[ $is_tunnel_active -eq 1 ]]; then
         # Check handshake freshness
        if [[ "$latest_handshake" == *"minute"* ]] || [[ "$latest_handshake" == *"second"* ]]; then
             status_msg="${GREEN}Active${NC}"
        else
             status_msg="${YELLOW}Stale (Old Handshake)${NC}"
        fi
    else
        status_msg="${RED}Offline${NC}"
        latest_handshake="N/A"
        transfer_rx="0"
        transfer_tx="0"
    fi

    # Display Summary
    echo -e "${BOLD}WireGuard Tunnel Status${NC}"
    print_line
    echo -e "  Interface:      ${interface_name}"
    echo -e "  Status:         ${status_msg}"
    echo -e "  Public Key:     ${BLUE}${public_key}${NC}"
    echo -e "  Last Handshake: ${latest_handshake}"
    echo -e "  Transfer:       ↓ ${transfer_rx} / ↑ ${transfer_tx}"
    echo -e "  VPN Endpoint:   ${endpoint}"
    echo -e "  VPN Port:       ${vpn_port}"
    if [[ -n "$sub_end" ]]; then
        echo -e "  Expires:        ${sub_end}" 
    fi
    echo ""

    # ---------------------------------------------------------
    # Node & Connectivity Checks (Ported from tunnelsats-sub-details.sh)
    # ---------------------------------------------------------

    # 1. Docker Setup Check
    check_docker_setup_status() {
       if systemctl is-active --quiet docker; then
         if docker ps --filter name=core-lightning -q | grep -q . || docker ps --filter name=lnd -q | grep -q .; then
          if docker ps --filter name=core-lightning -q | grep -q .; then
            echo "docker-core-lightning"
            return 0
          elif docker ps --filter name=lnd -q | grep -q .; then
            echo "docker-lnd"
            return 0
          fi
         fi
       fi
       echo "manual"
       return 1
    }

    # 2. Outbound Check
    perform_outbound_check_status() {
      local setup_type=$1
      local ip_address=""
      local cmd_exit_code=0
    
      if [[ "$setup_type" == "docker-lnd" || "$setup_type" == "docker-core-lightning" ]]; then
        if ! docker network inspect docker-tunnelsats > /dev/null 2>&1; then
            ip_address="Error: Docker network missing"
        else
            ip_address=$(timeout 20s docker run --rm --net=docker-tunnelsats curlimages/curl -s https://api.ipify.org)
            cmd_exit_code=$?
            if [ $cmd_exit_code -ne 0 ] || [[ -z "$ip_address" ]]; then
                 ip_address="Error: Check failed or timed out"
            fi
        fi
      else
        # Manual
        if command -v cgexec &> /dev/null; then
          ip_address=$(timeout 20s cgexec -g net_cls:splitted_processes curl --silent https://api.ipify.org)
        else
          # Fallback
          ip_address=$(timeout 20s curl --silent https://api.ipify.org)
        fi
      fi
      echo "$ip_address"
    }
    
    # 3. Inbound Check
    perform_inbound_check_status() {
      local target_endpoint=$1
      local target_port=$2
      local result_url=""
      local status="failed"
      
      # Clean endpoint
      local clean_endpoint=$(echo $target_endpoint | cut -d ':' -f 1)
      
      local curl_output=$(timeout 3s curl -sv telnet://"${clean_endpoint}":"${target_port}" 2>&1 | head -n 2)
      
      if [[ "$curl_output" == *"Connected to"* ]]; then
        result_url=$(echo "$curl_output" | grep "Connected to" | grep -oP 'Connected to [^ ]+ \(\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
        if [[ -n "$result_url" ]]; then
           status="success"
        else
           result_url="Unknown (Success)"
           status="success_no_ip"
        fi
      else
        result_url="Error: Connection failed"
      fi
      echo "$status $result_url"
    }

    # 4. Get Node Address
    get_node_ext_addr_status() {
        local setup_type=$1
        local ext_addr="N/A"
        local docker_name=""
        local node_type=""
        local target_impl="${LN_IMPL:-unknown}"

        case "$setup_type" in
            "docker-lnd")
                docker_name=$(docker ps --filter name=_lnd --format "{{.Names}}" | head -n 1) # Safer fetch
                if [[ -z "$docker_name" ]]; then docker_name="lightning_lnd_1"; fi # Fallback
                node_type="LND (Docker)"
                if command -v jq &> /dev/null; then
                    # Try direct exec
                    local info=$(docker exec "$docker_name" lncli getinfo 2>/dev/null)
                    if [[ -n "$info" ]]; then
                        ext_addr=$(echo "$info" | jq -r '.uris[]' | grep -v "\.onion" | head -n 1)
                        [[ -z "$ext_addr" ]] && ext_addr="NONE_DETECTED"
                    else
                        ext_addr="NODE_UNREACHABLE"
                    fi
                else
                    ext_addr="DEPENDENCY_MISSING"
                fi
                ;;
            "docker-core-lightning")
                # Filter specifically for the main lightningd container, avoiding proxies/apps
                docker_name=$(docker ps --filter name=core-lightning --format "{{.Names}}" | grep "lightningd" | head -n 1)
                
                # Fallback if grep failed but generic name exists
                if [[ -z "$docker_name" ]]; then 
                     docker_name=$(docker ps --filter name=lightningd --format "{{.Names}}" | head -n 1)
                fi
                if [[ -z "$docker_name" ]]; then docker_name="core-lightning_lightningd_1"; fi
                
                node_type="CLN (Docker)"
                if command -v jq &> /dev/null; then
                     local info=$(docker exec "$docker_name" lightning-cli getinfo 2>/dev/null)
                     if [[ -n "$info" ]]; then
                         local pk=$(echo "$info" | jq -r '.id')
                         local ip=$(echo "$info" | jq -r '.address[] | select(.type == "ipv4") | .address' | head -n 1)
                         local port=$(echo "$info" | jq -r '.address[] | select(.type == "ipv4") | .port' | head -n 1)
                         if [[ -n "$pk" && -n "$ip" ]]; then 
                             ext_addr="${pk}@${ip}:${port}"
                         else
                             ext_addr="NONE_DETECTED"
                         fi
                     else
                         ext_addr="NODE_UNREACHABLE"
                     fi
                else
                    ext_addr="DEPENDENCY_MISSING"
                fi
                ;;
            "manual")
                # Attempt to guess
                local original_user="${SUDO_USER:-$(whoami)}"
                
                 if [[ "$target_impl" == "lnd" ]]; then
                    node_type="LND (Systemd)"
                    if command -v lncli &> /dev/null; then
                         local info
                         # Try as sudo user first (RaspiBlitz standard)
                         info=$(sudo -u "$original_user" lncli getinfo 2>/dev/null)
                         
                         # Fallback to common node users with explicit data directory check
                         if [[ -z "$info" ]]; then
                            local users=("$node_user" "lnd" "bitcoin" "admin")
                            for u in "${users[@]}"; do
                                [[ -z "$u" ]] && continue
                                # Try with default paths for that user
                                info=$(sudo -u "$u" lncli getinfo 2>/dev/null)
                                [[ -n "$info" ]] && break
                            done
                         fi
                         
                         if [[ -n "$info" ]]; then
                             ext_addr=$(echo "$info" | jq -r '.uris[]' | grep -v "\.onion" | head -n 1)
                             [[ -z "$ext_addr" ]] && ext_addr="NONE_DETECTED"
                         else
                             ext_addr="NODE_UNREACHABLE"
                         fi
                    else
                         ext_addr="CLI_MISSING"
                    fi
                 elif [[ "$target_impl" == "cln" ]]; then
                    node_type="CLN (Systemd)"
                     if command -v lightning-cli &> /dev/null; then
                         local info
                         info=$(sudo -u "$original_user" lightning-cli getinfo 2>/dev/null)
                         [[ -z "$info" ]] && [[ "$node_user" != "$original_user" ]] && info=$(sudo -u "$node_user" lightning-cli getinfo 2>/dev/null)
                         [[ -z "$info" ]] && info=$(sudo -u bitcoin lightning-cli getinfo 2>/dev/null)
                         [[ -z "$info" ]] && info=$(lightning-cli getinfo 2>/dev/null)
                         
                         if [[ -n "$info" ]]; then
                             local pk=$(echo "$info" | jq -r '.id')
                             local ip=$(echo "$info" | jq -r '.address[] | select(.type == "ipv4") | .address' | head -n 1)
                             local port=$(echo "$info" | jq -r '.address[] | select(.type == "ipv4") | .port' | head -n 1)
                             if [[ -n "$pk" && -n "$ip" ]]; then 
                                 ext_addr="${pk}@${ip}:${port}"
                             else
                                 ext_addr="NONE_DETECTED"
                             fi
                         else
                             ext_addr="NODE_UNREACHABLE"
                         fi
                     else
                         ext_addr="CLI_MISSING"
                     fi
                  elif systemctl is-active --quiet litd || systemctl is-active --quiet lit; then
                    node_type="LIT (Systemd)"
                    if command -v litcli &> /dev/null; then
                         local info
                         info=$(sudo -u "$original_user" litcli getinfo 2>/dev/null)
                         [[ -z "$info" ]] && info=$(litcli getinfo 2>/dev/null)
                         if [[ -n "$info" ]]; then
                             ext_addr=$(echo "$info" | jq -r '.lnd_uris[]' | grep -v "\.onion" | head -n 1)
                             [[ -z "$ext_addr" ]] && ext_addr="NONE_DETECTED"
                         else
                             ext_addr="NODE_UNREACHABLE"
                         fi
                    else
                         ext_addr="CLI_MISSING"
                    fi
                  else
                    node_type="Unknown/Manual"
                  fi
                ;;
        esac
        
        # Check if we actually have jq
        if ! command -v jq &> /dev/null; then
            echo "$node_type|DEPENDENCY_MISSING"
            return 0
        fi

        echo "$node_type|$ext_addr"
    }

    # Execute Checks
    local setup_method=$(check_docker_setup_status)
    local outbound_ip="N/A"
    local inbound_status="N/A" 
    local inbound_ip="N/A"
    
    # 1. Listening Check (Manual/Bare Metal)
    if [[ "$setup_method" == "manual" ]] && [[ -n "$LN_IMPL" ]]; then
        if ss -tulpn | grep -q "127.0.0.1:9735"; then
            print_warning "Node only listening on Localhost (127.0.0.1)!"
        fi
    fi

    # Only run if config is valid
    if [[ -n "$endpoint" && -n "$vpn_port" ]]; then
         outbound_ip=$(perform_outbound_check_status "$setup_method")
         read -r inbound_status inbound_ip <<< "$(perform_inbound_check_status "$endpoint" "$vpn_port")"
    fi

    local node_data=$(get_node_ext_addr_status "$setup_method")
    local node_type=$(echo "$node_data" | cut -d '|' -f 1)
    local node_addr=$(echo "$node_data" | cut -d '|' -f 2)

    local ufw_status_str="Not Installed"
    local ufw_blocked=0
    if command -v ufw >/dev/null 2>&1; then
        local ufw_status_out
        ufw_status_out=$(ufw status 2>/dev/null)
        if echo "$ufw_status_out" | grep -q "Status: active"; then
            if is_port_allowed_in_ufw "$interface_name" "9735" "$ufw_status_out"; then
                ufw_status_str="${GREEN}Active (Port 9735 Allowed)${NC}"
            else
                ufw_status_str="${RED}Active (Port 9735 BLOCKED on ${interface_name})${NC}"
                ufw_blocked=1
            fi
        else
            ufw_status_str="Inactive"
        fi
    fi

    echo -e "${BOLD}Node Configuration${NC}"
    print_line
    echo -e "  Type:           $node_type"
    echo -e "  Public Address: $node_addr"
    echo ""
    
    echo -e "${BOLD}Connectivity Check${NC}"
    print_line
    echo -e "  Outbound IP:    $outbound_ip"
    echo -e "  Inbound Check:  $inbound_status ($inbound_ip)"
    echo -e "  UFW Status:     $ufw_status_str"
    echo ""
    
    # Final Verdict
    local outbound_ok=false
    local inbound_ok=false
    
    if [[ "$outbound_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then outbound_ok=true; fi
    if [[ "$inbound_status" == "success" || "$inbound_status" == "success_no_ip" ]]; then inbound_ok=true; fi
    
    if $outbound_ok && $inbound_ok; then
         print_success "Connectivity Verified"
    elif ! $outbound_ok && ! $inbound_ok; then
         print_error "Connectivity Check Failed (Both directions)"
    elif ! $outbound_ok; then
         print_warning "Outbound Check Failed (Inbound OK)"
    elif ! $inbound_ok; then
         print_warning "Inbound Check Failed (Outbound OK)"
    fi
    echo ""

    if [[ $ufw_blocked -eq 1 ]]; then
        echo ""
        echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD}${YELLOW}⚠  UFW FIREWALL BLOCKING PORT 9735!${NC}"
        echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "Your UFW firewall is active, but it does NOT allow inbound traffic"
        echo "on the Lightning port (9735) via your WireGuard interface (${interface_name})."
        echo ""
        echo "To allow traffic via this interface specifically, run:"
        echo -e "  ${BOLD}sudo ufw allow in on ${interface_name} to any port 9735 proto tcp${NC}"
        echo ""
        echo "Or to allow it globally on all interfaces:"
        echo -e "  ${BOLD}sudo ufw allow 9735/tcp${NC}"
        echo ""
        echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
    fi

    # ---------------------------------------------------------
    # MISCONFIGURATION DETECTION: Node not advertising VPN address
    # Scenario: Tunnel works (inbound/outbound OK) but getinfo shows no VPN URI
    # ---------------------------------------------------------
    if $outbound_ok && $inbound_ok; then
        # ONLY warn if we successfully talked to the node and confirmed it has NO clearnet address
        if [[ "$node_addr" == "NONE_DETECTED" ]] || [[ -z "$node_addr" ]]; then
            echo ""
            echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${BOLD}${YELLOW}⚠  NODE NOT ADVERTISING VPN ADDRESS!${NC}"
            echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo "Your tunnel is working perfectly, but your node isn't configured"
            echo "to announce the VPN address to the Lightning network."
            echo ""
            echo "Other nodes CAN connect to you through the tunnel, but they"
            echo "don't know about your clearnet address (it won't appear in lncli getinfo)."
            echo ""
            echo -e "${BOLD}To fix this, please update your node configuration:${NC}"
            echo ""
            
            # Get VPN endpoint details from config for guidance
            local status_vpn_dns=$(grep "^Endpoint" "$config_file" | awk '{print $3}' | cut -d ':' -f 1)
            local status_vpn_port="$vpn_port"
            
            print_node_config_instructions "$status_vpn_dns" "$status_vpn_port" "status"
            
            echo ""
            echo -e "${BOLD}Then restart your node:${NC}"
            if [[ "$PLATFORM" == "umbrel" ]]; then
                echo "   sudo reboot"
                echo "   (Or restart the Lightning app via Umbrel Dashboard: Right-click -> Restart)"
            else
                local svc="${LN_IMPL}"
                [[ "$LN_IMPL" == "cln" ]] && svc="lightningd"
                if [[ "$LN_IMPL" == "lit" ]]; then
                    # Use systemctl is-active for consistent service detection
                    if systemctl is-active --quiet litd 2>/dev/null; then
                        svc="litd"
                    elif systemctl is-active --quiet lit 2>/dev/null; then
                        svc="lit"
                    else
                        svc="litd"  # Default fallback
                    fi
                fi
                echo "   sudo systemctl restart ${svc}.service"
            fi
            echo ""
            echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
        fi
    fi

    # Iterative Feedback Support: Debug Summary (Simplified for Telegram)
    echo -e "${BOLD}Debug Summary (Copy for Telegram)${NC}"
    print_line
    local os_info=$(cat /etc/os-release | grep -E "^PRETTY_NAME=" | cut -d= -f2 | tr -d '"')
    local status_plain=$(echo -e "${status_msg}" | sed 's/\x1b\[[0-9;]*m//g')
    
    echo -e "Platform: ${PLATFORM} | Lightning: ${LN_IMPL} | Node: ${node_type}"
    echo -e "OS: ${os_info}"
    echo -e "Tunnel: ${status_plain} | Handshake: ${latest_handshake}"
    echo -e "Inbound: ${inbound_status} | Outbound: ${outbound_ip}"
    echo ""
}

# ---------------------------------------------------------------------------
# RESTART COMMAND
# ---------------------------------------------------------------------------
cmd_restart() {
    print_header "Restarting TunnelSats"
    
    # 0. Auto-detect environment
    auto_detect_environment
    
    # 1. Find Config/Interface: same selection as detect and status (--config, tunnelsatsv2.conf,
    # the only tunnelsats-*.conf). Several candidates are asked, never guessed, and a foreign
    # WireGuard interface is never restarted.
    local config_file
    if ! ts_resolve_wg_config; then
        print_error "No TunnelSats configuration found. Pass --config <file> for a config with another name."
        exit 1
    fi
    config_file="$TS_WG_RESOLVED"
    
    local interface_name=$(basename "$config_file" .conf)
    local stopped_containers=""
    local node_stopped_systemd=0
    local service_name="${LN_IMPL}"
    [[ "$LN_IMPL" == "cln" ]] && service_name="lightningd"
    if [[ "$LN_IMPL" == "lit" ]]; then
        service_name="litd"
        systemctl list-units --type=service | grep -q "lit.service" && service_name="lit"
    fi
    
    echo ""
    print_info "Platform: ${PLATFORM:-unknown}, Lightning: ${LN_IMPL:-unknown}"
    print_info "Interface: ${interface_name}"
    echo ""

    # 2. Deactivate Lightning node for safety (Privacy first / Leak-proof)
    if [[ "$PLATFORM" == "umbrel" ]] && [[ -n "$LN_IMPL" ]]; then
        local filter_name="lnd"
        [[ "$LN_IMPL" == "cln" ]] && filter_name="core-lightning"
        
        echo -e "${YELLOW}Umbrel detected. To ensure a leak-proof restart, we need to temporarily${NC}"
        echo -e "${YELLOW}stop your ${LN_IMPL} app containers.${NC}"
        ts_confirm restart_confirm "Do you want to proceed? [y/N]: "
        if [[ ! "$restart_confirm" =~ ^[Yy]$ ]]; then
            print_info "Restart aborted by user."
            exit 0
        fi
        echo ""

        print_info "Stopping ${LN_IMPL} app for safe restart..."
        stopped_containers=$(get_lightning_docker_containers)
        
        if [[ -n "$stopped_containers" ]]; then
            docker stop ${stopped_containers} &>/dev/null
            print_success "${LN_IMPL} app stopped (Leak-proof mode)"
        fi
    elif [[ "$PLATFORM" != "umbrel" ]] && [[ -n "$LN_IMPL" ]]; then
        echo -e "${YELLOW}Non-Docker setup detected. To ensure a leak-proof restart, it is${NC}"
        echo -e "${YELLOW}highly recommended to stop your node service temporarily.${NC}"
        # --yes stops the daemon, which keeps clearnet traffic blocked during the restart.
        # Restarting without stopping it is only possible interactively; non-interactive mode
        # without --yes fails before any change.
        ts_confirm stop_confirm "Stop ${service_name}.service for safe tunnel restart? [y/N]: "
        if [[ "$stop_confirm" =~ ^[Yy]$ ]]; then
            print_info "Stopping ${service_name}.service..."
            if systemctl stop "${service_name}.service"; then
                node_stopped_systemd=1
                print_success "Node stopped (Leak-proof mode)"
            fi
        fi
    fi

    # 3. Restart WireGuard Service
    print_info "Stopping WireGuard interface..."
    if systemctl stop "wg-quick@${interface_name}"; then
        print_success "Interface stopped"
    else
        print_warning "Failed to stop interface (might not be running)"
    fi
    
    sleep 1
    
    print_info "Starting WireGuard interface..."
    if systemctl start "wg-quick@${interface_name}"; then
        print_success "Interface started successfully"
    else
        print_error "Failed to start interface"
        journalctl -n 10 -u "wg-quick@${interface_name}" --no-pager
        exit 1
    fi
    
    # 4. App Restart
    if [[ "$PLATFORM" == "umbrel" ]] && [[ -n "$stopped_containers" ]]; then
        print_info "Restarting ${LN_IMPL} app containers..."
        docker start ${stopped_containers} &>/dev/null
        print_success "${LN_IMPL} app restarted"
    elif [[ "$node_stopped_systemd" -eq 1 ]]; then
        print_info "Starting ${service_name}.service..."
        systemctl start "${service_name}.service"
        print_success "${LN_IMPL} service restarted"
    fi

    # 5. Verify
    echo ""
    print_info "Verifying tunnel state..."
    sleep 2
    if [[ -n "$(wg show ${interface_name} 2>/dev/null)" ]]; then
        print_success "Tunnel Interface is UP"
        echo ""
        print_info "Note: Your node implementation (${LN_IMPL:-unknown}) may take several minutes"
        print_info "to fully initialize and start listening on its ports."
        echo ""
        echo "Please wait a moment, then run this command to verify full connectivity:"
        echo -e "   ${BOLD}sudo bash tunnelsats.sh status${NC}"
    else
        print_error "Tunnel Interface did not come up"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# VERSION COMMAND
# ---------------------------------------------------------------------------

# Prints the sha256 of the running script file; fails if it cannot be computed.
ts_script_sha256() {
    local file="$TS_SCRIPT_PATH" out=""
    if [[ ! -f "$file" ]] || [[ ! -r "$file" ]]; then
        return 1
    fi
    if command -v sha256sum >/dev/null 2>&1; then
        out=$(sha256sum -b "$file" 2>/dev/null) || return 1
    elif command -v shasum >/dev/null 2>&1; then
        out=$(shasum -a 256 "$file" 2>/dev/null) || return 1
    else
        return 1
    fi
    out="${out%% *}"
    if [[ ! "$out" =~ ^[0-9a-f]{64}$ ]]; then
        return 1
    fi
    echo "$out"
}

cmd_version() {
    local sha="" rc=0 errors="[]"
    if ! sha=$(ts_script_sha256); then
        sha=""
        rc=1
    fi
    if [[ "$TS_JSON" -eq 1 ]]; then
        if [[ "$rc" -ne 0 ]]; then
            ts_j_error E_SHA256_UNAVAILABLE operational "Could not compute the sha256 of the running script file"
            errors="[${TS_R}]"
        fi
        ts_j_str_or_null "$sha"
        ts_json_document "$rc" "$errors" "\"tool_sha256\":${TS_R}"
    else
        echo "tunnelsats.sh ${VERSION} (CLI contract ${TS_CONTRACT})"
        if [[ -n "$sha" ]]; then
            echo "sha256: ${sha}"
        else
            print_error "Could not compute the sha256 of the running script file [E_SHA256_UNAVAILABLE]"
        fi
    fi
    exit "$rc"
}

# ---------------------------------------------------------------------------
# DETECT COMMAND (read-only)
# Reports platform hints, Lightning units, an existing TunnelSats install with its artifacts,
# config facts, capabilities and conflicts. Strictly read-only: no writes anywhere (not even
# temporary files, so no here-strings or here-documents), no network, no package or service
# changes. Works without root: whatever cannot be read gets an explicit status such as
# permission_denied instead of a guess. File reads are prefixed with TS_FS_ROOT and commands run
# through WG_BIN, WG_QUICK_BIN, NFT_BIN, IP_BIN and SYSTEMCTL_BIN, so tests use fixture trees
# and stubs.
# ---------------------------------------------------------------------------

TSD_ST=""
TSD_UNREADABLE=0
TSD_IFACES=" tunnelsatsv2 "
TSD_PLATFORM_GUESS=""
TSD_HINT_PLATFORM=()
TSD_HINT_PATH=()
TSD_HINT_STATUS=()
TSD_LN_GUESS=""
TSD_LN_IMPL=()
TSD_LN_UNIT=()
TSD_LN_FILE=()
TSD_LN_ACTIVE=()
TSD_LN_USER=()
TSD_LN_PATH=()
# systemd unit search path in precedence order (admin, runtime, local, vendor); first match wins
TSD_UNIT_DIRS="/etc/systemd/system /run/systemd/system /usr/local/lib/systemd/system /usr/lib/systemd/system /lib/systemd/system"
TSD_ART_ID=()
TSD_ART_LOC=()
TSD_ART_STATUS=()
TSD_ART_DETAIL=()
TSD_ART_SECRET=()
TSD_T51820_STATUS=""
TSD_T51820_FOREIGN=()
TSD_INSTALL_KIND=""
TSD_INSTALL_CANDIDATES=()
TSD_EVIDENCE=()
TSD_MANAGED_STATE=""
TSD_CONF_ID=()
TSD_CONF_STATUS=()
TSD_CONF_DETAIL=()
TSD_CFG_SELECTION="none"
TSD_CFG_CANDIDATES=()

# Sets TSD_ST to present, absent or permission_denied for path $1 (below TS_FS_ROOT).
ts_detect_path_status() {
    local p="${TS_FS_ROOT}$1" dir
    if [[ -e "$p" ]] || [[ -L "$p" ]]; then
        TSD_ST="present"
        return 0
    fi
    # Absent, or hidden behind a directory that may not be searched: check the nearest existing parent
    dir="$p"
    while [[ "$dir" == */* ]]; do
        dir="${dir%/*}"
        if [[ -z "$dir" ]]; then
            break
        fi
        if [[ -e "$dir" ]]; then
            if [[ -d "$dir" ]] && [[ ! -x "$dir" ]]; then
                TSD_ST="permission_denied"
                return 0
            fi
            break
        fi
    done
    TSD_ST="absent"
    return 0
}

# Sets TSD_ST to readable, absent or permission_denied for a file whose content is needed.
ts_detect_read_status() {
    ts_detect_path_status "$1"
    if [[ "$TSD_ST" == "present" ]]; then
        if [[ ! -f "${TS_FS_ROOT}$1" ]]; then
            TSD_ST="absent"
        elif [[ -r "${TS_FS_ROOT}$1" ]]; then
            TSD_ST="readable"
        else
            TSD_ST="permission_denied"
        fi
    fi
    return 0
}

# Records one artifact: $1 = id, $2 = location, $3 = status, $4 = detail, $5 = 1 if it holds keys.
ts_detect_art() {
    TSD_ART_ID+=("$1")
    TSD_ART_LOC+=("$2")
    TSD_ART_STATUS+=("$3")
    TSD_ART_DETAIL+=("${4:-}")
    TSD_ART_SECRET+=("${5:-0}")
}

# Records artifact $1 for path $2 ($3 = 1 if it holds keys).
ts_detect_art_path() {
    ts_detect_path_status "$2"
    ts_detect_art "$1" "$2" "$TSD_ST" "" "${3:-0}"
}

# Records every entry of directory $2 matching glob $3 as artifact $1 ($4 = 1 if they hold keys),
# or a single entry with the pattern when nothing matches or the directory cannot be listed.
ts_detect_art_glob() {
    local id="$1" dir="$2" pattern="$3" secret="${4:-0}" full="${TS_FS_ROOT}$2" entry found=0
    ts_detect_path_status "$dir"
    if [[ "$TSD_ST" == "present" ]] && { [[ ! -r "$full" ]] || [[ ! -x "$full" ]]; }; then
        TSD_ST="permission_denied"
    fi
    if [[ "$TSD_ST" != "present" ]]; then
        ts_detect_art "$id" "${dir}/${pattern}" "$TSD_ST" "" "$secret"
        return 0
    fi
    # $pattern is unquoted on purpose: it is the glob to expand
    # shellcheck disable=SC2086
    for entry in "$full"/$pattern; do
        if [[ -e "$entry" ]] || [[ -L "$entry" ]]; then
            found=1
            ts_detect_art "$id" "${entry#"$TS_FS_ROOT"}" "present" "" "$secret"
        fi
    done
    if [[ "$found" -eq 0 ]]; then
        ts_detect_art "$id" "${dir}/${pattern}" "absent" "" "$secret"
    fi
    return 0
}

# Adds evidence id $1 for the install classification (once).
ts_detect_evidence() {
    local item
    for item in "${TSD_EVIDENCE[@]}"; do
        if [[ "$item" == "$1" ]]; then
            return 0
        fi
    done
    TSD_EVIDENCE+=("$1")
}

ts_detect_conflict() {
    TSD_CONF_ID+=("$1")
    TSD_CONF_STATUS+=("$2")
    TSD_CONF_DETAIL+=("${3:-}")
}

ts_valid_wg_key() {
    [[ "$1" =~ ^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=$ ]]
}

# Derives the WireGuard public key from private key $1 with "wg pubkey". The private key goes
# through stdin (never an argument of an external command) and is never printed.
ts_derive_wg_pubkey() {
    local pub=""
    pub=$(printf '%s\n' "$1" | "$WG_BIN" pubkey 2>/dev/null) || return 1
    if ! ts_valid_wg_key "$pub"; then
        return 1
    fi
    echo "$pub"
}

# Sets TSD_ST to the systemctl is-active state of unit $1 ("unavailable" without systemctl).
ts_detect_unit_active() {
    local out=""
    if ! command -v "$SYSTEMCTL_BIN" >/dev/null 2>&1; then
        TSD_ST="unavailable"
        return 0
    fi
    out=$("$SYSTEMCTL_BIN" is-active "$1" 2>/dev/null) || true
    out="${out%%$'\n'*}"
    case "$out" in
        active|inactive|failed|activating|deactivating|reloading|maintenance|refreshing) TSD_ST="$out" ;;
        *) TSD_ST="unknown" ;;
    esac
    return 0
}

# Succeeds if systemd state $1 means that the unit runs (or is starting, stopping or reloading).
ts_detect_unit_running() {
    case "$1" in
        active|activating|deactivating|reloading|refreshing) return 0 ;;
    esac
    return 1
}

# Succeeds if unit file $1 (below TS_FS_ROOT) is masked: systemd treats a symlink to /dev/null
# (systemctl mask) and an empty unit file as masked, so the unit cannot be started.
ts_detect_unit_masked() {
    local p="${TS_FS_ROOT}$1" target=""
    if [[ -L "$p" ]]; then
        target=$(readlink "$p" 2>/dev/null) || target=""
        if [[ "$target" == "/dev/null" ]]; then
            return 0
        fi
    fi
    [[ -f "$p" ]] && [[ ! -s "$p" ]]
}

ts_detect_platform() {
    local marker platform rest
    TSD_PLATFORM_GUESS=$(ts_guess_platform "$TS_FS_ROOT")
    for marker in "${TS_PLATFORM_MARKERS[@]}"; do
        platform="${marker%% *}"
        rest="${marker#* }"
        ts_detect_path_status "${rest#* }"
        TSD_HINT_PLATFORM+=("$platform")
        TSD_HINT_PATH+=("${rest#* }")
        TSD_HINT_STATUS+=("$TSD_ST")
    done
}

ts_detect_lightning() {
    local entry impl unit dir found file_status user
    # The guess is what the installer would detect (unit file in /etc/systemd/system or active unit)
    TSD_LN_GUESS=$(ts_guess_ln_impl_systemd "$TS_FS_ROOT")
    for entry in lnd:lnd.service cln:lightningd.service lit:litd.service lit:lit.service; do
        impl="${entry%%:*}"
        unit="${entry#*:}"
        found=""
        file_status="absent"
        user=""
        # Unit file in any unit directory: packages install them under /usr/lib/systemd/system
        # $TSD_UNIT_DIRS is split into words on purpose
        # shellcheck disable=SC2086
        for dir in $TSD_UNIT_DIRS; do
            ts_detect_path_status "${dir}/${unit}"
            if [[ "$TSD_ST" == "present" ]]; then
                found="${dir}/${unit}"
                file_status="present"
                # systemctl mask hides every other unit file of the same name
                if ts_detect_unit_masked "$found"; then
                    file_status="masked"
                fi
                break
            fi
            if [[ "$TSD_ST" == "permission_denied" ]]; then
                file_status="permission_denied"
            fi
        done
        if [[ "$file_status" == "present" ]] && [[ -r "${TS_FS_ROOT}${found}" ]]; then
            user=$(grep -Ei '^[[:space:]]*User[[:space:]]*=' "${TS_FS_ROOT}${found}" 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '[:space:]') || user=""
            if [[ ! "$user" =~ ^[a-z_][a-z0-9_.-]{0,31}$ ]]; then
                user=""
            fi
        fi
        ts_detect_unit_active "$unit"
        TSD_LN_IMPL+=("$impl")
        TSD_LN_UNIT+=("$unit")
        TSD_LN_FILE+=("$file_status")
        TSD_LN_PATH+=("$found")
        TSD_LN_ACTIVE+=("$TSD_ST")
        TSD_LN_USER+=("$user")
    done
}

# Lightning drop-in $1: v2 wrote Requires=, v3 writes Wants= for tunnelsats-create-cgroup.service.
ts_detect_ln_dropin() {
    local path="$1" detail=""
    ts_detect_read_status "$path"
    case "$TSD_ST" in
        readable)
            TSD_ST="present"
            if grep -qE '^[[:space:]]*Requires[[:space:]]*=[[:space:]]*tunnelsats-create-cgroup\.service' "${TS_FS_ROOT}${path}" 2>/dev/null; then
                detail="requires"
            elif grep -qE '^[[:space:]]*Wants[[:space:]]*=[[:space:]]*tunnelsats-create-cgroup\.service' "${TS_FS_ROOT}${path}" 2>/dev/null; then
                detail="wants"
            else
                detail="unrecognized"
            fi
            ;;
        permission_denied)
            ts_detect_path_status "$path"
            if [[ "$TSD_ST" == "present" ]]; then
                detail="unreadable"
            fi
            ;;
    esac
    ts_detect_art ln_dropin "$path" "$TSD_ST" "$detail"
}

# In-place edits of Lightning unit $1: cgexec in ExecStart, RaspiBlitz check commented out.
ts_detect_ln_unit_edits() {
    local path="$1"
    ts_detect_read_status "$path"
    case "$TSD_ST" in
        absent) return 0 ;;
        permission_denied)
            ts_detect_art ln_unit_cgexec "$path" "permission_denied"
            ts_detect_art ln_unit_check_disabled "$path" "permission_denied"
            return 0
            ;;
    esac
    if grep -qE '^[[:space:]]*ExecStart[[:space:]]*=.*cgexec' "${TS_FS_ROOT}${path}" 2>/dev/null; then
        ts_detect_art ln_unit_cgexec "$path" "present"
    else
        ts_detect_art ln_unit_cgexec "$path" "absent"
    fi
    if grep -qE '^[[:space:]]*#[[:space:]]*ExecStartPre[[:space:]]*=.*(lnd|cl)\.check\.sh' "${TS_FS_ROOT}${path}" 2>/dev/null; then
        ts_detect_art ln_unit_check_disabled "$path" "present"
    else
        ts_detect_art ln_unit_check_disabled "$path" "absent"
    fi
}

ts_detect_ip_rules() {
    local out="" rc=0 line st_main="absent" st_mark="absent" st_legacy="absent" st_failclosed="absent"
    if ! command -v "$IP_BIN" >/dev/null 2>&1; then
        st_main="unavailable"
        st_mark="unavailable"
        st_legacy="unavailable"
        st_failclosed="unavailable"
    else
        out=$("$IP_BIN" -4 rule show 2>/dev/null) || rc=$?
        if [[ "$rc" -ne 0 ]]; then
            st_main="error"
            st_mark="error"
            st_legacy="error"
            st_failclosed="error"
        else
            while IFS= read -r line; do
                case "$line" in
                    "21820:"*"from all lookup main suppress_prefixlength 0"*) st_main="present" ;;
                    "21821:"*"lookup 51820"*) st_mark="present" ;;
                    "21818:"*"blackhole"*|"21819:"*"blackhole"*) st_failclosed="present" ;;
                    *"from all fwmark 0x1000000/0xff000000 lookup 51820"*) st_legacy="present" ;;
                esac
            done < <(printf '%s\n' "$out")
        fi
    fi
    ts_detect_art ip_rule "ip -4 rule 21820 (lookup main suppress_prefixlength 0)" "$st_main"
    ts_detect_art ip_rule "ip -4 rule 21821 (lookup 51820)" "$st_mark"
    ts_detect_art ip_rule_legacy "ip -4 rule fwmark 0x1000000/0xff000000 lookup 51820 (other priority)" "$st_legacy"
    ts_detect_art failclosed_rules "ip -4 rule 21818/21819 blackhole" "$st_failclosed"
}

ts_detect_nft_tables() {
    local out="" rc=0 line found=0
    if ! command -v "$NFT_BIN" >/dev/null 2>&1; then
        ts_detect_art nft_table "nft tables" "unavailable"
        return 0
    fi
    out=$("$NFT_BIN" list tables 2>&1) || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        if [[ "$EUID" -ne 0 ]] || [[ "$out" == *"Operation not permitted"* ]]; then
            ts_detect_art nft_table "nft tables" "permission_denied" "listing tables needs root"
        else
            ts_detect_art nft_table "nft tables" "error"
        fi
        return 0
    fi
    while IFS= read -r line; do
        if [[ "$line" =~ ^table[[:space:]]+(ip|ip6|inet)[[:space:]]+(tunnelsats[A-Za-z0-9_.-]*)[[:space:]]*$ ]]; then
            found=1
            ts_detect_art nft_table "nft table ${BASH_REMATCH[1]} ${BASH_REMATCH[2]}" "present"
        fi
    done < <(printf '%s\n' "$out")
    if [[ "$found" -eq 0 ]]; then
        ts_detect_art nft_table "nft table tunnelsats*" "absent"
    fi
}

ts_detect_wg_links() {
    local out="" rc=0 line found=0
    if ! command -v "$IP_BIN" >/dev/null 2>&1; then
        ts_detect_art wg_interface "wireguard link tunnelsats*" "unavailable"
        return 0
    fi
    out=$("$IP_BIN" -o link show type wireguard 2>/dev/null) || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        ts_detect_art wg_interface "wireguard link tunnelsats*" "error"
        return 0
    fi
    while IFS= read -r line; do
        if [[ "$line" =~ ^[0-9]+:[[:space:]]+(tunnelsats[A-Za-z0-9_.=+-]*)[:@] ]]; then
            found=1
            ts_detect_art wg_interface "wireguard link ${BASH_REMATCH[1]}" "present"
        fi
    done < <(printf '%s\n' "$out")
    if [[ "$found" -eq 0 ]]; then
        ts_detect_art wg_interface "wireguard link tunnelsats*" "absent"
    fi
}

# Routes in table 51820, judged with the route guard's own filter (ts_table51820_filter_foreign):
# the kill-switch blackhole and routes via the selected TunnelSats interface are owned, everything
# else is foreign.
ts_detect_table51820() {
    local out="" rc=0 line owned=0 iface="" foreign="" total=0
    TSD_T51820_FOREIGN=()
    # Ownership follows the route guard: only the interface of the selected config (the same rule
    # as status and restart) and the kill-switch blackhole are TunnelSats routes. Without any
    # config, the interface a fresh install creates (tunnelsatsv2) is the one the guard would check.
    ts_select_wg_config "" "$TS_FS_ROOT" "/etc/wireguard"
    case "$TS_WG_SELECTION" in
        canonical|single)
            iface="${TS_WG_SELECTED##*/}"
            iface="${iface%.conf}"
            ;;
        none) iface="tunnelsatsv2" ;;
        *) iface="" ;;
    esac
    TSD_IFACES=" ${iface} "
    if ! command -v "$IP_BIN" >/dev/null 2>&1; then
        TSD_T51820_STATUS="unavailable"
        ts_detect_art table_51820_route "ip -4 route table 51820" "unavailable"
        return 0
    fi
    out=$("$IP_BIN" route show table 51820 2>&1) || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        if [[ "$out" != *"FIB table does not exist"* ]]; then
            TSD_T51820_STATUS="error"
            ts_detect_art table_51820_route "ip -4 route table 51820" "error"
            return 0
        fi
        out=""
    fi
    while IFS= read -r line; do
        if [[ -n "${line//[[:space:]]/}" ]]; then
            total=$((total + 1))
        fi
    done < <(printf '%s\n' "$out")
    foreign=$(printf '%s\n' "$out" | ts_table51820_filter_foreign "$iface")
    while IFS= read -r line; do
        # The managed kill switch blackhole is a TunnelSats route as well
        if [[ -n "${line//[[:space:]]/}" ]] && ! ts_m_is_blackhole_line "$line"; then
            TSD_T51820_FOREIGN+=("$line")
        fi
    done < <(printf '%s\n' "$foreign")
    owned=$((total - ${#TSD_T51820_FOREIGN[@]}))
    if [[ -z "$iface" ]] && [[ "${#TSD_T51820_FOREIGN[@]}" -gt 0 ]]; then
        # Several configs (or an unreadable directory): which tunnel owns these routes cannot be
        # decided, so the conflict check reports unknown instead of guessing either way
        TSD_T51820_STATUS="selection_${TS_WG_SELECTION}"
        TSD_T51820_FOREIGN=()
    else
        TSD_T51820_STATUS="ok"
    fi
    if [[ "$owned" -gt 0 ]]; then
        ts_detect_art table_51820_route "ip -4 route table 51820" "present" "${owned} route(s) via TunnelSats"
    else
        ts_detect_art table_51820_route "ip -4 route table 51820" "absent"
    fi
}

ts_detect_artifacts() {
    local wg="/etc/wireguard" sd="/etc/systemd/system" name unit
    # WireGuard configs and the sanitizer's backups hold the private key
    ts_detect_art_path wg_config "${wg}/tunnelsatsv2.conf" 1
    ts_detect_art_glob wg_config "$wg" "tunnelsats-*.conf" 1
    ts_detect_art_glob wg_config_backup "$wg" "tunnelsats*.conf.bak.*" 1
    # Route guard (since #204), helper scripts and state files
    ts_detect_art_path route_guard_script "${wg}/tunnelsats-route-guard.sh"
    for name in tunnelsats-create-cgroup.sh tunnelsats-splitting-processes.sh tunnelsats-resolve-dns-wg.sh tunnelsats-docker-network.sh; do
        ts_detect_art_path helper_script "${wg}/${name}"
    done
    ts_detect_art_path failclosed_state "${wg}/.tunnelsats-failclosed-rules"
    ts_detect_art_glob ufw_marker "$wg" ".tunnelsats-ufw-9735-*.created"
    # systemd units, timers and drop-ins
    for unit in tunnelsats-create-cgroup.service tunnelsats-splitting-processes.service \
        tunnelsats-splitting-processes.timer tunnelsats-resolve-dns-wg.service \
        tunnelsats-resolve-dns-wg.timer tunnelsats-docker-network.service tunnelsats-docker-network.timer; do
        ts_detect_art_path unit "${sd}/${unit}"
    done
    ts_detect_art_glob wg_quick_enabled "${sd}/multi-user.target.wants" "wg-quick@tunnelsats*.service"
    ts_detect_art_glob wg_quick_dropin "$sd" "wg-quick@tunnelsats*.service.d"
    for unit in lnd.service lightningd.service litd.service lit.service; do
        ts_detect_ln_dropin "${sd}/${unit}.d/tunnelsats-cgroup.conf"
        ts_detect_ln_unit_edits "${sd}/${unit}"
        ts_detect_art_path ln_unit_backup "${sd}/${unit}.bak"
    done
    ts_detect_art_path blitzapi_dropin "${sd}/blitzapi.service.d/tunnelsats-wg.conf"
    ts_detect_art_path umbrel_killswitch_dropin "${sd}/umbrel.service.d/tunnelsats_killswitch.conf"
    ts_detect_art_path umbrel_killswitch_dropin "${sd}/umbrel-startup.service.d/tunnelsats_killswitch.conf"
    # Left behind by the v2 installer
    ts_detect_art_path raspiblitz_check_renamed "/home/admin/config.scripts/lnd.check.bak"
    ts_detect_art_path raspiblitz_check_renamed "/home/admin/config.scripts/cl.check.bak"
    ts_detect_art_path nftables_conf_backup "/etc/nftablespriortunnelsats.backup"
    # Managed mode (install --managed): inventory, units, drop-ins, script copy, attestation
    ts_detect_art_path managed_inventory "$TS_M_INVENTORY"
    for unit in "$TS_M_SLICE_UNIT" "$TS_M_KILLSWITCH_UNIT" "$TS_M_VERIFIER_UNIT" "$TS_M_TIMER_UNIT"; do
        ts_detect_art_path managed_unit "${sd}/${unit}"
    done
    # The drop-in of every unit a managed profile can tunnel (RaspiBlitz testnet and signet units too)
    for name in $TS_M_ALL_LN_UNITS; do
        ts_detect_art_path managed_ln_dropin "${sd}/${name#*:}.d/${TS_M_DROPIN_NAME}"
    done
    ts_detect_art_path managed_script "$TS_M_BIN"
    ts_detect_art_path managed_attestation "$TS_M_ATTEST"
    # Kernel state (read-only queries)
    ts_detect_ip_rules
    ts_detect_nft_tables
    ts_detect_wg_links
    ts_detect_table51820
}

# Splits WireGuard Endpoint $1 into TSD_CFG_EP_HOST and TSD_CFG_EP_PORT; fails if it is invalid.
ts_detect_parse_endpoint() {
    local ep="$1" host="" port=""
    local re_v6='^\[([0-9A-Fa-f:.]+)\]:([0-9]{1,5})$'
    local re_host='^([A-Za-z0-9.-]{1,253}):([0-9]{1,5})$'
    local re_name='^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$'
    if [[ "$ep" =~ $re_v6 ]]; then
        host="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
    elif [[ "$ep" =~ $re_host ]]; then
        host="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
        if [[ ! "$host" =~ $re_name ]]; then
            return 1
        fi
    else
        return 1
    fi
    if (( 10#$port < 1 || 10#$port > 65535 )); then
        return 1
    fi
    TSD_CFG_EP_HOST="$host"
    TSD_CFG_EP_PORT="$((10#$port))"
    return 0
}

# Facts from the WireGuard config in use. The private key is read into memory only to derive
# the public key and is never printed.
ts_detect_config() {
    local i rel="" full line trimmed section="" key val privkey="" endpoint="" pub="" comment="" valid=""
    local re_iso='^[0-9]{4}-[0-9]{2}-[0-9]{2}([T ][0-9]{2}:[0-9]{2}(:[0-9]{2}(\.[0-9]{1,9})?)?)?(Z|[+-][0-9]{2}(:?[0-9]{2})?)?$'
    TSD_CFG_PATH=""
    TSD_CFG_STATUS="absent"
    TSD_CFG_IFACE=""
    TSD_CFG_MARKER=""
    TSD_CFG_MARKERS=0
    TSD_CFG_EP_HOST=""
    TSD_CFG_EP_PORT=""
    TSD_CFG_EP_STATUS="not_read"
    TSD_CFG_VPN_PORT=""
    TSD_CFG_VPN_PORT_STATUS="not_read"
    TSD_CFG_PUB=""
    TSD_CFG_PUB_STATUS="not_read"
    TSD_CFG_PUB_COMMENT=""
    TSD_CFG_PUB_COMMENT_STATUS="not_read"
    TSD_CFG_PUB_MATCH=""
    TSD_CFG_VALID_UNTIL=""
    TSD_CFG_VALID_UNTIL_STATUS="not_read"
    TSD_CFG_HOOK_GUARD="not_read"
    TSD_CFG_HOOK_KILLSWITCH="not_read"

    # The config in use: the same rule as status, restart and uninstall (ts_select_wg_config).
    # Several tunnelsats-*.conf without tunnelsatsv2.conf are ambiguous: no facts are read then.
    ts_select_wg_config "" "$TS_FS_ROOT" "/etc/wireguard"
    TSD_CFG_SELECTION="$TS_WG_SELECTION"
    TSD_CFG_CANDIDATES=("${TS_WG_CANDIDATES[@]}")
    case "$TS_WG_SELECTION" in
        canonical|single) rel="$TS_WG_SELECTED" ;;
        ambiguous)
            TSD_CFG_STATUS="ambiguous"
            return 0
            ;;
        permission_denied)
            TSD_CFG_STATUS="permission_denied"
            return 0
            ;;
        *) return 0 ;;
    esac
    TSD_CFG_PATH="$rel"
    TSD_CFG_IFACE="${rel##*/}"
    TSD_CFG_IFACE="${TSD_CFG_IFACE%.conf}"
    ts_detect_read_status "$rel"
    if [[ "$TSD_ST" != "readable" ]]; then
        TSD_CFG_STATUS="$TSD_ST"
        return 0
    fi
    TSD_CFG_STATUS="ok"
    full="${TS_FS_ROOT}${rel}"
    TSD_CFG_HOOK_GUARD="absent"
    TSD_CFG_HOOK_KILLSWITCH="none"
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        case "$line" in
            "#Tunnelsats-Setupv2-Non-Docker"*|"#Tunnelsats-Setupv2-Docker"*)
                TSD_CFG_MARKERS=$((TSD_CFG_MARKERS + 1))
                if [[ -z "$TSD_CFG_MARKER" ]] && [[ "$line" == "#Tunnelsats-Setupv2-Docker"* ]]; then
                    TSD_CFG_MARKER="docker"
                elif [[ -z "$TSD_CFG_MARKER" ]]; then
                    TSD_CFG_MARKER="non_docker"
                fi
                ;;
        esac
        trimmed="${line#"${line%%[![:space:]]*}"}"
        if [[ "$trimmed" =~ ^\[([A-Za-z]+)\] ]]; then
            section="${BASH_REMATCH[1],,}"
            continue
        fi
        if [[ ! "$trimmed" =~ ^([A-Za-z]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            continue
        fi
        key="${BASH_REMATCH[1],,}"
        val="${BASH_REMATCH[2]}"
        case "$key" in
            privatekey)
                if [[ "$section" == "interface" ]] && [[ -z "$privkey" ]]; then
                    privkey="${val%%[[:space:]#]*}"
                fi
                ;;
            endpoint)
                if [[ "$section" == "peer" ]] && [[ -z "$endpoint" ]]; then
                    endpoint="${val%%[[:space:]#]*}"
                fi
                ;;
            postup)
                if [[ "$val" == *"tunnelsats-route-guard.sh"* ]]; then
                    TSD_CFG_HOOK_GUARD="present"
                fi
                if [[ "$val" == *"skuid"* ]]; then
                    if [[ "$val" == *"meta cgroup 1118498"* ]]; then
                        TSD_CFG_HOOK_KILLSWITCH="skuid_cgroup"
                    elif [[ "$TSD_CFG_HOOK_KILLSWITCH" != "skuid_cgroup" ]]; then
                        TSD_CFG_HOOK_KILLSWITCH="skuid_only"
                    fi
                fi
                ;;
        esac
    done < "$full"

    if [[ -z "$endpoint" ]]; then
        TSD_CFG_EP_STATUS="missing"
    elif ts_detect_parse_endpoint "$endpoint"; then
        TSD_CFG_EP_STATUS="ok"
    else
        TSD_CFG_EP_STATUS="invalid"
    fi

    # Forwarded VPN port from "# Port Forwarding: N" (or "#VPNPort = N"). The complete value is
    # checked: 100000 is invalid (not 10000) and 80 is valid (not missing).
    TSD_CFG_VPN_PORT=$(parse_config_metadata "$full" port) || TSD_CFG_VPN_PORT=""
    if [[ -z "$TSD_CFG_VPN_PORT" ]]; then
        TSD_CFG_VPN_PORT_STATUS="missing"
    elif TSD_CFG_VPN_PORT=$(ts_normalize_port "$TSD_CFG_VPN_PORT"); then
        TSD_CFG_VPN_PORT_STATUS="ok"
    else
        TSD_CFG_VPN_PORT=""
        TSD_CFG_VPN_PORT_STATUS="invalid"
    fi

    # Public key in use: derived from PrivateKey, never taken from a comment
    if [[ -z "$privkey" ]]; then
        TSD_CFG_PUB_STATUS="no_private_key"
    elif ! ts_valid_wg_key "$privkey"; then
        TSD_CFG_PUB_STATUS="invalid_private_key"
    elif ! command -v "$WG_BIN" >/dev/null 2>&1; then
        TSD_CFG_PUB_STATUS="wg_unavailable"
    elif pub=$(ts_derive_wg_pubkey "$privkey"); then
        TSD_CFG_PUB="$pub"
        TSD_CFG_PUB_STATUS="derived"
    else
        TSD_CFG_PUB_STATUS="derive_failed"
    fi
    privkey=""

    # The myPubKey comment is only a hint and can be stale
    comment=$(parse_config_metadata "$full" pubkey) || comment=""
    if [[ -z "$comment" ]]; then
        TSD_CFG_PUB_COMMENT_STATUS="missing"
    elif ts_valid_wg_key "$comment"; then
        TSD_CFG_PUB_COMMENT="$comment"
        TSD_CFG_PUB_COMMENT_STATUS="ok"
        if [[ -n "$TSD_CFG_PUB" ]] && [[ "$TSD_CFG_PUB" == "$comment" ]]; then
            TSD_CFG_PUB_MATCH="true"
        elif [[ -n "$TSD_CFG_PUB" ]]; then
            TSD_CFG_PUB_MATCH="false"
        fi
    else
        TSD_CFG_PUB_COMMENT_STATUS="invalid"
    fi

    # Valid Until is a display hint; the TunnelSats API is the source of truth
    valid=$(parse_config_metadata "$full" expiry) || valid=""
    if [[ -z "$valid" ]]; then
        TSD_CFG_VALID_UNTIL_STATUS="missing"
    elif [[ "$valid" =~ $re_iso ]]; then
        TSD_CFG_VALID_UNTIL="$valid"
        TSD_CFG_VALID_UNTIL_STATUS="ok"
    else
        TSD_CFG_VALID_UNTIL_STATUS="invalid"
    fi
}

# Classifies the existing install (R2 7.5). A managed install (its inventory) comes first; otherwise
# the newest generation with positive evidence wins: legacy_v3_post_204 (route guard, #204),
# legacy_v3_pre_204, legacy_v2. "unknown" lists the kinds the readable evidence cannot tell apart;
# "none" requires that nothing was unreadable.
ts_detect_install_kind() {
    local i id status detail any_present=0 any_unreadable=0 v2=0 v3=0 pre=0 post=0 managed=0 managed_art=0
    TSD_EVIDENCE=()
    TSD_MANAGED_STATE=""
    for i in "${!TSD_ART_ID[@]}"; do
        id="${TSD_ART_ID[$i]}"
        status="${TSD_ART_STATUS[$i]}"
        detail="${TSD_ART_DETAIL[$i]}"
        case "$status" in
            present)
                if [[ "$id" != "managed_script" ]]; then
                    any_present=1
                fi
                ;;
            permission_denied|error) any_unreadable=1; continue ;;
            *) continue ;;
        esac
        case "$id" in
            managed_inventory) managed=1; ts_detect_evidence managed_inventory ;;
            managed_unit|managed_ln_dropin|managed_attestation) managed_art=1; ts_detect_evidence managed_artifacts ;;
            raspiblitz_check_renamed) v2=1; ts_detect_evidence v2_check_script_renamed ;;
            umbrel_killswitch_dropin) v2=1; ts_detect_evidence v2_umbrel_killswitch ;;
            nftables_conf_backup) v2=1; ts_detect_evidence v2_nftables_conf_backup ;;
            ln_dropin)
                if [[ "$detail" == "requires" ]]; then
                    v2=1
                    ts_detect_evidence v2_dropin_requires
                elif [[ "$detail" == "wants" ]]; then
                    v3=1
                    ts_detect_evidence v3_dropin_wants
                fi
                ;;
            ln_unit_check_disabled) v3=1; ts_detect_evidence v3_check_disabled_in_unit ;;
            ufw_marker) v3=1; ts_detect_evidence v3_ufw_marker ;;
            route_guard_script) post=1; ts_detect_evidence route_guard_script ;;
            wg_config_backup) post=1; ts_detect_evidence config_backup_copies ;;
            failclosed_state|failclosed_rules) post=1; ts_detect_evidence failclosed_block ;;
            ip_rule) post=1; ts_detect_evidence rule_priorities_21820_21821 ;;
            ip_rule_legacy) pre=1; ts_detect_evidence legacy_rule_selectors ;;
            nft_table)
                if [[ "${TSD_ART_LOC[$i]}" == *"tunnelsats_failclosed"* ]]; then
                    post=1
                    ts_detect_evidence failclosed_block
                fi
                ;;
        esac
    done
    if [[ "$TSD_CFG_STATUS" == "ok" ]]; then
        if [[ "$TSD_CFG_HOOK_KILLSWITCH" == "skuid_only" ]]; then
            v2=1
            ts_detect_evidence v2_killswitch_uid_only
        elif [[ "$TSD_CFG_HOOK_KILLSWITCH" == "skuid_cgroup" ]]; then
            v3=1
            ts_detect_evidence v3_killswitch_uid_cgroup
        fi
        if [[ "$TSD_CFG_HOOK_GUARD" == "present" ]]; then
            post=1
            ts_detect_evidence route_guard_hook
        elif [[ -n "$TSD_CFG_MARKER" ]]; then
            pre=1
            ts_detect_evidence config_without_route_guard
        fi
    fi

    if [[ "$managed" -eq 1 ]]; then
        TSD_INSTALL_KIND="managed"
        TSD_INSTALL_CANDIDATES=(managed)
        TSD_MANAGED_STATE=$(ts_m_inventory_state)
    elif [[ "$managed_art" -eq 1 ]]; then
        # Managed units or files without the inventory that lists them
        TSD_INSTALL_KIND="unknown"
        TSD_INSTALL_CANDIDATES=(managed)
    elif [[ "$post" -eq 1 ]]; then
        TSD_INSTALL_KIND="legacy_v3_post_204"
        TSD_INSTALL_CANDIDATES=(legacy_v3_post_204)
    elif [[ "$v3" -eq 1 ]] && [[ "$pre" -eq 1 ]]; then
        TSD_INSTALL_KIND="legacy_v3_pre_204"
        TSD_INSTALL_CANDIDATES=(legacy_v3_pre_204)
    elif [[ "$v3" -eq 1 ]]; then
        TSD_INSTALL_KIND="unknown"
        TSD_INSTALL_CANDIDATES=(legacy_v3_pre_204 legacy_v3_post_204)
    elif [[ "$v2" -eq 1 ]]; then
        TSD_INSTALL_KIND="legacy_v2"
        TSD_INSTALL_CANDIDATES=(legacy_v2)
    elif [[ "$pre" -eq 1 ]]; then
        TSD_INSTALL_KIND="unknown"
        TSD_INSTALL_CANDIDATES=(legacy_v2 legacy_v3_pre_204)
    elif [[ "$any_present" -eq 1 ]]; then
        TSD_INSTALL_KIND="unknown"
        TSD_INSTALL_CANDIDATES=(legacy_v2 legacy_v3_pre_204 legacy_v3_post_204)
    elif [[ "$any_unreadable" -eq 1 ]]; then
        TSD_INSTALL_KIND="unknown"
        TSD_INSTALL_CANDIDATES=(none legacy_v2 legacy_v3_pre_204 legacy_v3_post_204)
    else
        TSD_INSTALL_KIND="none"
        TSD_INSTALL_CANDIDATES=(none)
    fi
}

ts_detect_capabilities() {
    local out="" path dev mountpoint fstype options rest
    TSD_CAP_WG="missing"
    TSD_CAP_WG_VERSION=""
    TSD_CAP_WG_QUICK="missing"
    TSD_CAP_WG_UNIT="absent"
    TSD_CAP_NFT="missing"
    TSD_CAP_NFT_VERSION=""
    TSD_CAP_SYSTEMD="missing"
    TSD_CAP_SYSTEMD_VERSION=""
    TSD_CAP_CG2="unknown"
    TSD_CAP_CG2_MP=""
    TSD_CAP_NETCLS="unknown"
    TSD_CAP_NETCLS_MP=""
    TSD_CAP_KERNEL=""
    if command -v "$WG_BIN" >/dev/null 2>&1; then
        TSD_CAP_WG="present"
        out=$("$WG_BIN" --version 2>/dev/null) || out=""
        if [[ "$out" =~ v([0-9]+(\.[0-9]+)+) ]]; then
            TSD_CAP_WG_VERSION="${BASH_REMATCH[1]}"
        fi
    fi
    if command -v "$WG_QUICK_BIN" >/dev/null 2>&1; then
        TSD_CAP_WG_QUICK="present"
    fi
    for path in /lib/systemd/system/wg-quick@.service /usr/lib/systemd/system/wg-quick@.service /etc/systemd/system/wg-quick@.service; do
        ts_detect_path_status "$path"
        if [[ "$TSD_ST" == "present" ]]; then
            TSD_CAP_WG_UNIT="present"
            break
        fi
        if [[ "$TSD_ST" == "permission_denied" ]]; then
            TSD_CAP_WG_UNIT="permission_denied"
        fi
    done
    if command -v "$NFT_BIN" >/dev/null 2>&1; then
        TSD_CAP_NFT="present"
        out=$("$NFT_BIN" --version 2>/dev/null) || out=""
        if [[ "$out" =~ v([0-9]+(\.[0-9]+)+) ]]; then
            TSD_CAP_NFT_VERSION="${BASH_REMATCH[1]}"
        fi
    fi
    if command -v "$SYSTEMCTL_BIN" >/dev/null 2>&1; then
        TSD_CAP_SYSTEMD="present"
        out=$("$SYSTEMCTL_BIN" --version 2>/dev/null) || out=""
        if [[ "$out" =~ ^systemd[[:space:]]+([0-9]+) ]]; then
            TSD_CAP_SYSTEMD_VERSION="${BASH_REMATCH[1]}"
        fi
    fi
    # cgroup hierarchies from the mount table (no cgroup is created or modified)
    if [[ -r "${TS_FS_ROOT}/proc/mounts" ]]; then
        TSD_CAP_CG2="not_mounted"
        TSD_CAP_NETCLS="not_mounted"
        while read -r dev mountpoint fstype options rest; do
            if [[ "$fstype" == "cgroup2" ]] && [[ -z "$TSD_CAP_CG2_MP" ]]; then
                TSD_CAP_CG2="mounted"
                TSD_CAP_CG2_MP="$mountpoint"
            elif [[ "$fstype" == "cgroup" ]] && [[ ",${options}," == *",net_cls,"* ]] && [[ -z "$TSD_CAP_NETCLS_MP" ]]; then
                TSD_CAP_NETCLS="mounted"
                TSD_CAP_NETCLS_MP="$mountpoint"
            fi
        done < "${TS_FS_ROOT}/proc/mounts"
    fi
    out=$(uname -r 2>/dev/null) || out=""
    if [[ "$out" =~ ^[A-Za-z0-9._+~-]{1,64}$ ]]; then
        TSD_CAP_KERNEL="$out"
    fi
}

ts_detect_conflicts() {
    local out="" rc=0 line i impls="" units="" unreadable="" count=0 file="" value="" lines="" blitz_conf_st=""
    local re_port="^[[:space:]]*lndPort=[\"']?([0-9]+)[\"']?[[:space:]]*\$"

    # Routes in table 51820 that TunnelSats does not own: install and the route guard refuse to start
    local t51820_iface="${TSD_IFACES// /}"
    if [[ "$TSD_T51820_STATUS" == "ok" ]] && [[ "${#TSD_T51820_FOREIGN[@]}" -gt 0 ]]; then
        ts_detect_conflict table_51820_foreign_routes detected "${#TSD_T51820_FOREIGN[@]} route(s) not via ${t51820_iface}, first: ${TSD_T51820_FOREIGN[0]}"
    elif [[ "$TSD_T51820_STATUS" == "ok" ]]; then
        ts_detect_conflict table_51820_foreign_routes not_detected "${t51820_iface:+judged against ${t51820_iface}}${t51820_iface:-no routes besides the kill-switch blackhole}"
    elif [[ "$TSD_T51820_STATUS" == selection_* ]]; then
        ts_detect_conflict table_51820_foreign_routes unknown "config selection ${TSD_T51820_STATUS#selection_}: the owning interface cannot be decided"
    else
        ts_detect_conflict table_51820_foreign_routes unknown "$TSD_T51820_STATUS"
    fi

    # Tailscale exit node: its default route in table 52 is looked up before the TunnelSats rules
    if ! command -v "$IP_BIN" >/dev/null 2>&1; then
        ts_detect_conflict tailscale_exit_node unknown "unavailable"
    else
        out=$("$IP_BIN" route show table 52 2>&1) || rc=$?
        if [[ "$rc" -ne 0 ]] && [[ "$out" != *"FIB table does not exist"* ]]; then
            ts_detect_conflict tailscale_exit_node unknown "error"
        elif [[ "$rc" -eq 0 ]] && printf '%s\n' "$out" | grep -qE '^(default|0\.0\.0\.0/0)[[:space:]]'; then
            ts_detect_conflict tailscale_exit_node detected "default route in table 52"
        else
            ts_detect_conflict tailscale_exit_node not_detected
        fi
    fi

    # nftables.service enabled: its boot-time ruleset load can flush the TunnelSats tables
    ts_detect_path_status "/etc/systemd/system/sysinit.target.wants/nftables.service"
    case "$TSD_ST" in
        present)
            out="nftables.service is enabled"
            ts_detect_read_status "/etc/nftables.conf"
            if [[ "$TSD_ST" == "readable" ]] && grep -qE '^[[:space:]]*flush[[:space:]]+ruleset' "${TS_FS_ROOT}/etc/nftables.conf" 2>/dev/null; then
                out+="; /etc/nftables.conf flushes the whole ruleset"
            fi
            ts_detect_conflict nftables_service_enabled detected "$out"
            ;;
        absent) ts_detect_conflict nftables_service_enabled not_detected ;;
        *) ts_detect_conflict nftables_service_enabled unknown "$TSD_ST" ;;
    esac

    # More than one Lightning implementation: only one can receive the forwarded port 9735. An
    # implementation counts if its unit file exists in any unit directory or if its unit runs
    # (packaged units live under /usr/lib/systemd/system, generated units have no file at all).
    # A masked unit (file status masked) cannot start, so it only counts while it still runs.
    for i in "${!TSD_LN_UNIT[@]}"; do
        if [[ "${TSD_LN_FILE[$i]}" == "present" ]] || ts_detect_unit_running "${TSD_LN_ACTIVE[$i]}"; then
            units+="${units:+, }${TSD_LN_UNIT[$i]} (${TSD_LN_ACTIVE[$i]})"
            if [[ "$impls" != *" ${TSD_LN_IMPL[$i]} "* ]]; then
                impls+=" ${TSD_LN_IMPL[$i]} "
                count=$((count + 1))
            fi
        elif [[ "${TSD_LN_FILE[$i]}" == "permission_denied" ]]; then
            unreadable+="${unreadable:+, }${TSD_LN_UNIT[$i]}"
        fi
    done
    if [[ "$count" -gt 1 ]]; then
        ts_detect_conflict multiple_ln_implementations detected "$units"
    elif [[ -n "$unreadable" ]]; then
        # A stopped implementation could be installed in a unit directory that cannot be read
        ts_detect_conflict multiple_ln_implementations unknown "unit file location not readable: ${unreadable}"
    else
        ts_detect_conflict multiple_ln_implementations not_detected "$units"
    fi

    # RaspiBlitz: a custom lndPort moves LND away from 9735, where the server forwards to
    for file in /mnt/hdd/app-data/raspiblitz.conf /mnt/hdd/raspiblitz.conf; do
        ts_detect_read_status "$file"
        if [[ "$TSD_ST" != "absent" ]]; then
            break
        fi
    done
    blitz_conf_st="$TSD_ST"
    case "$TSD_ST" in
        absent)
            # raspiblitz.conf lives on the data drive, which may not be mounted (yet)
            if [[ "$TSD_PLATFORM_GUESS" == "raspiblitz" ]]; then
                ts_detect_conflict raspiblitz_custom_lnd_port unknown "raspiblitz.conf not found"
            else
                ts_detect_conflict raspiblitz_custom_lnd_port not_applicable
            fi
            ;;
        readable)
            value=""
            while IFS= read -r line || [[ -n "$line" ]]; do
                if [[ "$line" =~ $re_port ]]; then
                    value="${BASH_REMATCH[1]}"
                fi
            done < "${TS_FS_ROOT}${file}"
            if [[ -n "$value" ]] && [[ "$value" != "9735" ]]; then
                ts_detect_conflict raspiblitz_custom_lnd_port detected "lndPort=${value}"
            else
                ts_detect_conflict raspiblitz_custom_lnd_port not_detected
            fi
            ;;
        *) ts_detect_conflict raspiblitz_custom_lnd_port unknown "$TSD_ST" ;;
    esac

    # RaspiBlitz: custom-installs.sh runs on every provisioning and may re-apply an old setup
    ts_detect_read_status "/mnt/hdd/app-data/custom-installs.sh"
    case "$TSD_ST" in
        absent)
            if [[ "$blitz_conf_st" != "absent" ]]; then
                ts_detect_conflict raspiblitz_custom_installs not_detected
            elif [[ "$TSD_PLATFORM_GUESS" == "raspiblitz" ]]; then
                ts_detect_conflict raspiblitz_custom_installs unknown "raspiblitz.conf not found"
            else
                ts_detect_conflict raspiblitz_custom_installs not_applicable
            fi
            ;;
        readable)
            lines=$(grep -niE 'tunnelsats' "${TS_FS_ROOT}/mnt/hdd/app-data/custom-installs.sh" 2>/dev/null | cut -d: -f1 | head -n 20 | tr '\n' ',') || lines=""
            lines="${lines%,}"
            if [[ -n "$lines" ]]; then
                ts_detect_conflict raspiblitz_custom_installs detected "lines ${lines}"
            else
                ts_detect_conflict raspiblitz_custom_installs not_detected
            fi
            ;;
        *) ts_detect_conflict raspiblitz_custom_installs unknown "$TSD_ST" ;;
    esac
}

ts_detect_render_json() {
    local i privileged="false" platform_j ln_j arts_j cand_j ev_j install_j config_j caps_j conf_j
    local ep_j port_j pub_j comment_j valid_j hooks_j wg_j nft_j sd_j cg2_j netcls_j cand_cfg_j
    local -a items=()
    if [[ "$EUID" -eq 0 ]]; then
        privileged="true"
    fi

    for i in "${!TSD_HINT_PLATFORM[@]}"; do
        ts_j_obj s:platform "${TSD_HINT_PLATFORM[$i]}" s:path "${TSD_HINT_PATH[$i]}" s:status "${TSD_HINT_STATUS[$i]}"
        items+=("$TS_R")
    done
    ts_j_arr "${items[@]}"
    ts_j_obj sn:guess "$TSD_PLATFORM_GUESS" r:evidence "$TS_R"
    platform_j="$TS_R"

    items=()
    for i in "${!TSD_LN_IMPL[@]}"; do
        ts_j_obj s:impl "${TSD_LN_IMPL[$i]}" s:unit "${TSD_LN_UNIT[$i]}" s:file "${TSD_LN_FILE[$i]}" sn:path "${TSD_LN_PATH[$i]}" s:active "${TSD_LN_ACTIVE[$i]}" sn:user "${TSD_LN_USER[$i]}"
        items+=("$TS_R")
    done
    ts_j_arr "${items[@]}"
    ts_j_obj sn:guess "$TSD_LN_GUESS" r:units "$TS_R"
    ln_j="$TS_R"

    items=()
    for i in "${!TSD_ART_ID[@]}"; do
        ts_j_obj s:id "${TSD_ART_ID[$i]}" s:location "${TSD_ART_LOC[$i]}" s:status "${TSD_ART_STATUS[$i]}" sn:detail "${TSD_ART_DETAIL[$i]}" b:contains_secrets "${TSD_ART_SECRET[$i]}"
        items+=("$TS_R")
    done
    ts_j_arr "${items[@]}"
    arts_j="$TS_R"
    items=()
    for i in "${TSD_INSTALL_CANDIDATES[@]}"; do
        ts_j_str "$i"
        items+=("$TS_R")
    done
    ts_j_arr "${items[@]}"
    cand_j="$TS_R"
    items=()
    for i in "${TSD_EVIDENCE[@]}"; do
        ts_j_str "$i"
        items+=("$TS_R")
    done
    ts_j_arr "${items[@]}"
    ev_j="$TS_R"
    ts_j_obj s:kind "$TSD_INSTALL_KIND" sn:managed_state "$TSD_MANAGED_STATE" r:candidates "$cand_j" r:evidence "$ev_j" r:artifacts "$arts_j"
    install_j="$TS_R"

    ts_j_obj sn:host "$TSD_CFG_EP_HOST" i:port "$TSD_CFG_EP_PORT" s:status "$TSD_CFG_EP_STATUS"
    ep_j="$TS_R"
    ts_j_obj i:value "$TSD_CFG_VPN_PORT" s:status "$TSD_CFG_VPN_PORT_STATUS"
    port_j="$TS_R"
    ts_j_obj sn:value "$TSD_CFG_PUB" s:status "$TSD_CFG_PUB_STATUS" s:source "private_key"
    pub_j="$TS_R"
    ts_j_obj sn:value "$TSD_CFG_PUB_COMMENT" s:status "$TSD_CFG_PUB_COMMENT_STATUS" b:matches_derived "$TSD_CFG_PUB_MATCH"
    comment_j="$TS_R"
    ts_j_obj sn:value "$TSD_CFG_VALID_UNTIL" s:status "$TSD_CFG_VALID_UNTIL_STATUS"
    valid_j="$TS_R"
    ts_j_obj s:route_guard "$TSD_CFG_HOOK_GUARD" s:killswitch "$TSD_CFG_HOOK_KILLSWITCH"
    hooks_j="$TS_R"
    items=()
    for i in "${TSD_CFG_CANDIDATES[@]}"; do
        ts_j_str "$i"
        items+=("$TS_R")
    done
    ts_j_arr "${items[@]}"
    cand_cfg_j="$TS_R"
    ts_j_obj sn:path "$TSD_CFG_PATH" s:status "$TSD_CFG_STATUS" s:selection "$TSD_CFG_SELECTION" r:candidates "$cand_cfg_j" \
        sn:interface "$TSD_CFG_IFACE" sn:marker "$TSD_CFG_MARKER" \
        i:marker_count "$TSD_CFG_MARKERS" r:endpoint "$ep_j" r:vpn_port "$port_j" r:public_key "$pub_j" \
        r:public_key_comment "$comment_j" r:valid_until "$valid_j" r:hooks "$hooks_j"
    config_j="$TS_R"

    ts_j_obj s:status "$TSD_CAP_WG" sn:version "$TSD_CAP_WG_VERSION" s:wg_quick "$TSD_CAP_WG_QUICK" s:wg_quick_unit "$TSD_CAP_WG_UNIT"
    wg_j="$TS_R"
    ts_j_obj s:status "$TSD_CAP_NFT" sn:version "$TSD_CAP_NFT_VERSION"
    nft_j="$TS_R"
    ts_j_obj s:status "$TSD_CAP_SYSTEMD" i:version "$TSD_CAP_SYSTEMD_VERSION"
    sd_j="$TS_R"
    ts_j_obj s:status "$TSD_CAP_CG2" sn:mountpoint "$TSD_CAP_CG2_MP"
    cg2_j="$TS_R"
    ts_j_obj s:status "$TSD_CAP_NETCLS" sn:mountpoint "$TSD_CAP_NETCLS_MP"
    netcls_j="$TS_R"
    ts_j_obj r:wireguard_tools "$wg_j" r:nft "$nft_j" r:systemd "$sd_j" r:cgroup_v2 "$cg2_j" r:net_cls_v1 "$netcls_j" sn:kernel_release "$TSD_CAP_KERNEL"
    caps_j="$TS_R"

    items=()
    for i in "${!TSD_CONF_ID[@]}"; do
        ts_j_obj s:id "${TSD_CONF_ID[$i]}" s:status "${TSD_CONF_STATUS[$i]}" sn:detail "${TSD_CONF_DETAIL[$i]}"
        items+=("$TS_R")
    done
    ts_j_arr "${items[@]}"
    conf_j="$TS_R"

    ts_json_document 0 "[]" "\"privileged\":${privileged},\"unreadable_items\":${TSD_UNREADABLE},\"platform\":${platform_j},\"lightning\":${ln_j},\"install\":${install_j},\"config\":${config_j},\"capabilities\":${caps_j},\"conflicts\":${conf_j}"
}

ts_detect_render_human() {
    local i shown
    print_header "Detect (read-only)"
    echo -e "${BOLD}Platform${NC}"
    print_line
    echo "  Guess:            ${TSD_PLATFORM_GUESS:-none}"
    for i in "${!TSD_HINT_PLATFORM[@]}"; do
        if [[ "${TSD_HINT_STATUS[$i]}" != "absent" ]]; then
            echo "  Evidence:         ${TSD_HINT_PATH[$i]} (${TSD_HINT_PLATFORM[$i]}, ${TSD_HINT_STATUS[$i]})"
        fi
    done
    echo ""
    echo -e "${BOLD}Lightning${NC}"
    print_line
    echo "  Guess:            ${TSD_LN_GUESS:-none}"
    for i in "${!TSD_LN_UNIT[@]}"; do
        if [[ "${TSD_LN_FILE[$i]}" != "absent" ]] || ts_detect_unit_running "${TSD_LN_ACTIVE[$i]}"; then
            echo "  ${TSD_LN_UNIT[$i]}: file ${TSD_LN_FILE[$i]}${TSD_LN_PATH[$i]:+ (${TSD_LN_PATH[$i]})}, ${TSD_LN_ACTIVE[$i]}${TSD_LN_USER[$i]:+, user ${TSD_LN_USER[$i]}}"
        fi
    done
    echo ""
    echo -e "${BOLD}Existing TunnelSats install${NC}"
    print_line
    echo "  Kind:             ${TSD_INSTALL_KIND}"
    if [[ "$TSD_INSTALL_KIND" == "unknown" ]]; then
        echo "  Candidates:       ${TSD_INSTALL_CANDIDATES[*]}"
    fi
    if [[ -n "$TSD_MANAGED_STATE" ]]; then
        echo "  Managed state:    ${TSD_MANAGED_STATE}"
    fi
    echo "  Evidence:         ${TSD_EVIDENCE[*]:-none}"
    for i in "${!TSD_ART_ID[@]}"; do
        if [[ "${TSD_ART_STATUS[$i]}" != "absent" ]]; then
            shown="${TSD_ART_LOC[$i]//[[:cntrl:]]/?}"
            printf '  %-18s %-26s %s%s\n' "${TSD_ART_STATUS[$i]}" "${TSD_ART_ID[$i]}" "$shown" "${TSD_ART_DETAIL[$i]:+ (${TSD_ART_DETAIL[$i]})}"
        fi
    done
    echo ""
    echo -e "${BOLD}WireGuard config${NC}"
    print_line
    if [[ "$TSD_CFG_STATUS" == "ok" ]]; then
        echo "  Path:             ${TSD_CFG_PATH} (interface ${TSD_CFG_IFACE}, marker ${TSD_CFG_MARKER:-none})"
        echo "  Endpoint:         ${TSD_CFG_EP_HOST:-?}${TSD_CFG_EP_PORT:+:${TSD_CFG_EP_PORT}} (${TSD_CFG_EP_STATUS})"
        echo "  VPN port:         ${TSD_CFG_VPN_PORT:-?} (${TSD_CFG_VPN_PORT_STATUS})"
        echo "  Public key:       ${TSD_CFG_PUB:-?} (${TSD_CFG_PUB_STATUS}, from PrivateKey)"
        echo "  Key comment:      ${TSD_CFG_PUB_COMMENT:-?} (${TSD_CFG_PUB_COMMENT_STATUS}${TSD_CFG_PUB_MATCH:+, matches derived key: ${TSD_CFG_PUB_MATCH}})"
        echo "  Valid until:      ${TSD_CFG_VALID_UNTIL:-?} (${TSD_CFG_VALID_UNTIL_STATUS}, hint only)"
    else
        echo "  Status:           ${TSD_CFG_STATUS}${TSD_CFG_PATH:+ (${TSD_CFG_PATH})}"
    fi
    echo "  Selection:        ${TSD_CFG_SELECTION}${TSD_CFG_CANDIDATES[0]:+ (candidates: ${TSD_CFG_CANDIDATES[*]})}"
    echo ""
    echo -e "${BOLD}Capabilities${NC}"
    print_line
    echo "  wireguard-tools:  ${TSD_CAP_WG}${TSD_CAP_WG_VERSION:+ ${TSD_CAP_WG_VERSION}} (wg-quick ${TSD_CAP_WG_QUICK}, unit template ${TSD_CAP_WG_UNIT})"
    echo "  nftables:         ${TSD_CAP_NFT}${TSD_CAP_NFT_VERSION:+ ${TSD_CAP_NFT_VERSION}}"
    echo "  systemd:          ${TSD_CAP_SYSTEMD}${TSD_CAP_SYSTEMD_VERSION:+ ${TSD_CAP_SYSTEMD_VERSION}}"
    echo "  cgroup v2:        ${TSD_CAP_CG2}${TSD_CAP_CG2_MP:+ (${TSD_CAP_CG2_MP})}"
    echo "  net_cls (v1):     ${TSD_CAP_NETCLS}${TSD_CAP_NETCLS_MP:+ (${TSD_CAP_NETCLS_MP})}"
    echo "  Kernel:           ${TSD_CAP_KERNEL:-unknown}"
    echo ""
    echo -e "${BOLD}Conflicts${NC}"
    print_line
    for i in "${!TSD_CONF_ID[@]}"; do
        shown="${TSD_CONF_DETAIL[$i]//[[:cntrl:]]/?}"
        echo "  ${TSD_CONF_ID[$i]}: ${TSD_CONF_STATUS[$i]}${shown:+ (${shown})}"
    done
    echo ""
    if [[ "$TSD_UNREADABLE" -gt 0 ]]; then
        print_warning "${TSD_UNREADABLE} item(s) could not be read. Run as root for a complete report."
    fi
}

cmd_detect() {
    local i
    TS_FS_ROOT="${TS_FS_ROOT%/}"
    ts_detect_platform
    ts_detect_lightning
    ts_detect_artifacts
    ts_detect_config
    ts_detect_install_kind
    ts_detect_capabilities
    ts_detect_conflicts
    # Items that could not be read: unreadable locations, plus files that exist but cannot be read
    TSD_UNREADABLE=0
    for i in "${!TSD_ART_STATUS[@]}"; do
        if [[ "${TSD_ART_STATUS[$i]}" == "permission_denied" ]] || [[ "${TSD_ART_STATUS[$i]}" == "error" ]] || \
            [[ "${TSD_ART_DETAIL[$i]}" == "unreadable" ]]; then
            TSD_UNREADABLE=$((TSD_UNREADABLE + 1))
        elif [[ "$TSD_CFG_STATUS" == "permission_denied" ]] && [[ "${TSD_ART_ID[$i]}" == "wg_config" ]] && \
            [[ "${TSD_ART_LOC[$i]}" == "$TSD_CFG_PATH" ]]; then
            TSD_UNREADABLE=$((TSD_UNREADABLE + 1))
        fi
    done
    if [[ "$TS_JSON" -eq 1 ]]; then
        ts_detect_render_json
    else
        ts_detect_render_human
    fi
    exit 0
}

# ---------------------------------------------------------------------------
# ARGUMENT PARSING
# Options are global: they are accepted before or after the command word.
# ---------------------------------------------------------------------------

# Prints the canonical name of command word $1 (aliases included), nothing if it is unknown.
# managed-arm, managed-disarm, managed-verify and managed-mynode-lnd-pre are internal verbs of the managed units.
ts_canonical_command() {
    case "$1" in
        install) echo "install" ;;
        adopt) echo "adopt" ;;
        pre-check|precheck|check) echo "pre-check" ;;
        uninstall|remove) echo "uninstall" ;;
        status) echo "status" ;;
        restart) echo "restart" ;;
        verify) echo "verify" ;;
        detect) echo "detect" ;;
        version) echo "version" ;;
        help) echo "help" ;;
        managed-arm|managed-disarm|managed-verify|managed-mynode-lnd-pre) echo "$1" ;;
    esac
    return 0
}

# Succeeds if option $2 applies to command $1.
ts_option_supported() {
    case "$2" in
        --non-interactive|--yes|--json) return 0 ;;
        --config) [[ "$1" == "install" || "$1" == "adopt" || "$1" == "status" || "$1" == "restart" ]] ;;
        --platform|--impl) [[ "$1" == "install" || "$1" == "adopt" || "$1" == "uninstall" || "$1" == "status" || "$1" == "restart" ]] ;;
        --remove-packages|--keep-packages|--keep-config|--legacy-artifacts) [[ "$1" == "uninstall" ]] ;;
        --managed) [[ "$1" == "install" || "$1" == "adopt" || "$1" == "uninstall" ]] ;;
        --uid-backstop|--network) [[ "$1" == "install" || "$1" == "adopt" ]] ;;
        --no-probe) [[ "$1" == "verify" ]] ;;
        --fallback-uid) [[ "$1" == "managed-arm" ]] ;;
        *) return 1 ;;
    esac
}

# Keeps the first usage problem found while parsing (reported by parse_args).
ts_usage_note() {
    if [[ -z "$TS_USAGE_ERROR" ]]; then
        TS_USAGE_ERROR="$1"
    fi
    return 0
}

# Parses the command line into the TS_* variables without printing or exiting.
ts_parse_cli() {
    local word="" opt value
    TS_ARGV=("$@")
    TS_COMMAND=""
    TS_JSON=0
    TS_NONINTERACTIVE=0
    TS_OPT_YES=0
    TS_OPT_PLATFORM=""
    TS_OPT_IMPL=""
    TS_OPT_PACKAGES=""
    TS_OPT_KEEP_CONFIG=0
    TS_OPT_LEGACY_ARTIFACTS=0
    TS_OPT_MANAGED=0
    TS_OPT_PROFILE=""
    TS_OPT_UID_BACKSTOP=0
    TS_OPT_NO_PROBE=0
    TS_OPT_FALLBACK_UID=""
    TS_OPT_NETWORK=""
    TS_WANT_HELP=0
    TS_USAGE_ERROR=""
    TS_OPTS_GIVEN=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --non-interactive)
                TS_NONINTERACTIVE=1
                TS_OPTS_GIVEN+=("$1")
                ;;
            --json)
                TS_JSON=1
                TS_OPTS_GIVEN+=("$1")
                ;;
            --yes)
                TS_OPT_YES=1
                TS_OPTS_GIVEN+=("$1")
                ;;
            --keep-config)
                TS_OPT_KEEP_CONFIG=1
                TS_OPTS_GIVEN+=("$1")
                ;;
            --legacy-artifacts)
                TS_OPT_LEGACY_ARTIFACTS=1
                TS_OPTS_GIVEN+=("$1")
                ;;
            --managed)
                # The profile value is optional (uninstall --managed); only a profile word is taken
                if [[ "$TS_OPT_MANAGED" -eq 1 ]]; then
                    ts_usage_note "--managed given more than once"
                fi
                TS_OPT_MANAGED=1
                TS_OPTS_GIVEN+=("$1")
                if [[ $# -ge 2 ]] && ts_in_list "$2" "$TS_M_PROFILE_WORDS"; then
                    TS_OPT_PROFILE="$2"
                    shift 2
                    continue
                fi
                ;;
            --uid-backstop)
                TS_OPT_UID_BACKSTOP=1
                TS_OPTS_GIVEN+=("$1")
                ;;
            --no-probe)
                TS_OPT_NO_PROBE=1
                TS_OPTS_GIVEN+=("$1")
                ;;
            --fallback-uid)
                if [[ $# -lt 2 ]] || [[ ! "$2" =~ ^[1-9][0-9]*$ ]]; then
                    ts_usage_note "--fallback-uid requires a positive uid"
                    TS_OPTS_GIVEN+=("$1")
                    shift
                    continue
                fi
                TS_OPT_FALLBACK_UID="$2"
                TS_OPTS_GIVEN+=("$1")
                shift 2
                continue
                ;;
            --remove-packages|--keep-packages)
                value="${1#--}"
                value="${value%-packages}"
                if [[ -n "$TS_OPT_PACKAGES" ]] && [[ "$TS_OPT_PACKAGES" != "$value" ]]; then
                    ts_usage_note "--remove-packages and --keep-packages cannot be combined"
                fi
                TS_OPT_PACKAGES="$value"
                TS_OPTS_GIVEN+=("$1")
                ;;
            --config|--platform|--impl|--network)
                opt="$1"
                if [[ $# -lt 2 ]] || [[ -z "$2" ]] || [[ "$2" == -* ]]; then
                    ts_usage_note "${opt} requires a value"
                    TS_OPTS_GIVEN+=("$opt")
                    shift
                    continue
                fi
                value="$2"
                if [[ " ${TS_OPTS_GIVEN[*]} " == *" ${opt} "* ]]; then
                    ts_usage_note "${opt} given more than once"
                fi
                case "$opt" in
                    --config) CONFIG_FILE="$value" ;;
                    --platform)
                        if ! ts_in_list "$value" "$TS_PLATFORMS"; then
                            ts_usage_note "Invalid --platform '${value}' (expected: ${TS_PLATFORMS// /, })"
                        fi
                        TS_OPT_PLATFORM="$value"
                        ;;
                    --impl)
                        if ! ts_in_list "$value" "$TS_IMPLS"; then
                            ts_usage_note "Invalid --impl '${value}' (expected: ${TS_IMPLS// /, })"
                        fi
                        TS_OPT_IMPL="$value"
                        ;;
                    --network)
                        if ! ts_in_list "$value" "$TS_NETWORKS"; then
                            ts_usage_note "Invalid --network '${value}' (expected: ${TS_NETWORKS// /, })"
                        fi
                        TS_OPT_NETWORK="$value"
                        ;;
                esac
                TS_OPTS_GIVEN+=("$opt")
                shift 2
                continue
                ;;
            -h|--help)
                TS_WANT_HELP=1
                ;;
            -*)
                ts_usage_note "Unknown option: $1"
                ;;
            *)
                if [[ -z "$word" ]]; then
                    word="$1"
                else
                    ts_usage_note "Unexpected argument: $1"
                fi
                ;;
        esac
        shift
    done
    if [[ "$TS_WANT_HELP" -eq 1 ]]; then
        word="help"
    fi
    if [[ -n "$word" ]]; then
        TS_COMMAND=$(ts_canonical_command "$word")
        if [[ -z "$TS_COMMAND" ]]; then
            ts_usage_note "Unknown command: ${word}"
            TS_COMMAND="$word"
        fi
    fi
    # A JSON consumer cannot answer prompts
    if [[ "$TS_JSON" -eq 1 ]]; then
        TS_NONINTERACTIVE=1
    fi
    return 0
}

# Rejects options the command does not use, and --json where it is not supported yet.
ts_validate_cli() {
    local opt
    for opt in "${TS_OPTS_GIVEN[@]}"; do
        if ! ts_option_supported "$TS_COMMAND" "$opt"; then
            ts_usage_error "${opt} is not supported by '${TS_COMMAND}'"
        fi
    done
    if [[ "$TS_OPT_MANAGED" -eq 1 ]]; then
        for opt in "${TS_OPTS_GIVEN[@]}"; do
            case "$TS_COMMAND:$opt" in
                uninstall:--platform|uninstall:--impl|uninstall:--remove-packages|uninstall:--keep-packages)
                    ts_usage_error "${opt} is not used by 'uninstall --managed' (the inventory records what to remove; packages stay)"
                    ;;
            esac
        done
    elif [[ "$TS_OPT_UID_BACKSTOP" -eq 1 ]]; then
        ts_usage_error "--uid-backstop requires --managed"
    fi
    if [[ "$TS_COMMAND" == "adopt" ]] && [[ "$TS_OPT_MANAGED" -ne 1 ]]; then
        ts_usage_error "adopt requires --managed <baremetal|raspiblitz|mynode>"
    fi
    # RaspiBlitz runs one Lightning unit per implementation and chain, so the raspiblitz profile
    # names it (--impl, --network) instead of picking one
    if [[ "$TS_COMMAND" == "install" || "$TS_COMMAND" == "adopt" ]] && [[ "$TS_OPT_MANAGED" -eq 1 ]] && [[ "$TS_OPT_PROFILE" == "raspiblitz" ]]; then
        if [[ -z "$TS_OPT_IMPL" ]]; then
            ts_usage_error "${TS_COMMAND} --managed raspiblitz requires --impl lnd or --impl cln"
        fi
        if [[ "$TS_OPT_IMPL" != "lnd" ]] && [[ "$TS_OPT_IMPL" != "cln" ]]; then
            ts_usage_error "${TS_COMMAND} --managed raspiblitz supports --impl lnd or --impl cln, not ${TS_OPT_IMPL}"
        fi
    elif [[ -n "$TS_OPT_NETWORK" ]]; then
        ts_usage_error "--network is used by '${TS_COMMAND} --managed raspiblitz' only"
    fi
    if [[ "$TS_COMMAND" == "install" || "$TS_COMMAND" == "adopt" ]] && [[ "$TS_OPT_MANAGED" -eq 1 ]] && [[ "$TS_OPT_PROFILE" == "mynode" ]]; then
        if [[ "$TS_OPT_IMPL" == "cln" ]]; then
            ts_usage_error "${TS_COMMAND} --managed mynode supports --impl lnd or --impl lit, not cln (myNode does not ship Core Lightning)"
        fi
    fi
    if [[ "$TS_JSON" -eq 1 ]]; then
        case "$TS_COMMAND" in
            version|detect|verify) ;;
            install|uninstall|adopt)
                if [[ "$TS_OPT_MANAGED" -ne 1 ]]; then
                    ts_fail 2 E_JSON_UNSUPPORTED usage "'${TS_COMMAND}' does not support --json yet (supported: version, detect, verify, install --managed, adopt --managed, uninstall --managed)"
                fi
                ;;
            *)
                ts_fail 2 E_JSON_UNSUPPORTED usage "'${TS_COMMAND}' does not support --json yet (supported: version, detect, verify, install --managed, adopt --managed, uninstall --managed)"
                ;;
        esac
    fi
    return 0
}

parse_args() {
    # Internal verb of verify's probes: runs inside a transient unit of the slice, takes positional
    # arguments and prints plain lines
    if [[ "${1:-}" == "managed-probe" ]]; then
        shift
        ts_m_cmd_probe "$@"
    fi
    ts_parse_cli "$@"
    ts_init_colors
    if [[ "$TS_JSON" -eq 1 ]]; then
        # Anything printed to stdout from here on is a log and goes to stderr; the JSON document
        # goes to the original stdout, kept on file descriptor 3
        exec 3>&1 1>&2
        TS_OUT_FD=3
        trap ts_json_exit_guard EXIT
    fi

    if [[ -n "$TS_USAGE_ERROR" ]]; then
        ts_usage_error "$TS_USAGE_ERROR"
    fi
    if [[ -z "$TS_COMMAND" ]]; then
        if [[ ${#TS_ARGV[@]} -eq 0 ]]; then
            cmd_help
            exit 0
        fi
        ts_usage_error "Missing command"
    fi
    ts_validate_cli

    # Internal verbs of the managed units (they log to the journal through stderr)
    case "$TS_COMMAND" in
        managed-arm|managed-disarm|managed-verify|managed-mynode-lnd-pre)
            if [[ "$EUID" -ne 0 ]]; then
                echo "TunnelSats: ${TS_COMMAND} must run as root" >&2
                exit 1
            fi
            case "$TS_COMMAND" in
                managed-arm) ts_m_cmd_arm ;;
                managed-disarm) ts_m_cmd_disarm ;;
                managed-verify) ts_m_cmd_verifier ;;
                managed-mynode-lnd-pre) ts_m_cmd_mynode_lnd_pre ;;
            esac
            ;;
    esac

    # A managed install is changed only by the managed commands
    if [[ "$TS_OPT_MANAGED" -ne 1 ]] && ts_m_inventory_present; then
        case "$TS_COMMAND" in
            install)
                ts_fail 7 E_MANAGED_PRESENT refused "A managed install is present; run 'tunnelsats.sh uninstall --managed' first"
                ;;
            uninstall)
                ts_fail 7 E_MANAGED_PRESENT refused "A managed install is present; remove it with 'tunnelsats.sh uninstall --managed'"
                ;;
        esac
    fi

    # Verify configuration exists before proceeding (Early fail). A managed install checks the file
    # given with --config itself and reports a missing one in the JSON document (E_CONFIG_INVALID,
    # exit 8), so unattended callers such as provisioning get a clear error
    if [[ "$TS_COMMAND" == "install" ]] && { [[ "$TS_OPT_MANAGED" -ne 1 ]] || [[ -z "$CONFIG_FILE" ]]; }; then
        config_path=$(detect_config_file "$CONFIG_FILE") || exit $?
        CONFIG_FILE="$config_path"
    fi
    
    # Dispatch command
    case "$TS_COMMAND" in
        install)
            if [[ "$TS_OPT_MANAGED" -eq 1 ]]; then
                cmd_install_managed
            fi
            check_root "${TS_ARGV[@]}"
            cmd_install
            ;;
        adopt)
            cmd_adopt_managed
            ;;
        pre-check)
            check_root "${TS_ARGV[@]}"
            cmd_pre_check
            ;;
        uninstall)
            if [[ "$TS_OPT_MANAGED" -eq 1 ]]; then
                cmd_uninstall_managed
            fi
            check_root "${TS_ARGV[@]}"
            cmd_uninstall
            ;;
        verify)
            cmd_verify
            ;;
        status)
            check_root "${TS_ARGV[@]}"
            # A managed install is checked through its kernel state, never from configuration
            if ts_m_inventory_present; then
                cmd_verify
            fi
            if [[ -n "$CONFIG_FILE" ]] && [[ ! -f "$CONFIG_FILE" ]]; then
                print_error "Config file not found: $CONFIG_FILE"
                exit 1
            fi
            # Explicit --platform / --impl take precedence over auto-detection
            PLATFORM="$TS_OPT_PLATFORM"
            LN_IMPL="$TS_OPT_IMPL"
            cmd_status
            ;;
        restart)
            check_root "${TS_ARGV[@]}"
            # Managed: only the tunnel restarts; the kill switch units and rules stay as they are
            if ts_m_inventory_present; then
                ts_m_cmd_restart
            fi
            if [[ -n "$CONFIG_FILE" ]]; then
                # wg-quick@<name> always reads <WireGuard dir>/<name>.conf: only an installed config fits
                if [[ ! -f "$CONFIG_FILE" ]]; then
                    print_error "Config file not found: $CONFIG_FILE"
                    exit 1
                fi
                if [[ "$(cd "$(dirname "$CONFIG_FILE")" && pwd -P)" != "$(cd "${WG_DIR:-/etc/wireguard}" 2>/dev/null && pwd -P)" ]]; then
                    ts_usage_error "restart --config must name an installed config in ${WG_DIR:-/etc/wireguard}"
                fi
                # Checked before anything is stopped: a backup such as tunnelsatsv2.conf.bak.X is not
                # a config wg-quick can start, so restarting with it would leave Lightning stopped
                if ! ts_valid_installed_config_name "${CONFIG_FILE##*/}"; then
                    ts_usage_error "restart --config must name an installed TunnelSats config (tunnelsatsv2.conf or tunnelsats-<name>.conf)"
                fi
            fi
            PLATFORM="$TS_OPT_PLATFORM"
            LN_IMPL="$TS_OPT_IMPL"
            cmd_restart
            ;;
        detect)
            cmd_detect
            ;;
        version)
            cmd_version
            ;;
        help)
            cmd_help
            ;;
    esac
}

# ---------------------------------------------------------------------------
# MANAGED DATAPLANE (preview): install --managed baremetal|raspiblitz, verify, uninstall --managed
#
# The tunneled Lightning unit runs in a persistent systemd slice (tunnelsats.slice, set by a
# drop-in, so the unit file itself is never edited). A persistent nftables table marks the
# connections the slice opens (socket cgroupv2) and the connections that arrive through the
# tunnel (conntrack mark). Marked packets are routed into table 51820, which always holds a
# blackhole default route and holds "default dev tunnelsatsv2" only while wg-quick has the tunnel
# up; marked packets that would leave through another interface to a non-local, non-LAN address
# are dropped. None of this depends on wg-quick: tunnelsats-killswitch.service loads it before
# Lightning starts, and tunnelsats-verifier.timer checks it every 30 seconds and re-arms it on drift.
#
# Kernel constraints that shape the ruleset (probed on real kernels):
#   - "socket cgroupv2" is accepted only in the prerouting, input and output hooks, so slice
#     matching happens in output;
#   - oifname in later output chains still names the device chosen before the mark-based reroute,
#     so decisions about the outgoing interface happen in postrouting, keyed on the packet or
#     conntrack mark set in output;
#   - "nft -c" does not prove that the kernel accepts a ruleset. The capability probe and the
#     expected-ruleset listing therefore load the real ruleset into a throwaway network namespace,
#     which leaves the host's datapath untouched.
#
# Pure renderers (ts_m_render_*) only print text. Paths are prefixed with TS_FS_ROOT and commands
# run through the injectable *_BIN variables, so unit tests run these production functions against
# fixture trees and stub commands.
# ---------------------------------------------------------------------------

TS_M_IFACE="tunnelsatsv2"
TS_M_SLICE="tunnelsats.slice"
TS_M_NFT_TABLE="tunnelsats"
TS_M_MARK="0x01000000"
TS_M_MASK="0xff000000"
TS_M_KEEP="0x00ffffff"
TS_M_WG_FWMARK="0x02000000"
TS_M_RT_TABLE="51820"
TS_M_PRIO_MAIN="21820"
TS_M_PRIO_MARK="21821"
TS_M_PRIO_UID="21822"
TS_M_LN_PORT="9735"
TS_M_BLACKHOLE_METRIC="4294967295"
TS_M_LAN4="10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16"
TS_M_LAN6="::1/128, fc00::/7, fe80::/10"
# Subnet argument of the shared emergency helpers (ts_arm_failclosed_rules); bare metal sends no
# traffic from it, the uid rule is what covers the Lightning daemon
TS_M_EMERGENCY_SUBNET="10.9.9.0/25"
# Profiles install --managed accepts, and the words --managed recognises as a profile value
TS_M_PROFILES="baremetal raspiblitz mynode"
TS_M_PROFILE_WORDS="baremetal raspiblitz umbrel mynode"
TS_M_BIN="/usr/local/sbin/tunnelsats"
TS_M_UNIT_DIR="/etc/systemd/system"
TS_M_SLICE_UNIT="tunnelsats.slice"
TS_M_KILLSWITCH_UNIT="tunnelsats-killswitch.service"
TS_M_VERIFIER_UNIT="tunnelsats-verifier.service"
TS_M_TIMER_UNIT="tunnelsats-verifier.timer"
TS_M_WG_UNIT="wg-quick@tunnelsatsv2.service"
TS_M_DROPIN_NAME="tunnelsats-managed.conf"
TS_M_STATE_DIR="/etc/tunnelsats"
TS_M_INVENTORY="/etc/tunnelsats/managed.json"
TS_M_RUN_DIR="/run/tunnelsats"
TS_M_ATTEST="/run/tunnelsats/attest.json"
TS_M_LOCK="/run/tunnelsats/lock"
TS_M_LIFECYCLE_LOCK="/run/tunnelsats/lifecycle.lock"
TS_M_RULESET_FILE="/run/tunnelsats/ruleset.nft"
TS_M_VERIFIER_STATE="/run/tunnelsats/verifier.state"
# Lightning units the verifier stopped because no protection held (ts_m_quarantine); started again
# once one holds (ts_m_resume_stopped)
TS_M_STOPPED="/run/tunnelsats/stopped-units"
# Seconds ts_m_quarantine waits for a stopped Lightning unit to become inactive while it holds the
# kill switch lock (the stop itself does not block); a later check confirms a longer shutdown
TS_M_STOP_WAIT="${TS_M_STOP_WAIT:-15}"
# Seconds uninstall --managed waits for LND to answer lncli getinfo before it takes the former VPN
# address out of LND's node announcement (0 to 999)
TS_M_ANNOUNCE_WAIT="${TS_M_ANNOUNCE_WAIT:-120}"
# Starts ts_m_resume_stopped queues for a recorded unit before it gives up and logs the command to
# start it by hand (one per check, so about five minutes)
TS_M_RESUME_MAX="${TS_M_RESUME_MAX:-10}"
TS_M_EMERGENCY6_STATE="/run/tunnelsats/emergency6.rules"
# Local networks the emergency block keeps for the node uid (priority 21817, before its
# blackholes), and the record of the exemption rules TunnelSats added
TS_M_EMERGENCY_LAN_PRIO="21817"
TS_M_EMERGENCY_LAN4="10.0.0.0/8 100.64.0.0/10 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16"
TS_M_EMERGENCY_LAN6="fc00::/7 fe80::/10"
TS_M_EMERGENCY_LAN_STATE="/run/tunnelsats/emergency-lan.rules"
TS_M_WG_DIR="/etc/wireguard"
TS_M_WG_CONF="/etc/wireguard/tunnelsatsv2.conf"
TS_M_CGROUP_ROOT="/sys/fs/cgroup"
TS_M_HANDSHAKE_MAX_AGE=180
# Lightning units managed mode can tunnel: "<impl>:<unit>". The baremetal profile picks one of
# TS_M_LN_UNITS; the raspiblitz profile names one of TS_M_RASPIBLITZ_LN_UNITS with --impl and
# --network (ts_m_raspiblitz_unit); the mynode profile picks one of TS_M_MYNODE_LN_UNITS.
# TS_M_ALL_LN_UNITS lists each unit of all profiles once: any of them can carry the managed
# drop-in (path checks, removal, the damaged-record path, detect).
TS_M_LN_UNITS="lnd:lnd.service cln:lightningd.service lit:litd.service lit:lit.service"
TS_M_MYNODE_LN_UNITS="lnd:lnd.service lit:litd.service lit:lit.service"
TS_M_RASPIBLITZ_LN_UNITS="lnd:lnd.service lnd:tlnd.service lnd:slnd.service cln:lightningd.service cln:tlightningd.service cln:slightningd.service"
TS_M_ALL_LN_UNITS="${TS_M_LN_UNITS} lnd:tlnd.service lnd:slnd.service cln:tlightningd.service cln:slightningd.service"

# Inventory and install state (ts_m_inventory_read, install --managed). The inventory is written
# ahead of every change: state "installing" with the planned files first, each file's sha256 right
# after it is written, then state "installed" before any unit starts. Removal sets "removing" before
# its first change and keeps the inventory, with the items that remained, until everything is gone.
TS_M_INV_STATE=""
TS_M_INV_PROFILE=""
TS_M_INV_IMPL=""
TS_M_INV_UNIT=""
TS_M_INV_USER=""
TS_M_INV_UID=""
TS_M_INV_BACKSTOP=0
TS_M_INV_REMAINING=()
TS_M_FILES=()
TS_M_FILE_SHA=()
TS_M_CREATED_DIRS=()
TS_M_ENABLED_UNITS=()
TS_M_ERROR=""
TS_M_DRIFT=()
# Lightning units of other implementations found next to the tunneled one (not tunneled)
TS_M_OTHER_UNITS=()
# Command line of the Lightning unit's ExecStart (ts_m_execstart_args), and its argv[] text
TS_M_EXEC_ARGV=()
TS_M_EXEC_RAW=""
TS_M_EXEC_REASON=""
# RaspiBlitz's TunnelSats start guard on the Lightning unit (ts_m_raspiblitz_guard_ctx,
# ts_m_raspiblitz_guard_argv): the script its guard line runs; the variable that carries the flags of
# a start, its word on the command line and the env file the guard writes it to; and why a unit does
# not carry the guard in the expected form
TS_M_RB_SCRIPT="/home/admin/config.scripts/internet.tunnelsats.sh"
TS_M_RB_IMPL=""
TS_M_RB_CHAIN=""
TS_M_RB_VAR=""
TS_M_RB_WORD=""
TS_M_RB_ENVFILE=""
TS_M_RB_WHY=""

# Succeeds when the process runs as root. Managed commands call it first (tests replace it).
ts_m_require_root() {
    if [[ "$EUID" -ne 0 ]]; then
        ts_fail 2 E_NOT_ROOT usage "'${TS_COMMAND}' must be run as root (sudo)"
    fi
    return 0
}

# Owner uid expected for managed state files (tests replace it with their own uid).
ts_m_expected_owner() {
    echo 0
}

# Writes stdin to file $1 atomically (temporary file in the same directory, then rename) with
# mode $2. Returns 1 on failure and leaves no temporary file behind.
ts_m_write_file() {
    local dest="$1" mode="$2" tmp
    tmp=$(mktemp "${dest%/*}/.tunnelsats.XXXXXX") || return 1
    if ! cat > "$tmp" || ! chmod "$mode" "$tmp" || ! mv -f "$tmp" "$dest"; then
        rm -f "$tmp"
        return 1
    fi
    return 0
}

# Prints the sha256 of file $1.
ts_m_sha256() {
    local out
    out=$(sha256sum -b "$1" 2>/dev/null) || return 1
    echo "${out%% *}"
}

# Creates directory $1 (below TS_FS_ROOT) with mode $2 unless it exists. It is recorded in
# TS_M_CREATED_DIRS, and in the inventory once that exists, before it is created, so removal
# deletes it again (only when it is empty by then).
ts_m_ensure_dir() {
    local rel="$1" mode="$2" d listed=0
    if [[ -d "${TS_FS_ROOT}${rel}" ]]; then
        return 0
    fi
    for d in "${TS_M_CREATED_DIRS[@]}"; do
        if [[ "$d" == "$rel" ]]; then
            listed=1
        fi
    done
    if [[ "$listed" -eq 0 ]]; then
        TS_M_CREATED_DIRS+=("$rel")
        if [[ -f "${TS_FS_ROOT}${TS_M_INVENTORY}" ]] && ! ts_m_inventory_write; then
            return 1
        fi
    fi
    mkdir -m "$mode" "${TS_FS_ROOT}${rel}"
}

# Records sha256 $2 (empty if unknown) for file $1 at its planned entry in TS_M_FILES and
# TS_M_FILE_SHA, or appends the file if it was not planned.
ts_m_record_file() {
    local rel="$1" sha="$2" i
    for i in "${!TS_M_FILES[@]}"; do
        if [[ "${TS_M_FILES[$i]}" == "$rel" ]]; then
            TS_M_FILE_SHA[$i]="$sha"
            return 0
        fi
    done
    TS_M_FILES+=("$rel")
    TS_M_FILE_SHA+=("$sha")
}

# Writes stdin to file $1 (below TS_FS_ROOT) with mode $2, records its sha256 and rewrites the
# inventory. The file is recorded right after the write, so a failing checksum still leaves it in
# the record and removal deletes it. Must run in the installing shell (never as the right-hand
# side of a pipeline, where the record would be lost).
ts_m_install_file() {
    local rel="$1" mode="$2" sha=""
    ts_m_write_file "${TS_FS_ROOT}${rel}" "$mode" || return 1
    sha=$(ts_m_sha256 "${TS_FS_ROOT}${rel}") || sha=""
    ts_m_record_file "$rel" "$sha"
    if [[ -z "$sha" ]]; then
        return 1
    fi
    ts_m_inventory_write
}

# Creates /run/tunnelsats (root 0755) for the attestation, the lock and the verifier state.
ts_m_ensure_run_dir() {
    local d="${TS_FS_ROOT}${TS_M_RUN_DIR}"
    if [[ ! -d "$d" ]]; then
        mkdir -p "$d" || return 1
    fi
    chmod 0755 "$d"
}

# Serializes changes to the kill switch (arm, disarm, verifier re-arm, removal) on file descriptor
# 9 until ts_m_unlock or the end of the process. Never held while starting units that take it.
ts_m_lock() {
    ts_m_ensure_run_dir || return 1
    exec 9>"${TS_FS_ROOT}${TS_M_LOCK}" || return 1
    flock -w 60 9
}

ts_m_unlock() {
    exec 9>&-
}

# Serializes install --managed and uninstall --managed on file descriptor 8 until the process
# ends. It never waits: while another of these commands holds it, the command refuses with E_BUSY
# (exit 7) before it reads or changes anything. The units never take this lock, so the kill switch
# lock (ts_m_lock) stays available to everything they run. Uninstall removes the lock file only as
# its very last step.
ts_m_lifecycle_lock() {
    if ! ts_m_ensure_run_dir || ! exec 8>"${TS_FS_ROOT}${TS_M_LIFECYCLE_LOCK}"; then
        ts_fail 1 E_INTERNAL operational "Cannot open ${TS_M_LIFECYCLE_LOCK}"
    fi
    if ! flock -n 8; then
        ts_fail 7 E_BUSY refused "Another managed install or uninstall is running; try again when it has finished"
    fi
    return 0
}

# Removes the lifecycle lock file and /run/tunnelsats (only if nothing else is in it) when a
# lifecycle command stops while no managed install exists, so a refused command leaves nothing.
ts_m_lifecycle_cleanup() {
    if ts_m_inventory_present; then
        return 0
    fi
    rm -f "${TS_FS_ROOT}${TS_M_LIFECYCLE_LOCK}"
    rmdir "${TS_FS_ROOT}${TS_M_RUN_DIR}" 2>/dev/null || true
}

# Prints the current boot id; fails if it cannot be read.
ts_m_boot_id() {
    local id=""
    id=$(cat "${TS_FS_ROOT}/proc/sys/kernel/random/boot_id" 2>/dev/null) || return 1
    if [[ ! "$id" =~ ^[0-9a-f-]{36}$ ]]; then
        return 1
    fi
    echo "$id"
}

# Prints the cgroup id (inode number) of the slice; fails while the slice has no cgroup.
ts_m_slice_cgroup_id() {
    local p="${TS_FS_ROOT}${TS_M_CGROUP_ROOT}/${TS_M_SLICE}" id=""
    if [[ ! -d "$p" ]]; then
        return 1
    fi
    id=$(stat -c %i "$p" 2>/dev/null) || return 1
    if [[ ! "$id" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    echo "$id"
}

# Succeeds if the kernel has an IPv6 stack (no ipv6.disable=1); IPv6 rules and routes are managed then.
ts_m_ipv6_available() {
    [[ -e "${TS_FS_ROOT}/proc/net/if_inet6" ]]
}

ts_m_inventory_present() {
    [[ -e "${TS_FS_ROOT}${TS_M_INVENTORY}" ]]
}

# ---------------------------------------------------------------------------
# Managed mode: renderers (print only)
# ---------------------------------------------------------------------------

# Prints the kill switch ruleset as one nft transaction ("add table", "delete table", then the
# full definition): if the kernel refuses any rule, nothing is committed and the previous table
# stays armed. $1 = cgroup v2 path of the slice (default tunnelsats.slice), $2 = its level below
# the cgroup root (default 1); the capability probe and unit tests pass another existing cgroup.
#   pre   connections that arrive through the tunnel get the TunnelSats conntrack mark, and their
#         packets carry it as packet mark, so reverse-path filtering with src_valid_mark=1 on the
#         tunnel accepts the replies of tunneled connections (strict rp_filter)
#   out   new connections of the slice to non-local, non-LAN IPv4 addresses get the conntrack mark;
#         their packets and every packet of a marked connection get the packet mark, and the mark
#         change reroutes them into table 51820. The tunnel's own UDP (FwMark) is left alone.
#   out6  the slice uses IPv6 only for loopback, link-local and ULA (the tunnel carries IPv4)
#   kill  marked packets that would leave through another interface to a non-local, non-LAN
#         address are dropped (oifname is final only in postrouting)
#   nat   marked packets that leave through the tunnel get the tunnel address as source
#   in    the tunnel accepts replies and the Lightning port only
ts_m_render_ruleset() {
    local slice="${1:-$TS_M_SLICE}" level="${2:-1}"
    local iface="$TS_M_IFACE" mark="$TS_M_MARK" mask="$TS_M_MASK" keep="$TS_M_KEEP"
    local sock setmark_ct setmark_pkt
    if [[ ! "$slice" =~ ^[A-Za-z0-9_.@:-]+(/[A-Za-z0-9_.@:-]+)*$ ]] || [[ ! "$level" =~ ^[1-9]$ ]]; then
        return 1
    fi
    sock="socket cgroupv2 level ${level} \"${slice}\""
    setmark_ct="ct mark set ct mark and ${keep} or ${mark}"
    setmark_pkt="meta mark set meta mark and ${keep} or ${mark}"
    cat <<EOF
add table inet ${TS_M_NFT_TABLE}
delete table inet ${TS_M_NFT_TABLE}
table inet ${TS_M_NFT_TABLE} {
	set lan4 {
		type ipv4_addr
		flags interval
		elements = { ${TS_M_LAN4} }
	}
	set lan6 {
		type ipv6_addr
		flags interval
		elements = { ${TS_M_LAN6} }
	}
	chain pre {
		type filter hook prerouting priority mangle; policy accept;
		iifname "${iface}" ct state new ${setmark_ct}
		iifname "${iface}" ct mark and ${mask} == ${mark} ${setmark_pkt}
	}
	chain out {
		type route hook output priority mangle; policy accept;
		meta mark and ${mask} == ${TS_M_WG_FWMARK} return
		ct state new ${sock} fib daddr type != local ip daddr != @lan4 ${setmark_ct}
		${sock} fib daddr type != local ip daddr != @lan4 ${setmark_pkt}
		ct mark and ${mask} == ${mark} ${setmark_pkt}
	}
	chain out6 {
		type filter hook output priority filter; policy accept;
		${sock} ip6 daddr != @lan6 counter drop
	}
	chain kill {
		type filter hook postrouting priority filter; policy accept;
		meta mark and ${mask} == ${mark} oifname != "${iface}" fib daddr type != local ip daddr != @lan4 counter drop
		ct mark and ${mask} == ${mark} oifname != "${iface}" fib daddr type != local ip daddr != @lan4 counter drop
	}
	chain nat {
		type nat hook postrouting priority srcnat; policy accept;
		oifname "${iface}" meta mark and ${mask} == ${mark} masquerade
	}
	chain in {
		type filter hook input priority filter - 1; policy accept;
		iifname "${iface}" ct state established,related accept
		iifname "${iface}" tcp dport ${TS_M_LN_PORT} accept
		iifname "${iface}" counter drop
	}
}
EOF
}

ts_m_render_unit_header() {
    echo "# Generated by tunnelsats.sh (managed mode). Removed by: tunnelsats.sh uninstall --managed"
}

ts_m_render_slice_unit() {
    ts_m_render_unit_header
    cat <<'EOF'
[Unit]
Description=TunnelSats slice for the tunneled Lightning daemon

[Slice]
EOF
}

# $1 = Lightning unit, which starts after the kill switch.
# The kill switch unit; $1 = the Lightning unit, $2 = its uid. ExecStart carries the uid
# (--fallback-uid), so managed-arm can still arm the emergency block for it when the install record
# cannot be read.
ts_m_render_killswitch_unit() {
    local fallback=""
    if [[ "${2:-}" =~ ^[1-9][0-9]*$ ]]; then
        fallback=" --fallback-uid ${2}"
    fi
    ts_m_render_unit_header
    cat <<EOF
[Unit]
Description=TunnelSats kill switch (nftables table, policy rules, table-51820 blackhole)
After=nftables.service
Before=$1 ${TS_M_WG_UNIT}

[Service]
Type=oneshot
RemainAfterExit=yes
# Runs inside the slice and keeps it active, so the slice's cgroup (and the id the rules hold)
# stays the same while member units restart
Slice=${TS_M_SLICE}
ExecStart=${TS_M_BIN} managed-arm${fallback}
# Stopping removes only the attestation; the kill switch stays armed
ExecStop=${TS_M_BIN} managed-disarm

[Install]
WantedBy=multi-user.target
EOF
}

ts_m_render_verifier_service() {
    ts_m_render_unit_header
    cat <<EOF
[Unit]
Description=TunnelSats verifier (re-arms the kill switch on drift)
After=${TS_M_KILLSWITCH_UNIT}

[Service]
Type=oneshot
ExecStart=${TS_M_BIN} managed-verify
EOF
}

ts_m_render_verifier_timer() {
    ts_m_render_unit_header
    cat <<'EOF'
[Unit]
Description=TunnelSats verifier every 30 seconds

[Timer]
OnBootSec=30s
OnUnitActiveSec=30s
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF
}

# Drop-in for the Lightning unit: runs it inside the slice and requires the kill switch unit, so
# Lightning starts only after managed-arm succeeded, which it does only when Lightning's clearnet
# traffic is tunneled (kill switch armed) or blocked (emergency block in effect). Nothing restarts
# the kill switch unit after install (the verifier re-arms directly), so Requires= stops or restarts
# Lightning only when an operator stops or restarts that unit. Deliberately not ordered after the
# tunnel, so a boot never waits for the VPN server or DNS; the kill switch blocks clearnet traffic
# of the slice while the tunnel is down.
ts_m_render_ln_dropin() {
    local profile="${1:-${TS_M_INV_PROFILE:-${TS_OPT_PROFILE:-}}}"
    ts_m_render_unit_header
    cat <<EOF
[Unit]
Requires=${TS_M_KILLSWITCH_UNIT}
After=${TS_M_KILLSWITCH_UNIT}

[Service]
Slice=${TS_M_SLICE}
EOF
    if [[ "$profile" == "mynode" ]]; then
        printf 'ExecStartPre=+%s managed-mynode-lnd-pre\n' "$TS_M_BIN"
    fi
}

ts_m_render_wg_dropin() {
    ts_m_render_unit_header
    cat <<EOF
[Unit]
Wants=${TS_M_KILLSWITCH_UNIT}
After=${TS_M_KILLSWITCH_UNIT}

[Service]
Restart=on-failure
RestartSec=30
Environment=WG_ENDPOINT_RESOLUTION_RETRIES=5
EOF
}

# Prints the managed tunnel config from the sanitized subscription config in file $1. DNS lines
# are dropped (lookups keep using the system resolver). wg-quick only sets the per-interface
# src_valid_mark (strict reverse-path filtering then accepts tunneled replies) and adds or removes
# the tunnel route in table 51820 (PreDown: while the interface still exists; marked traffic then
# ends in the blackhole); the kill switch and the policy rules are not part of wg-quick.
ts_m_render_wg_config() {
    awk '{ l = tolower($0); sub(/^[[:space:]]+/, "", l) } l ~ /^dns[[:space:]]*=/ { next } { print }' "$1" || return 1
    cat <<EOF

#Tunnelsats-Managed (generated by tunnelsats.sh install --managed)
[Interface]
Table = off
FwMark = 0x2000000
PostUp = sysctl -q -w net.ipv4.conf.%i.src_valid_mark=1
PostUp = ip route replace default dev %i table ${TS_M_RT_TABLE}
PreDown = ip route del default dev %i table ${TS_M_RT_TABLE} || true
EOF
}

# Attestation: written only after the kill switch was read back. $1 boot id, $2 profile, $3 impl,
# $4 unit, $5 slice cgroup id, $6 uid backstop (0|1), $7 time of writing.
ts_m_render_attestation() {
    ts_j_obj i:schema 1 s:boot_id "$1" r:armed true s:profile "$2" s:impl "$3" s:unit "$4" \
        s:slice "$TS_M_SLICE" i:slice_cgroup_id "$5" s:table "inet ${TS_M_NFT_TABLE}" \
        b:uid_backstop "$6" s:version "$VERSION" s:written_at "$7"
    printf '%s\n' "$TS_R"
}

# Inventory: everything install --managed writes and enables, so uninstall --managed removes
# exactly that. Uses TS_M_INV_*, TS_M_FILES/TS_M_FILE_SHA, TS_M_CREATED_DIRS, TS_M_ENABLED_UNITS
# and $1 = time of writing. One value per line, so the reader needs no JSON parser. While the
# state is "installing", a planned file that is not written yet has sha256 null.
ts_m_render_inventory() {
    local i items=() sq="'"
    printf '{\n'
    printf '  "schema": 1,\n'
    ts_j_str "$TS_M_INV_STATE"; printf '  "state": %s,\n' "$TS_R"
    ts_j_str "$TS_M_INV_PROFILE"; printf '  "profile": %s,\n' "$TS_R"
    ts_j_str "$TS_M_INV_IMPL"; printf '  "impl": %s,\n' "$TS_R"
    ts_j_str "$TS_M_INV_UNIT"; printf '  "unit": %s,\n' "$TS_R"
    ts_j_str "$TS_M_INV_USER"; printf '  "node_user": %s,\n' "$TS_R"
    ts_j_int_or_null "$TS_M_INV_UID"; printf '  "node_uid": %s,\n' "$TS_R"
    ts_j_bool_or_null "$TS_M_INV_BACKSTOP"; printf '  "uid_backstop": %s,\n' "$TS_R"
    ts_j_str "$TS_M_IFACE"; printf '  "iface": %s,\n' "$TS_R"
    ts_j_str "$VERSION"; printf '  "tool_version": %s,\n' "$TS_R"
    ts_j_str "$1"; printf '  "written_at": %s,\n' "$TS_R"
    for i in "${!TS_M_FILES[@]}"; do
        ts_j_obj s:path "${TS_M_FILES[$i]}" sn:sha256 "${TS_M_FILE_SHA[$i]:-}"
        items+=("$TS_R")
    done
    ts_m_print_inventory_list files "${items[@]}"
    items=()
    for i in "${!TS_M_CREATED_DIRS[@]}"; do
        ts_j_str "${TS_M_CREATED_DIRS[$i]}"
        items+=("$TS_R")
    done
    ts_m_print_inventory_list dirs_created "${items[@]}"
    items=()
    for i in "${!TS_M_ENABLED_UNITS[@]}"; do
        ts_j_str "${TS_M_ENABLED_UNITS[$i]}"
        items+=("$TS_R")
    done
    ts_m_print_inventory_list units_enabled "${items[@]}"
    # What a failed removal left (state "removing"); informational, for the repeated uninstall
    if [[ ${#TS_M_INV_REMAINING[@]} -gt 0 ]]; then
        items=()
        for i in "${!TS_M_INV_REMAINING[@]}"; do
            ts_j_str "${TS_M_INV_REMAINING[$i]//[\"\\]/$sq}"
            items+=("$TS_R")
        done
        ts_m_print_inventory_list remaining "${items[@]}"
    fi
    # The former VPN addresses LND may announce (state "removing"): the tunnel config is gone after a
    # failed removal, and the repeated uninstall still takes them out of LND's node announcement
    if [[ -n "${TS_M_INV_ANNOUNCE:-}" ]]; then
        ts_j_str "$TS_M_INV_ANNOUNCE"; printf '  "announce_addrs": %s,\n' "$TS_R"
    fi
    # Node configs are never edited in managed mode (the operator adds the hybrid settings)
    printf '  "node_config": []\n'
    printf '}\n'
}

# Prints inventory list $1 with the JSON values $2..., one per line.
ts_m_print_inventory_list() {
    printf '  "%s": [\n' "$1"
    shift
    while [[ $# -gt 0 ]]; do
        if [[ $# -gt 1 ]]; then
            printf '    %s,\n' "$1"
        else
            printf '    %s\n' "$1"
        fi
        shift
    done
    printf '  ],\n'
}

# Succeeds if $1 is a path managed mode may have written: removal never follows anything else,
# even from a modified inventory.
ts_m_inventory_path_ok() {
    local p="$1" entry unit
    if [[ "$p" == *".."* ]] || [[ "$p" == *"//"* ]] || [[ ! "$p" =~ ^/[A-Za-z0-9_.@/:-]+$ ]]; then
        return 1
    fi
    case "$p" in
        "$TS_M_BIN"|"$TS_M_WG_CONF"|"$TS_M_STATE_DIR"|"$TS_M_WG_DIR") return 0 ;;
        "${TS_M_UNIT_DIR}/${TS_M_SLICE_UNIT}"|"${TS_M_UNIT_DIR}/${TS_M_KILLSWITCH_UNIT}") return 0 ;;
        "${TS_M_UNIT_DIR}/${TS_M_VERIFIER_UNIT}"|"${TS_M_UNIT_DIR}/${TS_M_TIMER_UNIT}") return 0 ;;
        "${TS_M_UNIT_DIR}/${TS_M_WG_UNIT}.d"|"${TS_M_UNIT_DIR}/${TS_M_WG_UNIT}.d/${TS_M_DROPIN_NAME}") return 0 ;;
    esac
    # The drop-in of a Lightning unit managed mode can tunnel, and its directory
    for entry in $TS_M_ALL_LN_UNITS; do
        unit="${entry#*:}"
        if [[ "$p" == "${TS_M_UNIT_DIR}/${unit}.d" ]] || [[ "$p" == "${TS_M_UNIT_DIR}/${unit}.d/${TS_M_DROPIN_NAME}" ]]; then
            return 0
        fi
    done
    return 1
}

# Succeeds if "<impl>:<unit>" $2 is a Lightning unit that profile $1 can tunnel.
ts_m_profile_unit_ok() {
    case "$1" in
        baremetal) ts_in_list "$2" "$TS_M_LN_UNITS" ;;
        raspiblitz) ts_in_list "$2" "$TS_M_RASPIBLITZ_LN_UNITS" ;;
        mynode) ts_in_list "$2" "$TS_M_MYNODE_LN_UNITS" ;;
        *) return 1 ;;
    esac
}

# Reads the inventory into TS_M_INV_* (TS_M_INV_STATE: installing, installed or removing;
# TS_M_INV_REMAINING: what a failed removal left), TS_M_FILES and TS_M_FILE_SHA (empty for a planned
# file not written yet), TS_M_CREATED_DIRS and TS_M_ENABLED_UNITS. Every value is validated; returns
# 1 (with TS_M_ERROR) if the file is missing, unreadable or holds anything unexpected.
ts_m_inventory_read() {
    local f="${TS_FS_ROOT}${TS_M_INVENTORY}" line section="" key val path sha
    TS_M_INV_STATE=""
    TS_M_INV_PROFILE=""
    TS_M_INV_IMPL=""
    TS_M_INV_UNIT=""
    TS_M_INV_USER=""
    TS_M_INV_UID=""
    TS_M_INV_BACKSTOP=0
    TS_M_INV_REMAINING=()
    TS_M_INV_ANNOUNCE=""
    TS_M_FILES=()
    TS_M_FILE_SHA=()
    TS_M_CREATED_DIRS=()
    TS_M_ENABLED_UNITS=()
    TS_M_ERROR=""
    if [[ -L "$f" ]] || [[ ! -f "$f" ]] || [[ ! -r "$f" ]]; then
        TS_M_ERROR="inventory ${TS_M_INVENTORY} missing or unreadable"
        return 1
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^\ \ \"([a-z_]+)\":\ \[$ ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi
        if [[ "$line" =~ ^\ \ \]\,?$ ]]; then
            section=""
            continue
        fi
        if [[ -n "$section" ]]; then
            case "$section" in
                files)
                    if [[ ! "$line" =~ ^\ +\{\"path\":\"([^\"\\]+)\",\"sha256\":(\"([0-9a-f]{64})\"|null)\}\,?$ ]]; then
                        TS_M_ERROR="inventory holds an unexpected file entry"
                        return 1
                    fi
                    path="${BASH_REMATCH[1]}"
                    sha="${BASH_REMATCH[3]}"
                    if ! ts_m_inventory_path_ok "$path"; then
                        TS_M_ERROR="inventory lists an unexpected file: ${path}"
                        return 1
                    fi
                    TS_M_FILES+=("$path")
                    TS_M_FILE_SHA+=("$sha")
                    ;;
                dirs_created)
                    if [[ ! "$line" =~ ^\ +\"([^\"\\]+)\"\,?$ ]]; then
                        TS_M_ERROR="inventory holds an unexpected directory entry"
                        return 1
                    fi
                    path="${BASH_REMATCH[1]}"
                    if ! ts_m_inventory_path_ok "$path"; then
                        TS_M_ERROR="inventory lists an unexpected directory: ${path}"
                        return 1
                    fi
                    TS_M_CREATED_DIRS+=("$path")
                    ;;
                units_enabled)
                    if [[ ! "$line" =~ ^\ +\"([^\"\\]+)\"\,?$ ]]; then
                        TS_M_ERROR="inventory holds an unexpected unit entry"
                        return 1
                    fi
                    case "${BASH_REMATCH[1]}" in
                        "$TS_M_KILLSWITCH_UNIT"|"$TS_M_TIMER_UNIT"|"$TS_M_WG_UNIT") TS_M_ENABLED_UNITS+=("${BASH_REMATCH[1]}") ;;
                        *)
                            TS_M_ERROR="inventory lists an unexpected unit: ${BASH_REMATCH[1]}"
                            return 1
                            ;;
                    esac
                    ;;
                remaining)
                    if [[ ! "$line" =~ ^\ +\"([^\"\\]*)\"\,?$ ]]; then
                        TS_M_ERROR="inventory holds an unexpected remaining entry"
                        return 1
                    fi
                    TS_M_INV_REMAINING+=("${BASH_REMATCH[1]}")
                    ;;
            esac
            continue
        fi
        if [[ "$line" =~ ^\ \ \"([a-z_]+)\":\ (.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]%,}"
            if [[ "$val" =~ ^\"([^\"\\]*)\"$ ]]; then
                val="${BASH_REMATCH[1]}"
            fi
            case "$key" in
                state) TS_M_INV_STATE="$val" ;;
                profile) TS_M_INV_PROFILE="$val" ;;
                impl) TS_M_INV_IMPL="$val" ;;
                unit) TS_M_INV_UNIT="$val" ;;
                node_user) TS_M_INV_USER="$val" ;;
                node_uid) TS_M_INV_UID="$val" ;;
                announce_addrs)
                    if [[ "$val" =~ ^[0-9.]{7,15}:[0-9]{1,5}( [0-9.]{7,15}:[0-9]{1,5}){0,7}$ ]]; then
                        TS_M_INV_ANNOUNCE="$val"
                    fi
                    ;;
                uid_backstop)
                    if [[ "$val" == "true" ]]; then
                        TS_M_INV_BACKSTOP=1
                    fi
                    ;;
            esac
        fi
    done < "$f"
    case "$TS_M_INV_STATE" in
        installing|installed|removing) ;;
        *)
            TS_M_ERROR="inventory ${TS_M_INVENTORY} holds an unknown state (${TS_M_INV_STATE:-none})"
            return 1
            ;;
    esac
    if ! ts_in_list "$TS_M_INV_PROFILE" "$TS_M_PROFILES" || ! ts_in_list "$TS_M_INV_IMPL" "$TS_IMPLS" || \
        ! ts_m_profile_unit_ok "$TS_M_INV_PROFILE" "${TS_M_INV_IMPL}:${TS_M_INV_UNIT}" || \
        [[ ! "$TS_M_INV_USER" =~ ^[a-z_][a-z0-9_.-]{0,31}$ ]] || [[ ! "$TS_M_INV_UID" =~ ^[1-9][0-9]{0,9}$ ]]; then
        TS_M_ERROR="inventory ${TS_M_INVENTORY} holds invalid values"
        return 1
    fi
    return 0
}

# Prints the state the inventory records (installing, installed or removing); "unknown" if it
# cannot be read (detect runs without root, and the inventory is root-only).
ts_m_inventory_state() {
    local f="${TS_FS_ROOT}${TS_M_INVENTORY}" line=""
    if [[ ! -r "$f" ]]; then
        echo "unknown"
        return 0
    fi
    line=$(grep -m 1 -E '^  "state": "(installing|installed|removing)",?$' "$f" 2>/dev/null) || line=""
    case "$line" in
        *'"installing"'*) echo "installing" ;;
        *'"installed"'*) echo "installed" ;;
        *'"removing"'*) echo "removing" ;;
        *) echo "unknown" ;;
    esac
}

# Writes the inventory (root 0600) from the current TS_M_* state.
ts_m_inventory_write() {
    ts_m_render_inventory "$(date -u +%Y-%m-%dT%H:%M:%SZ)" | ts_m_write_file "${TS_FS_ROOT}${TS_M_INVENTORY}" 0600
}

# ---------------------------------------------------------------------------
# Managed mode: kernel state (kill switch, policy rules, table-51820 blackhole, emergency block)
# ---------------------------------------------------------------------------

ts_m_rule_prio() {
    case "$1" in
        main) echo "$TS_M_PRIO_MAIN" ;;
        mark) echo "$TS_M_PRIO_MARK" ;;
        uid) echo "$TS_M_PRIO_UID" ;;
    esac
}

# Selector of policy rule $1 (main, mark, uid) exactly as "ip rule show" prints it; $2 = node uid.
ts_m_rule_selector() {
    case "$1" in
        main) echo "from all lookup main suppress_prefixlength 0" ;;
        mark) echo "from all fwmark 0x1000000/0xff000000 lookup ${TS_M_RT_TABLE}" ;;
        uid) echo "from all uidrange ${2}-${2} lookup ${TS_M_RT_TABLE}" ;;
    esac
}

# Prints how often the rule "<priority $2>: <selector $3>" appears in the "ip rule show" listing $1.
ts_m_rule_count() {
    local listing="$1" prio="$2" sel="$3" line rest n=0
    while IFS= read -r line; do
        if [[ "$line" != "${prio}:"* ]]; then
            continue
        fi
        rest="${line#"${prio}":}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        rest="${rest%"${rest##*[![:space:]]}"}"
        if [[ "$rest" == "$sel" ]]; then
            n=$((n + 1))
        fi
    done < <(printf '%s\n' "$listing")
    echo "$n"
}

# Adds policy rule $2 (main, mark, uid) for IPv$1 unless it is present; $3 = node uid.
ts_m_rule_ensure() {
    local fam="$1" name="$2" uid="${3:-}" prio sel listing
    prio=$(ts_m_rule_prio "$name")
    sel=$(ts_m_rule_selector "$name" "$uid")
    listing=$("$IP_BIN" "-${fam}" rule show 2>/dev/null) || return 1
    if [[ "$(ts_m_rule_count "$listing" "$prio" "$sel")" -gt 0 ]]; then
        return 0
    fi
    # $sel is a list of selector words on purpose
    # shellcheck disable=SC2086
    "$IP_BIN" "-${fam}" rule add $sel priority "$prio"
}

# Deletes every copy of policy rule $2 for IPv$1 (bounded); returns 1 if a copy remains.
ts_m_rule_delete() {
    local fam="$1" name="$2" uid="${3:-}" prio sel listing n
    prio=$(ts_m_rule_prio "$name")
    sel=$(ts_m_rule_selector "$name" "$uid")
    for n in 1 2 3 4 5 6 7 8 9 10; do
        listing=$("$IP_BIN" "-${fam}" rule show 2>/dev/null) || return 1
        if [[ "$(ts_m_rule_count "$listing" "$prio" "$sel")" -eq 0 ]]; then
            return 0
        fi
        # shellcheck disable=SC2086
        "$IP_BIN" "-${fam}" rule del $sel priority "$prio" 2>/dev/null || return 1
    done
    return 1
}

# Prints the routes of table 51820 for IPv$1 (nothing if the table does not exist); returns 1 if
# the table cannot be read.
ts_m_table_routes() {
    local fam="$1" out="" rc=0
    out=$("$IP_BIN" "-${fam}" route show table "$TS_M_RT_TABLE" 2>&1) || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        case "$out" in
            *"FIB table does not exist"*) return 0 ;;
        esac
        return 1
    fi
    if [[ -n "$out" ]]; then
        printf '%s\n' "$out"
    fi
    return 0
}

# Succeeds if route line $1 is the kill switch blackhole (IPv6 lists it with "dev lo" and "pref").
ts_m_is_blackhole_line() {
    [[ "$1" =~ ^blackhole[[:space:]]+default([[:space:]]+dev[[:space:]]+lo)?[[:space:]]+metric[[:space:]]+${TS_M_BLACKHOLE_METRIC}([[:space:]]|$) ]]
}

# Succeeds if route line $1 is the tunnel route that wg-quick adds while the tunnel is up.
ts_m_is_tunnel_route_line() {
    [[ "$1" =~ ^default[[:space:]]+dev[[:space:]]+${TS_M_IFACE}([[:space:]]|$) ]]
}

# Prints how many kill switch blackholes table 51820 holds for IPv$1; fails if it cannot be read.
ts_m_blackhole_count() {
    local routes line n=0
    routes=$(ts_m_table_routes "$1") || return 1
    while IFS= read -r line; do
        if ts_m_is_blackhole_line "$line"; then
            n=$((n + 1))
        fi
    done < <(printf '%s\n' "$routes")
    echo "$n"
}

ts_m_blackhole_ensure() {
    local n
    n=$(ts_m_blackhole_count "$1") || return 1
    if [[ "$n" -gt 0 ]]; then
        return 0
    fi
    "$IP_BIN" "-${1}" route add blackhole default metric "$TS_M_BLACKHOLE_METRIC" table "$TS_M_RT_TABLE"
}

ts_m_blackhole_delete() {
    local n i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        n=$(ts_m_blackhole_count "$1") || return 1
        if [[ "$n" -eq 0 ]]; then
            return 0
        fi
        "$IP_BIN" "-${1}" route del blackhole default metric "$TS_M_BLACKHOLE_METRIC" table "$TS_M_RT_TABLE" 2>/dev/null || return 1
    done
    return 1
}

ts_m_nft_live_listing() {
    "$NFT_BIN" list table inet "$TS_M_NFT_TABLE" 2>/dev/null
}

# Prints the listing the kernel produces for ruleset file $1 when it is loaded into a throwaway
# network namespace: the expected form for this nft and kernel version, compared with the live
# table. The host's tables are not touched.
ts_m_nft_reference_listing() {
    "$UNSHARE_BIN" --net -- /bin/sh -c '"$1" -f "$2" >/dev/null && "$1" list table inet "$3"' \
        sh "$NFT_BIN" "$1" "$TS_M_NFT_TABLE" 2>/dev/null
}

# Normalizes an nft listing for comparison: counter values are dropped and whitespace collapses.
ts_m_nft_normalize() {
    sed -E 's/counter packets [0-9]+ bytes [0-9]+/counter/g' | tr -s '[:space:]' ' ' | sed -E 's/^ //; s/ $//'
}

# Compares the kernel with the expected kill switch and sets TS_M_DRIFT to the findings (empty when
# everything matches): the live nftables table against the listing of ruleset file $1 loaded into a
# throwaway network namespace, the policy rules (uid rule if $2 = 1, for node uid $3) and the
# table-51820 blackholes, for IPv4 and (if the kernel has it) IPv6.
ts_m_kernel_readback() {
    local rsfile="$1" backstop="$2" uid="$3" live="" ref="" fam listing name n
    TS_M_DRIFT=()
    live=$(ts_m_nft_live_listing) || live=""
    if [[ -z "$live" ]]; then
        TS_M_DRIFT+=("nft table inet ${TS_M_NFT_TABLE} is missing")
    else
        ref=$(ts_m_nft_reference_listing "$rsfile") || ref=""
        if [[ -z "$ref" ]]; then
            TS_M_DRIFT+=("the expected ruleset could not be loaded for comparison (is ${TS_M_SLICE} active?)")
        elif [[ "$(printf '%s\n' "$live" | ts_m_nft_normalize)" != "$(printf '%s\n' "$ref" | ts_m_nft_normalize)" ]]; then
            TS_M_DRIFT+=("nft table inet ${TS_M_NFT_TABLE} differs from the expected ruleset")
        fi
    fi
    for fam in 4 6; do
        if [[ "$fam" == "6" ]] && ! ts_m_ipv6_available; then
            continue
        fi
        if ! listing=$("$IP_BIN" "-${fam}" rule show 2>/dev/null); then
            TS_M_DRIFT+=("IPv${fam} policy rules cannot be read")
        else
            for name in main mark uid; do
                if [[ "$name" == "uid" ]] && [[ "$backstop" != "1" ]]; then
                    continue
                fi
                n=$(ts_m_rule_count "$listing" "$(ts_m_rule_prio "$name")" "$(ts_m_rule_selector "$name" "$uid")")
                if [[ "$n" -ne 1 ]]; then
                    TS_M_DRIFT+=("IPv${fam} rule $(ts_m_rule_prio "$name") is present ${n} times")
                fi
            done
        fi
        if ! n=$(ts_m_blackhole_count "$fam"); then
            TS_M_DRIFT+=("IPv${fam} table ${TS_M_RT_TABLE} cannot be read")
        elif [[ "$n" -ne 1 ]]; then
            TS_M_DRIFT+=("IPv${fam} blackhole in table ${TS_M_RT_TABLE} is present ${n} times")
        fi
    done
    return 0
}

# Arms the kill switch and attests it: loads the ruleset as one transaction, adds the missing
# policy rules and table-51820 blackholes (IPv4 and IPv6), reads everything back and only then
# writes the attestation. $1 profile, $2 impl, $3 unit, $4 node uid, $5 uid backstop (0|1).
# Returns 1 with TS_M_ERROR set if a step or the read-back fails; no attestation is written then.
ts_m_killswitch_apply() {
    local profile="$1" impl="$2" unit="$3" uid="$4" backstop="$5" rsfile fam err="" id boot doc
    TS_M_ERROR=""
    if ! ts_m_ensure_run_dir; then
        TS_M_ERROR="cannot create ${TS_M_RUN_DIR}"
        return 1
    fi
    rsfile="${TS_FS_ROOT}${TS_M_RULESET_FILE}"
    if ! ts_m_render_ruleset > "$rsfile"; then
        TS_M_ERROR="cannot write ${TS_M_RULESET_FILE}"
        return 1
    fi
    if ! err=$("$NFT_BIN" -f "$rsfile" 2>&1); then
        err="${err//$'\n'/ }"
        TS_M_ERROR="nft refused the kill switch ruleset (the previous table, if any, stays loaded): ${err:0:400}"
        return 1
    fi
    for fam in 4 6; do
        if [[ "$fam" == "6" ]] && ! ts_m_ipv6_available; then
            continue
        fi
        if ! ts_m_rule_ensure "$fam" main || ! ts_m_rule_ensure "$fam" mark; then
            TS_M_ERROR="cannot add the IPv${fam} policy rules ${TS_M_PRIO_MAIN} and ${TS_M_PRIO_MARK}"
            return 1
        fi
        if [[ "$backstop" == "1" ]] && ! ts_m_rule_ensure "$fam" uid "$uid"; then
            TS_M_ERROR="cannot add the IPv${fam} uid backstop rule ${TS_M_PRIO_UID}"
            return 1
        fi
        if ! ts_m_blackhole_ensure "$fam"; then
            TS_M_ERROR="cannot add the IPv${fam} blackhole to table ${TS_M_RT_TABLE}"
            return 1
        fi
    done
    ts_m_kernel_readback "$rsfile" "$backstop" "$uid"
    if [[ ${#TS_M_DRIFT[@]} -gt 0 ]]; then
        TS_M_ERROR="read-back failed: ${TS_M_DRIFT[*]}"
        return 1
    fi
    if ! id=$(ts_m_slice_cgroup_id); then
        TS_M_ERROR="${TS_M_SLICE} has no cgroup"
        return 1
    fi
    if ! boot=$(ts_m_boot_id); then
        TS_M_ERROR="cannot read the boot id"
        return 1
    fi
    doc=$(ts_m_render_attestation "$boot" "$profile" "$impl" "$unit" "$id" "$backstop" "$(date -u +%Y-%m-%dT%H:%M:%SZ)")
    if ! printf '%s\n' "$doc" | ts_m_write_file "${TS_FS_ROOT}${TS_M_ATTEST}" 0644; then
        TS_M_ERROR="cannot write ${TS_M_ATTEST}"
        return 1
    fi
    return 0
}

# Removes the attestation only; the kill switch stays armed (ExecStop of the kill switch unit).
ts_m_killswitch_disarm() {
    rm -f "${TS_FS_ROOT}${TS_M_ATTEST}"
}

# Removes exactly what ts_m_killswitch_apply creates: the nftables table, the policy rules
# (including the uid rule of node uid $1, if given) and the blackholes, for IPv4 and IPv6, and the
# attestation. Foreign rules and routes are never touched. Returns 1 with TS_M_ERROR naming what is
# still present.
ts_m_killswitch_remove() {
    local uid="${1:-}" fam left=() n
    TS_M_ERROR=""
    rm -f "${TS_FS_ROOT}${TS_M_ATTEST}" "${TS_FS_ROOT}${TS_M_RULESET_FILE}"
    if ts_m_nft_live_listing >/dev/null; then
        "$NFT_BIN" delete table inet "$TS_M_NFT_TABLE" 2>/dev/null || true
    fi
    if ts_m_nft_live_listing >/dev/null; then
        left+=("nft table inet ${TS_M_NFT_TABLE}")
    fi
    for fam in 4 6; do
        if ! ts_m_rule_delete "$fam" main; then
            left+=("IPv${fam} rule ${TS_M_PRIO_MAIN}")
        fi
        if ! ts_m_rule_delete "$fam" mark; then
            left+=("IPv${fam} rule ${TS_M_PRIO_MARK}")
        fi
        if [[ -n "$uid" ]] && ! ts_m_rule_delete "$fam" uid "$uid"; then
            left+=("IPv${fam} rule ${TS_M_PRIO_UID}")
        fi
        if ! ts_m_blackhole_delete "$fam"; then
            left+=("IPv${fam} blackhole in table ${TS_M_RT_TABLE}")
        fi
    done
    if [[ ${#left[@]} -gt 0 ]]; then
        TS_M_ERROR="still present: ${left[*]}"
        return 1
    fi
    return 0
}

# Emergency block for managed mode: blackhole policy rules for the node uid at priority 21819
# (IPv4 through the shared ts_arm_failclosed_rules, IPv6 here). They are evaluated before table
# main, so every route of that uid to the internet ends in a blackhole: Lightning clearnet traffic
# stops, and bitcoind loses its internet peers if it runs under the same uid. Loopback keeps working
# through table local (Tor SOCKS and control port, local RPC), and exemptions at priority 21817 keep
# the local network (ts_m_emergency_lan_arm). The block is armed when the kill switch cannot be
# armed and released only after a successful re-arm and read-back. The net_cls-based nft emergency
# table is never used in managed mode: slice processes do not carry its classid.
ts_m_emergency6_selector() {
    echo "from all uidrange ${1}-${1} blackhole"
}

# Selector of the local network exemption for range $1 and node uid $2, as "ip rule show" prints it.
# "lookup main suppress_prefixlength 0" lets only specific (on-link or explicitly routed) routes of
# table main through; a destination that only the default route would reach falls through to the
# blackhole.
ts_m_emergency_lan_selector() {
    echo "from all to ${1} uidrange ${2}-${2} lookup main suppress_prefixlength 0"
}

# Succeeds if rule selector $1 (as "ip rule show" prints it) is a local network exemption of the
# emergency block, for any uid.
ts_m_is_emergency_lan_rule() {
    local sel="$1" range rest r
    sel="${sel#"${sel%%[![:space:]]*}"}"
    sel="${sel%"${sel##*[![:space:]]}"}"
    if [[ "$sel" != "from all to "* ]]; then
        return 1
    fi
    rest="${sel#from all to }"
    range="${rest%% *}"
    rest="${rest#"$range" }"
    if [[ ! "$rest" =~ ^uidrange\ ([0-9]+)-([0-9]+)\ lookup\ main\ suppress_prefixlength\ 0$ ]] || \
        [[ "${BASH_REMATCH[1]}" != "${BASH_REMATCH[2]}" ]]; then
        return 1
    fi
    for r in $TS_M_EMERGENCY_LAN4 $TS_M_EMERGENCY_LAN6; do
        if [[ "$range" == "$r" ]]; then
            return 0
        fi
    done
    return 1
}

# Prints the ranges of IP family $1 that the emergency block keeps reachable (nothing for IPv6
# when the host has none).
ts_m_emergency_lan_ranges() {
    if [[ "$1" == "4" ]]; then
        echo "$TS_M_EMERGENCY_LAN4"
    elif ts_m_ipv6_available; then
        echo "$TS_M_EMERGENCY_LAN6"
    fi
}

# Adds the local network exemptions for node uid $1 that are missing and records each one it
# added, once. Arming again (the verifier does on every run while the block holds) adds nothing,
# so there are never more than 5 IPv4 and 2 IPv6 exemptions per uid. Best effort: the block's
# safety rests on its blackholes, a missing exemption only costs that local network (verify
# reports it as emergency_lan).
ts_m_emergency_lan_arm() {
    local uid="$1" fam range listing state="${TS_FS_ROOT}${TS_M_EMERGENCY_LAN_STATE}"
    for fam in 4 6; do
        listing=$("$IP_BIN" "-${fam}" rule show 2>/dev/null) || continue
        for range in $(ts_m_emergency_lan_ranges "$fam"); do
            if [[ "$(ts_m_rule_count "$listing" "$TS_M_EMERGENCY_LAN_PRIO" "$(ts_m_emergency_lan_selector "$range" "$uid")")" -gt 0 ]]; then
                continue
            fi
            if ! "$IP_BIN" "-${fam}" rule add to "$range" uidrange "${uid}-${uid}" lookup main suppress_prefixlength 0 priority "$TS_M_EMERGENCY_LAN_PRIO" 2>/dev/null; then
                continue
            fi
            if grep -qxF "${fam} ${range} ${uid}" "$state" 2>/dev/null; then
                # Added back after another tool removed it: it is recorded already
                continue
            fi
            if ! ts_m_ensure_run_dir || ! printf '%s %s %s\n' "$fam" "$range" "$uid" >> "$state"; then
                # Unrecorded, it could not be released later: take it back
                "$IP_BIN" "-${fam}" rule del to "$range" uidrange "${uid}-${uid}" lookup main suppress_prefixlength 0 priority "$TS_M_EMERGENCY_LAN_PRIO" 2>/dev/null || true
            fi
        done
    done
    return 0
}

# Prints "<missing> <total>": how many of the local network exemptions for node uid $1 are missing.
ts_m_emergency_lan_missing() {
    local uid="$1" fam range listing missing=0 total=0
    for fam in 4 6; do
        listing=$("$IP_BIN" "-${fam}" rule show 2>/dev/null) || listing=""
        for range in $(ts_m_emergency_lan_ranges "$fam"); do
            total=$((total + 1))
            if [[ "$(ts_m_rule_count "$listing" "$TS_M_EMERGENCY_LAN_PRIO" "$(ts_m_emergency_lan_selector "$range" "$uid")")" -eq 0 ]]; then
                missing=$((missing + 1))
            fi
        done
    done
    echo "$missing $total"
}

# Removes the local network exemptions TunnelSats recorded; keeps the record of any that remain.
# Returns 1 if one remains.
ts_m_emergency_lan_release() {
    local state="${TS_FS_ROOT}${TS_M_EMERGENCY_LAN_STATE}" fam range uid listing n failed=0 keep=()
    if [[ ! -f "$state" ]]; then
        return 0
    fi
    while read -r fam range uid <&3; do
        if [[ ! "$fam" =~ ^[46]$ ]] || [[ ! "$uid" =~ ^[1-9][0-9]*$ ]] || [[ -z "$range" ]]; then
            continue
        fi
        if [[ "$fam" == "6" ]] && ! ts_m_ipv6_available; then
            continue
        fi
        for n in 1 2 3 4 5; do
            listing=$("$IP_BIN" "-${fam}" rule show 2>/dev/null) || break
            if [[ "$(ts_m_rule_count "$listing" "$TS_M_EMERGENCY_LAN_PRIO" "$(ts_m_emergency_lan_selector "$range" "$uid")")" -eq 0 ]]; then
                break
            fi
            "$IP_BIN" "-${fam}" rule del to "$range" uidrange "${uid}-${uid}" lookup main suppress_prefixlength 0 priority "$TS_M_EMERGENCY_LAN_PRIO" 2>/dev/null || break
        done
        listing=$("$IP_BIN" "-${fam}" rule show 2>/dev/null) || listing="unreadable"
        if [[ "$listing" == "unreadable" ]] || \
            [[ "$(ts_m_rule_count "$listing" "$TS_M_EMERGENCY_LAN_PRIO" "$(ts_m_emergency_lan_selector "$range" "$uid")")" -gt 0 ]]; then
            failed=1
            keep+=("${fam} ${range} ${uid}")
        fi
    done 3< "$state"
    if [[ ${#keep[@]} -eq 0 ]]; then
        rm -f "$state"
    else
        printf '%s\n' "${keep[@]}" > "$state" 2>/dev/null || true
    fi
    [[ "$failed" -eq 0 ]]
}

# Arms the emergency block for node uid $1 (blackholes, then the local network exemptions);
# succeeds only if the blackholes are verified in place.
ts_m_emergency_arm() {
    local uid="$1" listing state
    if [[ ! "$uid" =~ ^[1-9][0-9]*$ ]]; then
        return 1
    fi
    if ! ts_arm_failclosed_rules "$TS_M_EMERGENCY_SUBNET" "$uid"; then
        return 1
    fi
    if ts_m_ipv6_available; then
        listing=$("$IP_BIN" -6 rule show 2>/dev/null) || return 1
        if [[ "$(ts_m_rule_count "$listing" 21819 "$(ts_m_emergency6_selector "$uid")")" -eq 0 ]]; then
            "$IP_BIN" -6 rule add uidrange "${uid}-${uid}" blackhole priority 21819 || return 1
            state="${TS_FS_ROOT}${TS_M_EMERGENCY6_STATE}"
            if ! ts_m_ensure_run_dir || ! printf 'uidrange %s-%s\n' "$uid" "$uid" > "$state"; then
                "$IP_BIN" -6 rule del uidrange "${uid}-${uid}" blackhole priority 21819 2>/dev/null || true
                return 1
            fi
        fi
    fi
    ts_m_emergency_lan_arm "$uid"
    ts_m_emergency_verified "$uid"
}

# Succeeds if the emergency block for node uid $1 is completely in place (IPv4 and IPv6).
ts_m_emergency_verified() {
    local uid="$1" listing
    ts_failclosed_rules_verified "$TS_M_EMERGENCY_SUBNET" "$uid" || return 1
    if ts_m_ipv6_available; then
        listing=$("$IP_BIN" -6 rule show 2>/dev/null) || return 1
        if [[ "$(ts_m_rule_count "$listing" 21819 "$(ts_m_emergency6_selector "$uid")")" -eq 0 ]]; then
            return 1
        fi
    fi
    return 0
}

# Succeeds if any emergency rule for node uid $1 is present.
ts_m_emergency_present() {
    local uid="$1" listing
    listing=$("$IP_BIN" -4 rule show 2>/dev/null) || return 0
    if printf '%s\n' "$listing" | grep -Eq "^21819:[[:space:]]+from all uidrange ${uid}-${uid}[[:space:]]+blackhole[[:space:]]*$"; then
        return 0
    fi
    if ts_m_ipv6_available; then
        listing=$("$IP_BIN" -6 rule show 2>/dev/null) || return 0
        if [[ "$(ts_m_rule_count "$listing" 21819 "$(ts_m_emergency6_selector "$uid")")" -gt 0 ]]; then
            return 0
        fi
    fi
    return 1
}

# Succeeds if a Tailscale exit node (default route in table 52) is active.
ts_m_tailscale_exit_node() {
    local out=""
    out=$("$IP_BIN" route show table 52 2>/dev/null) || return 1
    printf '%s\n' "$out" | grep -qE '^(default|0\.0\.0\.0/0)[[:space:]]'
}

# Prints the rules of another tool in listing $2 ("ip -<fam> rule show" of family $1) that come
# before priority $3, one per line as "IPv<fam> rule before <$3>: <rule>"; $4 = 1 while a Tailscale
# exit node is active. Not listed: the local rule at 0, Tailscale's rules (5200-5299) while no exit
# node is active, and TunnelSats's own emergency rules (the local network exemptions at 21817, the
# blackholes at 21818 and 21819). Meant for priorities up to 21820, below TunnelSats's other rules.
ts_m_rules_before() {
    local fam="$1" listing="$2" before="$3" exit_node="$4" line prio
    while IFS= read -r line; do
        prio="${line%%:*}"
        if [[ ! "$prio" =~ ^[0-9]+$ ]] || [[ "$prio" -ge "$before" ]]; then
            continue
        fi
        if [[ "$prio" -eq 0 ]] && [[ "$line" =~ ^0:[[:space:]]+from\ all\ lookup\ local[[:space:]]*$ ]]; then
            continue
        fi
        if [[ "$prio" -eq "$TS_M_EMERGENCY_LAN_PRIO" ]] && ts_m_is_emergency_lan_rule "${line#*:}"; then
            continue
        fi
        if [[ "$prio" -eq 21818 || "$prio" -eq 21819 ]] && [[ "$line" =~ [[:space:]]blackhole[[:space:]]*$ ]]; then
            continue
        fi
        if [[ "$prio" -ge 5200 ]] && [[ "$prio" -le 5299 ]] && [[ "$exit_node" -eq 0 ]]; then
            continue
        fi
        echo "IPv${fam} rule before ${before}: ${line//$'\t'/ }"
    done < <(printf '%s\n' "$listing")
}

# Prints the rules of another tool before priority $1 in both families (IPv6 where available), as
# ts_m_rules_before does. A family whose rules cannot be read is printed as "IPv<fam> rules cannot
# be read" and makes it return 1.
ts_m_foreign_rules_before() {
    local before="$1" fam listing exit_node=0 rc=0
    if ts_m_tailscale_exit_node; then
        exit_node=1
    fi
    for fam in 4 6; do
        if [[ "$fam" == "6" ]] && ! ts_m_ipv6_available; then
            continue
        fi
        if ! listing=$("$IP_BIN" "-${fam}" rule show 2>/dev/null); then
            echo "IPv${fam} rules cannot be read"
            rc=1
            continue
        fi
        ts_m_rules_before "$fam" "$listing" "$before" "$exit_node"
    done
    return "$rc"
}

# Succeeds if the emergency block for node uid $1 is in effect: its rules are verified (IPv4, and
# IPv6 where available) and no rule of another tool comes before them (priority 21818) in either
# family, where it could route the node's traffic around the blackholes. Otherwise sets TS_M_ERROR
# to the reason, naming such rules, and TS_M_EMERG_FAIL to "incomplete" (rules missing) or
# "bypassed" (a rule of another tool before them). verify, managed-arm and the verifier all decide
# "blocked" by this predicate alone.
ts_m_emergency_effective() {
    local uid="$1" before=""
    TS_M_EMERG_FAIL=""
    if ! ts_m_emergency_verified "$uid"; then
        TS_M_ERROR="not all of its rules (priority 21818 and 21819) are in place"
        TS_M_EMERG_FAIL="incomplete"
        return 1
    fi
    before=$(ts_m_foreign_rules_before 21818) || true
    if [[ -n "$before" ]]; then
        TS_M_ERROR="${before//$'\n'/; }"
        TS_M_EMERG_FAIL="bypassed"
        return 1
    fi
    return 0
}

# Removes the emergency rules TunnelSats recorded (IPv4 state file of the shared helpers, IPv6
# state and the local network exemptions in /run/tunnelsats). Returns 1 if one remains.
ts_m_emergency_release() {
    local uid="$1" state="${TS_FS_ROOT}${TS_M_EMERGENCY6_STATE}" n listing failed=0 fam r ranges
    ts_release_failclosed_rules || failed=1
    ts_m_emergency_lan_release || failed=1
    if [[ -f "$state" ]] && ts_m_ipv6_available; then
        rm -f "$state"
    fi
    for fam in 4 6; do
        if [[ "$fam" == "6" ]] && ! ts_m_ipv6_available; then continue; fi
        for n in 1 2 3 4 5; do
            listing=$("$IP_BIN" "-${fam}" rule show 2>/dev/null) || { failed=1; break; }
            local to_del=()
            if [[ "$fam" == "4" ]] && [[ "$(ts_m_rule_count "$listing" 21818 "from ${TS_M_EMERGENCY_SUBNET} blackhole")" -gt 0 ]]; then
                to_del+=("$IP_BIN -4 rule del priority 21818 from ${TS_M_EMERGENCY_SUBNET} blackhole")
            fi
            if [[ "$(ts_m_rule_count "$listing" 21819 "$(ts_m_emergency6_selector "$uid")")" -gt 0 ]]; then
                to_del+=("$IP_BIN -${fam} rule del priority 21819 uidrange ${uid}-${uid} blackhole")
            fi
            if [[ "$fam" == "4" ]]; then ranges="$TS_M_EMERGENCY_LAN4"; else ranges="$TS_M_EMERGENCY_LAN6"; fi
            for r in $ranges; do
                if [[ "$(ts_m_rule_count "$listing" "$TS_M_EMERGENCY_LAN_PRIO" "$(ts_m_emergency_lan_selector "$r" "$uid")")" -gt 0 ]]; then
                    to_del+=("$IP_BIN -${fam} rule del to $r uidrange ${uid}-${uid} lookup main suppress_prefixlength 0 priority $TS_M_EMERGENCY_LAN_PRIO")
                fi
            done
            if [[ ${#to_del[@]} -eq 0 ]]; then break; fi
            for cmd in "${to_del[@]}"; do
                $cmd 2>/dev/null || failed=1
            done
        done
        listing=$("$IP_BIN" "-${fam}" rule show 2>/dev/null) || { failed=1; continue; }
        if [[ "$fam" == "4" ]] && [[ "$(ts_m_rule_count "$listing" 21818 "from ${TS_M_EMERGENCY_SUBNET} blackhole")" -gt 0 ]]; then failed=1; fi
        if [[ "$(ts_m_rule_count "$listing" 21819 "$(ts_m_emergency6_selector "$uid")")" -gt 0 ]]; then failed=1; fi
        if [[ "$fam" == "4" ]]; then ranges="$TS_M_EMERGENCY_LAN4"; else ranges="$TS_M_EMERGENCY_LAN6"; fi
        for r in $ranges; do
            if [[ "$(ts_m_rule_count "$listing" "$TS_M_EMERGENCY_LAN_PRIO" "$(ts_m_emergency_lan_selector "$r" "$uid")")" -gt 0 ]]; then failed=1; fi
        done
    done
    [[ "$failed" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# Managed mode: internal verbs run by the units (managed-arm, managed-disarm, managed-verify) and
# by verify's probes (managed-probe). They log to stderr, which systemd sends to the journal.
# ---------------------------------------------------------------------------

ts_m_log() {
    echo "TunnelSats: $*" >&2
}

# Records verifier state $1 (armed, failclosed, damaged, stopping, stopped, unprotected) and logs
# message $2 only when the state changes, so a steady state never repeats itself in the journal.
ts_m_state_change() {
    local new="$1" msg="$2" f="${TS_FS_ROOT}${TS_M_VERIFIER_STATE}" old=""
    old=$(cat "$f" 2>/dev/null) || old=""
    if [[ "$old" != "$new" ]]; then
        ts_m_log "$msg"
        if ts_m_ensure_run_dir; then
            printf '%s\n' "$new" > "$f" 2>/dev/null || true
        fi
    fi
    return 0
}

# Records protected state $1 (armed, failclosed, damaged) with message $2, as ts_m_state_change
# does, then starts the Lightning units the verifier stopped while no protection held.
ts_m_state_protected() {
    ts_m_state_change "$1" "$2"
    ts_m_resume_stopped
}

# Prints the status recorded for unit $1 in TS_M_STOPPED (stopped, starting, retrying or
# start-failed); fails if the unit is not recorded.
ts_m_stopped_status() {
    local f="${TS_FS_ROOT}${TS_M_STOPPED}" u st _n
    if [[ ! -f "$f" ]]; then
        return 1
    fi
    while read -r u st _n; do
        if [[ "$u" == "$1" ]]; then
            echo "${st:-stopped}"
            return 0
        fi
    done < "$f"
    return 1
}

# Records status $2 and start attempts $3 (default 0) for unit $1 in TS_M_STOPPED, one line
# "<unit> <status> <attempts>" per unit, replacing an earlier line for it; status "-" removes the
# unit, and the file goes with its last unit. Fails if the record cannot be written.
ts_m_stopped_set() {
    local f="${TS_FS_ROOT}${TS_M_STOPPED}" u st n lines=()
    if [[ -f "$f" ]]; then
        while read -r u st n; do
            if [[ -n "$u" ]] && [[ "$u" != "$1" ]]; then
                lines+=("$u ${st:-stopped} ${n:-0}")
            fi
        done < "$f"
    fi
    if [[ "$2" != "-" ]]; then
        lines+=("$1 $2 ${3:-0}")
    fi
    if [[ ${#lines[@]} -eq 0 ]]; then
        rm -f "$f"
        return 0
    fi
    ts_m_ensure_run_dir || return 1
    printf '%s\n' "${lines[@]}" > "${f}.tmp" 2>/dev/null && mv -f "${f}.tmp" "$f" 2>/dev/null
}

# Starts the Lightning units recorded in TS_M_STOPPED (stopped by ts_m_quarantine) again. Called
# only while a protection holds: the kill switch is armed and verified, or the emergency block is
# in effect. A unit stays recorded until a later check finds it running, so a start that systemd
# accepts but that fails (for example at the unit's start limit) is retried with each check, up to
# TS_M_RESUME_MAX starts; then the command to start it by hand is logged and the unit is dropped.
# The start does not block, because the caller holds the kill switch lock, which a start of the
# kill switch unit takes. Each change of a unit's status is logged once.
ts_m_resume_stopped() {
    local f="${TS_FS_ROOT}${TS_M_STOPPED}" unit st n state err="" new e entries=()
    if [[ ! -f "$f" ]]; then
        return 0
    fi
    while read -r unit st n; do
        if [[ "$unit" =~ ^[A-Za-z0-9@._:-]+\.service$ ]]; then
            if [[ ! "$n" =~ ^[0-9]+$ ]]; then
                n=0
            fi
            entries+=("${unit} ${st:-stopped} ${n}")
        fi
    done < "$f"
    if [[ ${#entries[@]} -eq 0 ]]; then
        rm -f "$f"
        return 0
    fi
    for e in "${entries[@]}"; do
        read -r unit st n <<< "$e"
        if ! state=$(ts_m_unit_prop "$unit" ActiveState); then
            state="unknown"
        fi
        case "$state" in
            active|reloading|refreshing)
                if ! ts_m_stopped_set "$unit" -; then
                    ts_m_log "cannot update ${TS_M_STOPPED}"
                fi
                ts_m_log "${unit} runs again"
                continue
                ;;
            activating)
                continue
                ;;
        esac
        n=$((n + 1))
        if [[ "$n" -gt "$TS_M_RESUME_MAX" ]]; then
            if ! ts_m_stopped_set "$unit" -; then
                ts_m_log "cannot update ${TS_M_STOPPED}"
            fi
            ts_m_log "${unit} did not start after ${TS_M_RESUME_MAX} attempts (state ${state:-unknown}); no further attempts. Start it with: systemctl start ${unit}"
            continue
        fi
        if err=$("$SYSTEMCTL_BIN" start --no-block "$unit" 2>&1); then
            case "$st" in
                starting|retrying)
                    new="retrying"
                    if [[ "$st" == "starting" ]]; then
                        ts_m_log "${unit} did not start (state ${state:-unknown}); trying again with each check"
                    fi
                    ;;
                *)
                    new="starting"
                    ts_m_log "protection holds again; starting ${unit} again"
                    ;;
            esac
        else
            new="start-failed"
            if [[ "$st" != "start-failed" ]]; then
                ts_m_log "protection holds again, but ${unit} could not be started (${err:-no reason given}); trying again with each check"
            fi
        fi
        if ! ts_m_stopped_set "$unit" "$new" "$n"; then
            ts_m_log "cannot update ${TS_M_STOPPED}"
        fi
    done
    return 0
}

# Prints the Lightning units that carry the TunnelSats drop-in, one per line. Read from the unit
# directory, so it works while the install record is unreadable or systemd does not answer. Covers
# the units of every profile (RaspiBlitz testnet and signet units included).
ts_m_dropin_units() {
    local e unit
    for e in $TS_M_ALL_LN_UNITS; do
        unit="${e#*:}"
        if [[ -f "${TS_FS_ROOT}${TS_M_UNIT_DIR}/${unit}.d/${TS_M_DROPIN_NAME}" ]]; then
            echo "$unit"
        fi
    done
}

# Waits up to TS_M_STOP_WAIT seconds for unit $1 to leave the active states and prints its
# ActiveState ("unknown" if systemd cannot tell). Used after a stop that does not block, so the
# kill switch lock is never held for a whole shutdown of the Lightning daemon.
ts_m_wait_stopped() {
    local unit="$1" state="" i=0 steps=$((TS_M_STOP_WAIT * 2))
    while true; do
        if ! state=$(ts_m_unit_prop "$unit" ActiveState); then
            state="unknown"
        fi
        case "$state" in
            active|activating|deactivating|reloading|refreshing) ;;
            *) break ;;
        esac
        if [[ "$i" -ge "$steps" ]]; then
            break
        fi
        sleep 0.5
        i=$((i + 1))
    done
    echo "${state:-unknown}"
}

# Last resort of the verifier when neither the kill switch nor the emergency block holds ($1 =
# why): stops the Lightning units $2... without blocking and reads back, for up to TS_M_STOP_WAIT
# seconds, that each is no longer active. A unit that was running is recorded in TS_M_STOPPED
# before it is stopped, so ts_m_resume_stopped starts it again once a protection holds. Logs one
# state per change: "stopped" (no unit runs), "stopping" (a unit is still shutting down; the next
# check confirms it) or "unprotected" (a unit is still running, systemd cannot tell, or no unit is
# known). Returns 0 when every unit is confirmed stopped, 1 otherwise; the verifier exits 1 either
# way.
ts_m_quarantine() {
    local why="$1" unit state err="" failed=() stopping=() names=()
    shift
    if [[ $# -eq 0 ]]; then
        ts_m_state_change unprotected "${why}; no Lightning unit with the TunnelSats drop-in was found to stop"
        return 1
    fi
    for unit in "$@"; do
        names+=("$unit")
        if ! state=$(ts_m_unit_prop "$unit" ActiveState); then
            state="unknown"
        fi
        if [[ "$state" == "inactive" ]] || [[ "$state" == "failed" ]]; then
            continue
        fi
        if ! ts_m_stopped_set "$unit" stopped; then
            ts_m_log "cannot record ${unit} in ${TS_M_STOPPED}; it will not be started again automatically"
        fi
        if err=$("$SYSTEMCTL_BIN" stop --no-block "$unit" 2>&1); then
            err=""
            state=$(ts_m_wait_stopped "$unit")
        else
            err="${err:-systemctl stop failed}"
            if ! state=$(ts_m_unit_prop "$unit" ActiveState); then
                state="unknown"
            fi
        fi
        case "$state" in
            inactive|failed) ;;
            deactivating) stopping+=("$unit") ;;
            *) failed+=("${unit} (state ${state:-unknown}${err:+; ${err//$'\n'/ }})") ;;
        esac
    done
    if [[ ${#failed[@]} -gt 0 ]]; then
        ts_m_state_change unprotected "${why}; could not stop ${failed[*]}. Stop it until the kill switch or the emergency block holds again."
        return 1
    fi
    if [[ ${#stopping[@]} -gt 0 ]]; then
        ts_m_state_change stopping "${why}; ${stopping[*]} is shutting down; the next check confirms that it stopped. It starts again once the kill switch or the emergency block holds."
        return 1
    fi
    ts_m_state_change stopped "${why}; ${names[*]} stopped, so no Lightning traffic leaves outside the tunnel. It starts again once the kill switch or the emergency block holds."
    return 0
}

# Fail-closed path when the kill switch cannot be armed: removes the attestation and arms the
# emergency block for the node uid. $1 = reason. Succeeds only if the block is in effect
# (ts_m_emergency_effective). Otherwise it sets TS_M_ERROR to the reason and why the block does not
# hold, and returns 1: the Lightning user changed, the block could not be armed, or a rule of another
# tool routes around it (the block stays armed then; it still covers what that rule does not). The
# caller acts on that: managed-arm exits 1, so Lightning does not start; the verifier stops
# Lightning (ts_m_quarantine).
ts_m_failclose() {
    ts_m_killswitch_disarm
    local current_user current_uid=""
    current_user=$(ts_m_unit_prop "$TS_M_INV_UNIT" User) || current_user=""
    if [[ -n "$current_user" ]]; then
        current_uid=$(id -u "$current_user" 2>/dev/null || true)
    fi
    if [[ -n "$current_uid" ]] && [[ "$current_uid" != "$TS_M_INV_UID" ]]; then
        TS_M_ERROR="$1; the ${TS_M_INV_UNIT} user changed to uid ${current_uid}, so the emergency block for uid ${TS_M_INV_UID} does not cover it"
        return 1
    fi
    if ! ts_m_emergency_arm "$TS_M_INV_UID"; then
        TS_M_ERROR="$1; the emergency block could not be armed either"
        return 1
    fi
    if ! ts_m_emergency_effective "$TS_M_INV_UID"; then
        TS_M_ERROR="$1; the emergency block is armed but not in effect: ${TS_M_ERROR}"
        return 1
    fi
    ts_m_state_protected failclosed "$1; emergency block armed for uid ${TS_M_INV_UID}: Lightning clearnet traffic is blocked, Tor keeps working"
    return 0
}

# Arms (or re-arms) the kill switch for the inventory and, after a successful read-back, releases
# an emergency block left from an earlier failure. $1 = what triggered it (for the log).
ts_m_rearm() {
    local why="$1"
    if ! ts_m_killswitch_apply "$TS_M_INV_PROFILE" "$TS_M_INV_IMPL" "$TS_M_INV_UNIT" "$TS_M_INV_UID" "$TS_M_INV_BACKSTOP"; then
        return 1
    fi
    if ts_m_emergency_present "$TS_M_INV_UID"; then
        if ts_m_emergency_release "$TS_M_INV_UID"; then
            ts_m_log "emergency block released"
        else
            ts_m_log "kill switch armed, but an emergency rule (priority 21817-21819) could not be removed"
        fi
    elif ! ts_m_emergency_lan_release; then
        ts_m_log "kill switch armed, but a local network exemption (priority ${TS_M_EMERGENCY_LAN_PRIO}) could not be removed"
    fi
    if [[ -n "$why" ]]; then
        ts_m_log "$why; kill switch re-armed and verified"
    fi
    ts_m_state_protected armed "kill switch armed and verified (slice ${TS_M_SLICE}, table inet ${TS_M_NFT_TABLE})"
    return 0
}

# Prints the Lightning uid that the kill switch unit's ExecStart carries (--fallback-uid), nothing
# if there is none. Asks systemd for the loaded unit; when systemd does not answer, reads the unit
# file TunnelSats wrote, so the emergency block can still be armed. Returns 1 if neither can be read.
ts_m_fallback_uid() {
    local out="" re='argv\[\]=[^;]*[[:space:]]--fallback-uid[[:space:]]+([1-9][0-9]*)([[:space:]]|;|$)'
    local file_re='^ExecStart=[^[:space:]]+[[:space:]]+managed-arm[[:space:]]+--fallback-uid[[:space:]]+([1-9][0-9]*)[[:space:]]*$'
    if out=$(ts_m_unit_prop "$TS_M_KILLSWITCH_UNIT" ExecStart); then
        if [[ "$out" =~ $re ]]; then
            echo "${BASH_REMATCH[1]}"
        fi
        return 0
    fi
    if ! out=$(grep -m 1 -E '^ExecStart=' "${TS_FS_ROOT}${TS_M_UNIT_DIR}/${TS_M_KILLSWITCH_UNIT}" 2>/dev/null); then
        return 1
    fi
    if [[ "$out" =~ $file_re ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
    return 0
}

# managed-arm while the install record cannot be read ($1 = why): the kill switch cannot be armed
# without it, but the emergency block can, for the Lightning uid that the unit's ExecStart carries
# ($2, --fallback-uid). Exits 0 when that block is in effect, so Lightning starts with its internet
# clearnet traffic blocked (Tor and the local network keep working); exits 1 otherwise. Nothing is
# released while the record is unreadable.
ts_m_arm_damaged() {
    local why="$1" uid="$2"
    if [[ ! "$uid" =~ ^[1-9][0-9]*$ ]]; then
        ts_m_log "${why}; the kill switch cannot be armed and Lightning does not start"
        exit 1
    fi
    if ! ts_m_lock; then
        ts_m_log "cannot take ${TS_M_LOCK}; arming the emergency block without it"
    fi
    ts_m_killswitch_disarm
    if ! ts_m_emergency_arm "$uid"; then
        ts_m_log "install record unreadable (${why}); the emergency block for uid ${uid} could not be armed either; Lightning does not start"
        exit 1
    fi
    if ! ts_m_emergency_effective "$uid"; then
        ts_m_log "install record unreadable (${why}); the emergency block for uid ${uid} is armed but not in effect: ${TS_M_ERROR}; Lightning does not start"
        exit 1
    fi
    ts_m_log "install record unreadable (${why}); emergency block armed for uid ${uid}: Lightning starts with clearnet traffic blocked, Tor and the local network keep working"
    ts_m_resume_stopped
    exit 0
}

# managed-arm: ExecStart of tunnelsats-killswitch.service, which the Lightning unit requires. Exits 0
# when Lightning's clearnet traffic is either tunneled (kill switch armed, read back and attested) or
# blocked (emergency block in effect, ts_m_emergency_effective; attestation absent), so Lightning may
# start; the verifier keeps trying to re-arm and releases the block after a successful re-arm. With
# an unreadable install record it falls back to the emergency block for --fallback-uid
# (ts_m_arm_damaged). Exits 1 when neither protection is in place: Lightning does not start, and the
# journal says why on every attempt.
ts_m_cmd_arm() {
    if ! ts_m_inventory_read; then
        ts_m_arm_damaged "$TS_M_ERROR" "${TS_OPT_FALLBACK_UID:-}"
    fi
    if ! ts_m_lock; then
        ts_m_log "cannot take ${TS_M_LOCK}; the kill switch was not armed"
        if ts_m_failclose "kill switch lock unavailable"; then
            exit 0
        fi
        ts_m_log "${TS_M_ERROR}; Lightning does not start"
        exit 1
    fi
    if ts_m_rearm ""; then
        exit 0
    fi
    if ts_m_failclose "kill switch could not be armed: ${TS_M_ERROR}"; then
        exit 0
    fi
    ts_m_log "${TS_M_ERROR}; Lightning does not start"
    exit 1
}

# managed-disarm: ExecStop of tunnelsats-killswitch.service. Removes the attestation only.
ts_m_cmd_disarm() {
    if ts_m_lock; then
        ts_m_killswitch_disarm
    else
        rm -f "${TS_FS_ROOT}${TS_M_ATTEST}"
    fi
    exit 0
}

# managed-verify: run by tunnelsats-verifier.timer every 30 seconds. Checks the table, the policy
# rules, the blackholes, the slice id and the attestation; re-arms on drift; logs only changes.
# If re-arming fails, it removes the attestation and arms the emergency block. When neither holds
# (the block cannot be armed, or a rule of another tool routes around it), it stops Lightning
# (ts_m_quarantine) and starts it again once one of them holds.
# managed-verify while the install record cannot be read ($1 = why), for fallback uid $2: keeps the
# emergency block for that uid in place (arming what is missing), releases nothing, and logs the
# state once. If the block does not hold, it stops the Lightning units that carry the drop-in.
ts_m_verify_damaged() {
    local why="$1" uid="$2" units=()
    if ! ts_m_lock; then
        ts_m_log "cannot take ${TS_M_LOCK}; check skipped"
        exit 1
    fi
    ts_m_killswitch_disarm
    mapfile -t units < <(ts_m_dropin_units)
    if ! ts_m_emergency_arm "$uid"; then
        ts_m_quarantine "install record unreadable (${why}); the emergency block for uid ${uid} could not be armed" "${units[@]}" || true
        exit 1
    fi
    if ! ts_m_emergency_effective "$uid"; then
        ts_m_quarantine "install record unreadable (${why}); the emergency block for uid ${uid} is armed but not in effect: ${TS_M_ERROR}" "${units[@]}" || true
        exit 1
    fi
    ts_m_state_protected damaged "install record unreadable (${why}); emergency block active for uid ${uid}"
    exit 0
}

ts_m_cmd_verifier() {
    local drift=() cur="" why="" fallback="" frc=0 units=()
    if ! ts_m_inventory_read; then
        why="$TS_M_ERROR"
        fallback=$(ts_m_fallback_uid) || frc=$?
        if [[ "$frc" -ne 0 ]]; then
            why="${why}; the Lightning uid cannot be read (systemd does not answer and ${TS_M_UNIT_DIR}/${TS_M_KILLSWITCH_UNIT} cannot be read)"
        elif [[ -z "$fallback" ]]; then
            why="${why}; the kill switch unit carries no Lightning uid (--fallback-uid)"
        fi
        if [[ "$frc" -ne 0 ]] || [[ -z "$fallback" ]]; then
            if ! ts_m_lock; then
                ts_m_log "cannot take ${TS_M_LOCK}; check skipped"
                exit 1
            fi
            mapfile -t units < <(ts_m_dropin_units)
            ts_m_quarantine "${why}, so no emergency block can be armed" "${units[@]}" || true
            exit 1
        fi
        ts_m_verify_damaged "$why" "$fallback"
    fi
    if ! ts_m_lock; then
        ts_m_log "cannot take ${TS_M_LOCK}; check skipped"
        exit 1
    fi
    if ts_m_ensure_run_dir && ts_m_render_ruleset > "${TS_FS_ROOT}${TS_M_RULESET_FILE}"; then
        ts_m_kernel_readback "${TS_FS_ROOT}${TS_M_RULESET_FILE}" "$TS_M_INV_BACKSTOP" "$TS_M_INV_UID"
        drift=("${TS_M_DRIFT[@]}")
    else
        drift=("cannot write ${TS_M_RULESET_FILE}")
    fi
    ts_m_read_attestation
    if [[ "$TS_M_ATT_STATUS" != "valid" ]]; then
        drift+=("attestation ${TS_M_ATT_STATUS//_/ }")
    else
        cur=$(ts_m_slice_cgroup_id) || cur=""
        if [[ "$cur" != "$TS_M_ATT_SLICE_ID" ]]; then
            drift+=("slice id changed from ${TS_M_ATT_SLICE_ID} to ${cur:-none}")
        fi
    fi
    if [[ ${#drift[@]} -eq 0 ]] && ! ts_m_emergency_present "$TS_M_INV_UID"; then
        ts_m_state_protected armed "kill switch armed and verified (slice ${TS_M_SLICE}, table inet ${TS_M_NFT_TABLE})"
        exit 0
    fi
    if [[ ${#drift[@]} -eq 0 ]]; then
        drift=("emergency block present")
    fi
    if ts_m_rearm "drift detected (${drift[*]})"; then
        exit 0
    fi
    if ts_m_failclose "drift detected (${drift[*]}) and re-arming failed: ${TS_M_ERROR}"; then
        exit 0
    fi
    ts_m_quarantine "$TS_M_ERROR" "$TS_M_INV_UNIT" || true
    exit 1
}

# managed-mynode-lnd-pre: ExecStartPre=+ of the Lightning unit on the mynode profile.
# MyNode regenerates /mnt/hdd/mynode/lnd/lnd.conf from /mnt/hdd/mynode/settings/lnd_custom.conf
# and /mnt/hdd/mynode/settings/lnd_extra_config.conf when starting LND. Verifies the managed
# inventory and tunnel config, checks the MyNode custom/extra LND configs, and reconciles
# /mnt/hdd/mynode/lnd/lnd.conf before LND starts if any configured TunnelSats hybrid settings
# are missing. Fails closed (exits 1) if the inventory, tunnel config or lnd.conf cannot be
# read or updated when expected.
ts_m_cmd_mynode_lnd_pre() {
    local inv_file="${TS_FS_ROOT}${TS_M_INVENTORY}"
    local wg_conf="${TS_FS_ROOT}${TS_M_WG_CONF}"
    local custom_conf="${TS_FS_ROOT}/mnt/hdd/mynode/settings/lnd_custom.conf"
    local extra_conf="${TS_FS_ROOT}/mnt/hdd/mynode/settings/lnd_extra_config.conf"
    local lnd_conf="${TS_FS_ROOT}/mnt/hdd/mynode/lnd/lnd.conf"
    local src entry key val w c found vpn_dns="" vpn_port=""
    local -a want_listens=() want_exthosts=() cur_listens=() cur_exthosts=() add_listens=() add_exthosts=()
    local want_streamiso="" want_skipproxy="" has_hybrid=0
    local cur_streamiso="" cur_skipproxy=""
    local listen_port="9735" want_ipv4_wild=0 want_ipv6_wild=0
    local conflict_listen=0 dup_listen=0 dup_exthost=0 fix_listen=0 fix_exthosts=0
    local add_streamiso="" add_skipproxy=""
    local add_listens_nl="" want_listens_nl="" add_exthosts_nl=""
    local tmp mode="" owner=""

    if [[ -L "$inv_file" ]]; then
        ts_m_log "managed-mynode-lnd-pre: ${TS_M_INVENTORY} is a symlink"
        exit 1
    fi
    if ! ts_m_inventory_read; then
        ts_m_log "managed-mynode-lnd-pre: install record unreadable (${TS_M_ERROR})"
        exit 1
    fi
    if [[ "$TS_M_INV_PROFILE" != "mynode" ]]; then
        ts_m_log "managed-mynode-lnd-pre: profile is ${TS_M_INV_PROFILE:-unknown} (expected mynode)"
        exit 1
    fi
    if [[ -L "$wg_conf" ]] || [[ ! -f "$wg_conf" ]] || [[ ! -r "$wg_conf" ]]; then
        ts_m_log "managed-mynode-lnd-pre: ${TS_M_WG_CONF} cannot be read"
        exit 1
    fi
    vpn_dns=$(sed -nE 's/^[[:space:]]*Endpoint[[:space:]]*=[[:space:]]*([^:[:space:]]+):.*/\1/Ip' "$wg_conf" | head -n 1)
    vpn_port=$(ts_config_vpn_port "$wg_conf")

    for src in "$custom_conf" "$extra_conf"; do
        if [[ -L "$src" ]]; then
            ts_m_log "managed-mynode-lnd-pre: ${src#"$TS_FS_ROOT"} is a symlink"
            exit 1
        fi
        if [[ -e "$src" ]] && { [[ ! -f "$src" ]] || [[ ! -r "$src" ]]; }; then
            ts_m_log "managed-mynode-lnd-pre: ${src#"$TS_FS_ROOT"} cannot be read"
            exit 1
        fi
        if [[ -f "$src" ]]; then
            while IFS= read -r entry; do
                entry="${entry#*|}"
                key="${entry%%|*}"
                val="${entry#*|}"
                case "$key" in
                    listen)
                        if [[ "$val" =~ :9735$ ]]; then
                            found=0
                            for w in "${want_listens[@]}"; do
                                [[ "${w,,}" == "${val,,}" ]] && { found=1; break; }
                            done
                            [[ "$found" -eq 0 ]] && want_listens+=("$val")
                        fi
                        ;;
                    externalhosts)
                        if [[ -n "$val" ]]; then
                            has_hybrid=1
                            found=0
                            for w in "${want_exthosts[@]}"; do
                                [[ "${w,,}" == "${val,,}" ]] && { found=1; break; }
                            done
                            [[ "$found" -eq 0 ]] && want_exthosts+=("$val")
                        fi
                        ;;
                    tor.streamisolation)
                        case "${val,,}" in
                            false|0) want_streamiso="$val" ;;
                        esac
                        ;;
                    tor.skip-proxy-for-clearnet-targets)
                        case "${val,,}" in
                            ""|true|1)
                                want_skipproxy="${val:-true}"
                                has_hybrid=1
                                ;;
                        esac
                        ;;
                esac
            done < <(ts_m_config_settings "$src")
        fi
    done

    if [[ "$TS_M_INV_IMPL" == "lnd" ]] || [[ "$has_hybrid" -eq 1 ]] || [[ -e "$lnd_conf" ]] || [[ -L "$lnd_conf" ]]; then
        if [[ -L "$lnd_conf" ]] || [[ ! -f "$lnd_conf" ]] || [[ ! -r "$lnd_conf" ]]; then
            ts_m_log "managed-mynode-lnd-pre: /mnt/hdd/mynode/lnd/lnd.conf cannot be read"
            exit 1
        fi
    fi

    if [[ "$has_hybrid" -ne 1 ]]; then
        exit 0
    fi

    if [[ ${#want_listens[@]} -eq 0 ]]; then
        want_listens=("0.0.0.0:9735")
    fi
    listen_port="${want_listens[0]##*:}"
    [[ "$listen_port" =~ ^[0-9]+$ ]] || listen_port="9735"
    for w in "${want_listens[@]}"; do
        case "${w,,}" in
            "0.0.0.0:${listen_port}"|":${listen_port}"|"${listen_port}") want_ipv4_wild=1 ;;
            "[::]:${listen_port}") want_ipv6_wild=1 ;;
        esac
    done
    if [[ ${#want_exthosts[@]} -eq 0 ]] && [[ -n "$vpn_dns" ]] && [[ -n "$vpn_port" ]]; then
        want_exthosts=("${vpn_dns}:${vpn_port}")
    fi
    [[ -z "$want_streamiso" ]] && want_streamiso="false"
    [[ -z "$want_skipproxy" ]] && want_skipproxy="true"

    while IFS= read -r entry; do
        entry="${entry#*|}"
        key="${entry%%|*}"
        val="${entry#*|}"
        case "$key" in
            listen)
                found=0
                for c in "${cur_listens[@]}"; do
                    [[ "${c,,}" == "${val,,}" ]] && { found=1; break; }
                done
                if [[ "$found" -eq 1 ]]; then
                    dup_listen=1
                else
                    cur_listens+=("$val")
                fi
                found=0
                for w in "${want_listens[@]}"; do
                    [[ "${w,,}" == "${val,,}" ]] && { found=1; break; }
                done
                if [[ "$found" -eq 0 ]]; then
                    case "${val,,}" in
                        localhost|"localhost:${listen_port}"|127.0.0.1|"127.0.0.1:${listen_port}"|"[::1]"|"[::1]:${listen_port}")
                            conflict_listen=1
                            ;;
                        *)
                            if [[ "$want_ipv4_wild" -eq 1 ]] && [[ "$val" != \[* ]] && [[ "$val" == *":${listen_port}" || "$val" == "${listen_port}" ]]; then
                                conflict_listen=1
                            elif [[ "$want_ipv6_wild" -eq 1 ]] && [[ "${val,,}" == \[*\]:"${listen_port}" ]]; then
                                conflict_listen=1
                            fi
                            ;;
                    esac
                fi
                ;;
            externalhosts)
                found=0
                for c in "${cur_exthosts[@]}"; do
                    [[ "${c,,}" == "${val,,}" ]] && { found=1; break; }
                done
                if [[ "$found" -eq 1 ]]; then
                    dup_exthost=1
                else
                    cur_exthosts+=("$val")
                fi
                ;;
            tor.streamisolation)
                case "${val,,}" in
                    false|0) cur_streamiso="$val" ;;
                    *) cur_streamiso="" ;;
                esac
                ;;
            tor.skip-proxy-for-clearnet-targets)
                case "${val,,}" in
                    ""|true|1) cur_skipproxy="${val:-true}" ;;
                    *) cur_skipproxy="" ;;
                esac
                ;;
        esac
    done < <(ts_m_config_settings "$lnd_conf")

    for w in "${want_listens[@]}"; do
        found=0
        for c in "${cur_listens[@]}"; do
            [[ "${c,,}" == "${w,,}" ]] && { found=1; break; }
        done
        [[ "$found" -eq 0 ]] && add_listens+=("$w")
    done
    if [[ ${#add_listens[@]} -gt 0 || "$conflict_listen" -eq 1 || "$dup_listen" -eq 1 ]]; then
        fix_listen=1
    fi

    for w in "${want_exthosts[@]}"; do
        found=0
        for c in "${cur_exthosts[@]}"; do
            [[ "${c,,}" == "${w,,}" ]] && { found=1; break; }
        done
        [[ "$found" -eq 0 ]] && add_exthosts+=("$w")
    done
    if [[ ${#add_exthosts[@]} -gt 0 || "$dup_exthost" -eq 1 ]]; then
        fix_exthosts=1
    fi

    [[ -z "$cur_streamiso" ]] && add_streamiso="$want_streamiso"
    [[ -z "$cur_skipproxy" ]] && add_skipproxy="$want_skipproxy"

    if [[ "$fix_listen" -eq 0 && "$fix_exthosts" -eq 0 && -z "$add_streamiso" && -z "$add_skipproxy" ]]; then
        exit 0
    fi

    if [[ ${#add_listens[@]} -gt 0 ]]; then
        add_listens_nl=$(printf '%s\n' "${add_listens[@]}")
    fi
    if [[ ${#want_listens[@]} -gt 0 ]]; then
        want_listens_nl=$(printf '%s\n' "${want_listens[@]}")
    fi
    if [[ ${#add_exthosts[@]} -gt 0 ]]; then
        add_exthosts_nl=$(printf '%s\n' "${add_exthosts[@]}")
    fi

    mode=$(stat -c '%a' "$lnd_conf" 2>/dev/null || echo "640")
    owner=$(stat -c '%u:%g' "$lnd_conf" 2>/dev/null || echo "")
    local stage_dir="/run/tunnelsats"
    if [[ "$EUID" -ne 0 ]] || ! install -d -m 0755 "$stage_dir" 2>/dev/null; then
        stage_dir="${TMPDIR:-/tmp}"
    fi
    if ! stage_tmp=$(mktemp "${stage_dir}/mynode-lnd-conf.XXXXXX" 2>/dev/null); then
        ts_m_log "managed-mynode-lnd-pre: failed to allocate staging file"
        exit 1
    fi
    if ! awk \
        -v fix_listen="$fix_listen" \
        -v add_listens_nl="$add_listens_nl" \
        -v want_listens_nl="$want_listens_nl" \
        -v listen_port="$listen_port" \
        -v want_ipv4_wild="$want_ipv4_wild" \
        -v want_ipv6_wild="$want_ipv6_wild" \
        -v fix_exthosts="$fix_exthosts" \
        -v add_exthosts_nl="$add_exthosts_nl" \
        -v add_streamiso="$add_streamiso" \
        -v add_skipproxy="$add_skipproxy" '
        BEGIN {
            app_done = 0
            tor_done = 0
            n_add_l = split(add_listens_nl, add_l, "\n")
            for (i = 1; i <= n_add_l; i++) {
                if (add_l[i] != "") seen_listen[tolower(add_l[i])] = 1
            }
            n_want_l = split(want_listens_nl, want_l, "\n")
            for (i = 1; i <= n_want_l; i++) {
                if (want_l[i] != "") is_want_listen[tolower(want_l[i])] = 1
            }
            n_add_e = split(add_exthosts_nl, add_e, "\n")
            for (i = 1; i <= n_add_e; i++) {
                if (add_e[i] != "") seen_exthost[tolower(add_e[i])] = 1
            }
        }
        {
            trimmed = $0
            sub(/\r$/, "", trimmed)
            sub(/^[[:space:]]+/, "", trimmed)
            sub(/[[:space:]]+$/, "", trimmed)
            low = tolower(trimmed)
            if (low == "[application options]" && !app_done) {
                print $0
                for (i = 1; i <= n_add_l; i++) {
                    if (add_l[i] != "") print "listen=" add_l[i]
                }
                for (i = 1; i <= n_add_e; i++) {
                    if (add_e[i] != "") print "externalhosts=" add_e[i]
                }
                app_done = 1
                next
            }
            if (low == "[tor]" && !tor_done) {
                print $0
                if (add_streamiso != "") print "tor.streamisolation=" add_streamiso
                if (add_skipproxy != "") print "tor.skip-proxy-for-clearnet-targets=" add_skipproxy
                tor_done = 1
                next
            }
            if (fix_listen && low ~ /^listen[[:space:]]*=/) {
                v = trimmed
                sub(/^[^=]*=[[:space:]]*/, "", v)
                lv = tolower(v)
                if (seen_listen[lv]) next
                if (!is_want_listen[lv]) {
                    if (lv == "localhost" || lv == ("localhost:" listen_port) ||
                        lv == "127.0.0.1" || lv == ("127.0.0.1:" listen_port) ||
                        lv == "[::1]" || lv == ("[::1]:" listen_port)) next
                    if (want_ipv4_wild && substr(lv, 1, 1) != "[" &&
                        (lv == listen_port || lv ~ (":" listen_port "$"))) next
                    if (want_ipv6_wild && substr(lv, 1, 1) == "[" &&
                        lv ~ ("\\]:" listen_port "$")) next
                }
                seen_listen[lv] = 1
                print $0
                next
            }
            if (fix_exthosts && low ~ /^externalhosts[[:space:]]*=/) {
                v = trimmed
                sub(/^[^=]*=[[:space:]]*/, "", v)
                lv = tolower(v)
                if (seen_exthost[lv]) next
                seen_exthost[lv] = 1
                print $0
                next
            }
            if (add_streamiso != "" && low ~ /^tor\.streamisolation[[:space:]]*=/) next
            if (add_skipproxy != "" && low ~ /^tor\.skip-proxy-for-clearnet-targets([[:space:]]*=|$)/) next
            print $0
        }
        END {
            if (!app_done && (n_add_l > 0 || n_add_e > 0)) {
                has_app_adds = 0
                for (i = 1; i <= n_add_l; i++) if (add_l[i] != "") has_app_adds = 1
                for (i = 1; i <= n_add_e; i++) if (add_e[i] != "") has_app_adds = 1
                if (has_app_adds) {
                    print ""
                    print "[Application Options]"
                    for (i = 1; i <= n_add_l; i++) {
                        if (add_l[i] != "") print "listen=" add_l[i]
                    }
                    for (i = 1; i <= n_add_e; i++) {
                        if (add_e[i] != "") print "externalhosts=" add_e[i]
                    }
                }
            }
            if (!tor_done && (add_streamiso != "" || add_skipproxy != "")) {
                print ""
                print "[Tor]"
                if (add_streamiso != "") print "tor.streamisolation=" add_streamiso
                if (add_skipproxy != "") print "tor.skip-proxy-for-clearnet-targets=" add_skipproxy
            }
        }' "$lnd_conf" > "$stage_tmp" 2>/dev/null; then
        rm -f "$stage_tmp" 2>/dev/null || true
        ts_m_log "managed-mynode-lnd-pre: failed to stage reconciled /mnt/hdd/mynode/lnd/lnd.conf"
        exit 1
    fi
    if [[ "$EUID" -eq 0 ]] && id -u bitcoin >/dev/null 2>&1 && command -v runuser >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
        if ! runuser -u bitcoin -g bitcoin -- python3 - "$lnd_conf" "$mode" 3< "$stage_tmp" <<'PY' 2>/dev/null
import os, secrets, sys
target, mode_s = sys.argv[1:3]
if os.path.islink(target):
    sys.exit(1)
with os.fdopen(3, "rb") as f_in:
    data = f_in.read()
try:
    mode = int(mode_s, 8)
except ValueError:
    mode = 0o640
tmp = f"{target}.tunnelsats.tmp.{os.getpid()}.{secrets.token_hex(6)}"
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
        then
            rm -f "$stage_tmp" 2>/dev/null || true
            ts_m_log "managed-mynode-lnd-pre: failed to update /mnt/hdd/mynode/lnd/lnd.conf as bitcoin"
            exit 1
        fi
        rm -f "$stage_tmp" 2>/dev/null || true
    else
        if [[ -L "$lnd_conf" ]]; then
            rm -f "$stage_tmp" 2>/dev/null || true
            ts_m_log "managed-mynode-lnd-pre: refusing symlinked /mnt/hdd/mynode/lnd/lnd.conf"
            exit 1
        fi
        if ! tmp=$(mktemp "${lnd_conf}.tunnelsats.tmp.XXXXXX" 2>/dev/null); then
            rm -f "$stage_tmp" 2>/dev/null || true
            ts_m_log "managed-mynode-lnd-pre: failed to create temp file for /mnt/hdd/mynode/lnd/lnd.conf"
            exit 1
        fi
        if ! cp "$stage_tmp" "$tmp" 2>/dev/null; then
            rm -f "$stage_tmp" "$tmp" 2>/dev/null || true
            exit 1
        fi
        rm -f "$stage_tmp" 2>/dev/null || true
        chmod "$mode" "$tmp" 2>/dev/null || chmod 0640 "$tmp" 2>/dev/null || true
        if [[ -n "$owner" ]] && [[ "$EUID" -eq 0 ]]; then
            chown -h "$owner" "$tmp" 2>/dev/null || chown -h "${TS_M_INV_USER}:bitcoin" "$tmp" 2>/dev/null || true
        fi
        if ! mv -f "$tmp" "$lnd_conf" 2>/dev/null; then
            rm -f "$tmp" 2>/dev/null || true
            ts_m_log "managed-mynode-lnd-pre: failed to update /mnt/hdd/mynode/lnd/lnd.conf"
            exit 1
        fi
    fi

    cur_listens=()
    cur_exthosts=()
    cur_skipproxy=""
    while IFS= read -r entry; do
        entry="${entry#*|}"
        key="${entry%%|*}"
        val="${entry#*|}"
        case "$key" in
            listen)
                cur_listens+=("$val")
                ;;
            externalhosts)
                cur_exthosts+=("$val")
                ;;
            tor.skip-proxy-for-clearnet-targets)
                case "${val,,}" in
                    ""|true|1) cur_skipproxy="${val:-true}" ;;
                esac
                ;;
        esac
    done < <(ts_m_config_settings "$lnd_conf")
    for w in "${want_listens[@]}"; do
        found=0
        for c in "${cur_listens[@]}"; do
            [[ "${c,,}" == "${w,,}" ]] && { found=1; break; }
        done
        if [[ "$found" -eq 0 ]]; then
            ts_m_log "managed-mynode-lnd-pre: read-back verification of /mnt/hdd/mynode/lnd/lnd.conf failed"
            exit 1
        fi
    done
    for w in "${want_exthosts[@]}"; do
        found=0
        for c in "${cur_exthosts[@]}"; do
            [[ "${c,,}" == "${w,,}" ]] && { found=1; break; }
        done
        if [[ "$found" -eq 0 ]]; then
            ts_m_log "managed-mynode-lnd-pre: read-back verification of /mnt/hdd/mynode/lnd/lnd.conf failed"
            exit 1
        fi
    done
    if [[ -z "$cur_skipproxy" ]]; then
        ts_m_log "managed-mynode-lnd-pre: read-back verification of /mnt/hdd/mynode/lnd/lnd.conf failed"
        exit 1
    fi
    ts_m_log "reconciled /mnt/hdd/mynode/lnd/lnd.conf with TunnelSats hybrid settings before ${TS_M_INV_UNIT} start"
    exit 0
}

# Prints the address an echo service returns for curl arguments "$@" (the URL last); nothing if
# there is no answer or the answer is not an IP address.
ts_m_probe_fetch() {
    local out=""
    out=$("$CURL_BIN" -s --connect-timeout 4 --max-time 6 "$@" 2>/dev/null) || return 0
    out="${out//[[:space:]]/}"
    if valid_ipv4 "$out" || [[ "$out" =~ ^[0-9A-Fa-f]{0,4}(:[0-9A-Fa-f]{0,4}){2,7}$ ]]; then
        echo "$out"
    fi
    return 0
}

# The perl helper of ts_m_probe_send (perl-base is part of every Debian and Ubuntu system). Sends
# one UDP datagram to address ARGV[1] (family ARGV[0], 4 or 6), port 9 (discard), the socket bound
# to interface ARGV[2] unless "-", and prints one word: "sent", the errno name of an immediate
# failure (perl's Errno names do not depend on the locale or the architecture) or "error:<stage>".
TS_M_PROBE_PERL='
use strict; use warnings;
use Socket qw(AF_INET AF_INET6 SOCK_DGRAM SOL_SOCKET inet_pton pack_sockaddr_in pack_sockaddr_in6);
use Errno ();
my ($fam, $ip, $dev) = @ARGV;
sub errname {
    for my $n (qw(EPERM EACCES EINVAL ENETUNREACH EHOSTUNREACH)) { return $n if $!{$n} }
    for my $n (sort keys %!) { return $n if $!{$n} }
    return "error:errno-" . ($! + 0);
}
my $af = $fam eq "6" ? AF_INET6 : AF_INET;
my $addr = inet_pton($af, $ip);
if (!defined $addr) { print "error:address\n"; exit 0 }
socket(my $s, $af, SOCK_DGRAM, 0) or do { print "error:socket-", lc(errname()), "\n"; exit 0 };
if ($dev ne "-") {
    my $opt = eval { Socket::SO_BINDTODEVICE() } // 25;
    setsockopt($s, SOL_SOCKET, $opt, pack("Z*", $dev)) or do { print "error:bind-", lc(errname()), "\n"; exit 0 };
}
my $sa = $fam eq "6" ? pack_sockaddr_in6(9, $addr) : pack_sockaddr_in(9, $addr);
if (defined send($s, "tunnelsats-verify", 0, $sa)) { print "sent\n" } else { print errname(), "\n" }
'

# Sends one UDP datagram from this process to address $2 (IP family $1), port 9, bound to interface
# $3 unless "-" (see TS_M_PROBE_PERL). Prints "sent", an errno name such as EPERM, or
# "error:<reason>" when the helper cannot run.
ts_m_probe_send() {
    local fam="$1" ip="$2" iface="$3" out=""
    if ! command -v "$PERL_BIN" >/dev/null 2>&1; then
        echo "error:no-perl"
        return 0
    fi
    out=$("$PERL_BIN" -e "$TS_M_PROBE_PERL" "$fam" "$ip" "$iface" 2>/dev/null) || out=""
    if [[ "$out" =~ ^(sent|E[A-Z0-9]+|error:[a-z0-9-]+)$ ]]; then
        echo "$out"
    else
        echo "error:helper"
    fi
}

# Classifies a result word of ts_m_probe_send. "blocked": an immediate local error, the datagram
# never left the host (EPERM from an nft drop such as the kill chain or the IPv6 drop; EINVAL,
# EHOSTUNREACH or EACCES from a blackhole, unreachable or prohibit route or rule; ENETUNREACH: no
# route). "left": the datagram was sent. "error": anything else, the probe cannot tell.
ts_m_probe_classify() {
    case "$1" in
        sent) echo "left" ;;
        EPERM|EINVAL|ENETUNREACH|EHOSTUNREACH|EACCES) echo "blocked" ;;
        *) echo "error" ;;
    esac
}

# managed-probe <mode> ...: runs inside a transient unit of the slice, started by verify. The first
# line names the cgroup the probe runs in, so verify can confirm it ran inside the slice.
#   egress4 URL...           "answer <url> <address|->" for each URL (IPv4 echo services, curl)
#   send 4|6 IFACE|- IP      "send <ip> <word>" (see ts_m_probe_send): one UDP datagram to IP port 9,
#                            the socket bound to IFACE unless "-"
ts_m_cmd_probe() {
    local mode="${1:-}" url cg="" fam iface ip
    if [[ -w "${TS_FS_ROOT:-}/sys/fs/cgroup/net_cls/splitted_processes/tasks" ]]; then
        echo "$$" > "${TS_FS_ROOT:-}/sys/fs/cgroup/net_cls/splitted_processes/tasks" 2>/dev/null || true
    fi
    cg=$(sed -n 's/^0:://p' /proc/self/cgroup 2>/dev/null | head -n 1) || cg=""
    echo "cgroup ${cg:-unknown}"
    case "$mode" in
        egress4)
            if ! command -v "$CURL_BIN" >/dev/null 2>&1; then
                echo "error ${CURL_BIN} not found"
                exit 0
            fi
            shift
            for url in "$@"; do
                echo "answer ${url} $(ts_m_probe_fetch -4 "$url" | head -n 1 | grep . || echo -)"
            done
            ;;
        send)
            fam="${2:-}"
            iface="${3:-}"
            ip="${4:-}"
            if [[ "$fam" != "4" ]] && [[ "$fam" != "6" ]] || [[ -z "$iface" ]] || [[ -z "$ip" ]]; then
                echo "usage: managed-probe send 4|6 IFACE|- IP" >&2
                exit 2
            fi
            echo "send ${ip} $(ts_m_probe_send "$fam" "$ip" "$iface")"
            ;;
        *)
            echo "usage: managed-probe egress4 URL... | send 4|6 IFACE|- IP" >&2
            exit 2
            ;;
    esac
    exit 0
}

# Reads the attestation into TS_M_ATT_STATUS (valid, missing, invalid, other_boot, not_armed,
# not_root_owned), TS_M_ATT_SLICE_ID and TS_M_ATT_BACKSTOP.
ts_m_read_attestation() {
    local f="${TS_FS_ROOT}${TS_M_ATTEST}" doc="" owner="" boot=""
    TS_M_ATT_STATUS="missing"
    TS_M_ATT_SLICE_ID=""
    TS_M_ATT_BACKSTOP=""
    if [[ ! -f "$f" ]]; then
        return 0
    fi
    owner=$(stat -c %u "$f" 2>/dev/null) || owner=""
    if [[ "$owner" != "$(ts_m_expected_owner)" ]]; then
        TS_M_ATT_STATUS="not_root_owned"
        return 0
    fi
    doc=$(head -c 4096 "$f" 2>/dev/null) || doc=""
    boot=$(ts_m_boot_id) || boot=""
    if [[ ! "$doc" =~ \"schema\":1[,}] ]] || [[ ! "$doc" =~ \"slice_cgroup_id\":([0-9]+)[,}] ]]; then
        TS_M_ATT_STATUS="invalid"
        return 0
    fi
    TS_M_ATT_SLICE_ID="${BASH_REMATCH[1]}"
    if [[ "$doc" =~ \"uid_backstop\":(true|false)[,}] ]]; then
        TS_M_ATT_BACKSTOP="${BASH_REMATCH[1]}"
    fi
    if [[ -z "$boot" ]] || [[ "$doc" != *"\"boot_id\":\"${boot}\""* ]]; then
        TS_M_ATT_STATUS="other_boot"
    elif [[ "$doc" != *'"armed":true'* ]]; then
        TS_M_ATT_STATUS="not_armed"
    else
        TS_M_ATT_STATUS="valid"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Managed mode: Lightning unit and node config (read-only helpers)
# ---------------------------------------------------------------------------

# Prints property $2 of unit $1 ("systemctl show --value"); empty if systemd cannot tell.
ts_m_unit_prop() {
    "$SYSTEMCTL_BIN" show -p "$2" --value "$1" 2>/dev/null
}

# Reads the command line of the single ExecStart of unit $1 ("systemctl show": "{ path=... ;
# argv[]=<arguments> ; ignore_errors=... }") into TS_M_EXEC_ARGV, one argument per element, and the
# argv[] text into TS_M_EXEC_RAW. Fails if there is no ExecStart, more than one, or the field cannot
# be found.
ts_m_execstart_tokens() {
    local raw marker='argv[]=' rest
    TS_M_EXEC_ARGV=()
    TS_M_EXEC_RAW=""
    raw=$(ts_m_unit_prop "$1" ExecStart)
    if [[ "$raw" != *"$marker"* ]]; then
        return 1
    fi
    rest="${raw#*"$marker"}"
    if [[ "$rest" == *"$marker"* ]] || [[ "$rest" != *" ; ignore_errors="* ]]; then
        return 1
    fi
    rest="${rest%% ; ignore_errors=*}"
    TS_M_EXEC_RAW="$rest"
    read -r -a TS_M_EXEC_ARGV <<< "$rest"
    if [[ ${#TS_M_EXEC_ARGV[@]} -eq 0 ]]; then
        return 1
    fi
    return 0
}

# RaspiBlitz starts CLN through a shell, so that it can pipe the password of an encrypted
# hsm_secret into lightningd (cl.install-service.sh):
#   /bin/sh -c '[(cat <file>;echo;cat <file>) | ]/usr/local/bin/lightningd --conf=<config> [--encrypted-hsm] --rpc-file-mode 0660'
# If TS_M_EXEC_ARGV has exactly this shape, the command line holds no control character and every
# word from lightningd on is a plain word (no quote, variable, glob, redirection or other shell
# syntax), the shell runs lightningd with exactly these words: replaces TS_M_EXEC_ARGV with them and
# succeeds. Fails and leaves TS_M_EXEC_ARGV unchanged for anything else.
ts_m_raspiblitz_cln_argv() {
    local i=2 w n="${#TS_M_EXEC_ARGV[@]}" f=""
    if [[ "$TS_M_EXEC_RAW" == *[[:cntrl:]]* ]] || [[ "$n" -lt 3 ]]; then
        return 1
    fi
    if [[ "${TS_M_EXEC_ARGV[0]}" != "/bin/sh" ]] || [[ "${TS_M_EXEC_ARGV[1]}" != "-c" ]]; then
        return 1
    fi
    # The password pipe: "(cat <file>;echo;cat <file>) |", with the same plain path twice
    if [[ "${TS_M_EXEC_ARGV[2]}" == "(cat" ]]; then
        f="${TS_M_EXEC_ARGV[3]:-}"
        f="${f%;echo;cat}"
        if [[ ! "$f" =~ ^/[A-Za-z0-9_./-]+$ ]] || [[ "${TS_M_EXEC_ARGV[3]:-}" != "${f};echo;cat" ]] || \
            [[ "${TS_M_EXEC_ARGV[4]:-}" != "${f})" ]] || [[ "${TS_M_EXEC_ARGV[5]:-}" != "|" ]]; then
            return 1
        fi
        i=6
    fi
    if [[ "${TS_M_EXEC_ARGV[$i]:-}" != "/usr/local/bin/lightningd" ]]; then
        return 1
    fi
    for (( w = i; w < n; w++ )); do
        if [[ ! "${TS_M_EXEC_ARGV[$w]}" =~ ^[A-Za-z0-9_./:=@,+-]+$ ]]; then
            return 1
        fi
    done
    TS_M_EXEC_ARGV=("${TS_M_EXEC_ARGV[@]:$i}")
    return 0
}

# RaspiBlitz's TunnelSats start guard (the RaspiBlitz integration) for unit $1: TS_M_RB_IMPL and
# TS_M_RB_CHAIN (as its guard line names them: lnd or cl, and the chain), TS_M_RB_VAR (the variable
# that carries the clearnet flags of a start), TS_M_RB_WORD (its word on the command line) and
# TS_M_RB_ENVFILE (the file the guard writes it to). Fails for any other unit.
ts_m_raspiblitz_guard_ctx() {
    local impl net
    TS_M_RB_IMPL=""
    TS_M_RB_CHAIN=""
    TS_M_RB_VAR=""
    TS_M_RB_WORD=""
    TS_M_RB_ENVFILE=""
    for impl in lnd cln; do
        for net in $TS_NETWORKS; do
            if [[ "$(ts_m_raspiblitz_unit "$impl" "$net")" != "$1" ]]; then
                continue
            fi
            TS_M_RB_CHAIN="$net"
            if [[ "$impl" == "lnd" ]]; then
                TS_M_RB_IMPL="lnd"
                TS_M_RB_VAR="TUNNELSATS_LND_ARGS"
                TS_M_RB_WORD="\$TUNNELSATS_LND_ARGS"
            else
                # Inside RaspiBlitz's sh -c string: systemd turns $$ into the $ the shell expands
                TS_M_RB_IMPL="cl"
                TS_M_RB_VAR="TUNNELSATS_CLN_ARGS"
                TS_M_RB_WORD="\$\$TUNNELSATS_CLN_ARGS"
            fi
            TS_M_RB_ENVFILE="${TS_M_RUN_DIR}/hybrid-${1%.service}.env"
            return 0
        done
    done
    return 1
}

# RaspiBlitz's TunnelSats start guard passes the clearnet flags of each start through one variable,
# the last word of the Lightning command line:
#   LND: ExecStart=/usr/local/bin/lnd --configfile=<config> $TUNNELSATS_LND_ARGS
#   CLN: ExecStart=/bin/sh -c '<RaspiBlitz's command, ts_m_raspiblitz_cln_argv> $$TUNNELSATS_CLN_ARGS'
# Before every start, its guard line (ExecStartPre=+) writes "<VAR>=<flags>" to the env file, or
# "<VAR>=" (Tor-only) unless verify vouches for the managed dataplane, and also when the guard script
# is missing; Environment=<VAR>= is the default. Succeeds if unit $1 (TS_M_EXEC_ARGV ends with
# TS_M_RB_WORD, see ts_m_raspiblitz_guard_ctx) carries exactly this form, and removes the variable
# word from TS_M_EXEC_ARGV and TS_M_EXEC_RAW: systemd loaded the unit file as it is (no daemon-reload
# pending), no drop-in but the managed one applies, and the [Service] section holds the Environment=
# line (no empty Environment= clears it later), the env file as the last EnvironmentFile=, the guard
# line as the last ExecStartPre= (nothing runs after it, no empty ExecStartPre= clears it) and the
# ExecStart systemd shows, each exactly once; no other line names the variable and none continues on
# the next. Lines count as systemd reads them: comments, and whitespace around a line and around "=",
# do not count. Fails with TS_M_RB_WHY and changes nothing otherwise.
ts_m_raspiblitz_guard_argv() {
    local unit="$1" n="${#TS_M_EXEC_ARGV[@]}" raw frag p line key val section="" exec_line guard_line env_line envf_line
    local n_env=0 n_envf=0 n_guard=0 n_exec=0 n_var=0 last_envf="" last_pre="" exec_seen="" cont=0 env_reset=0
    local -a dropins=()
    TS_M_RB_WHY=""
    raw="${TS_M_EXEC_RAW% "$TS_M_RB_WORD"}"
    if [[ "${TS_M_EXEC_ARGV[n-1]}" != "$TS_M_RB_WORD" ]] || [[ "$raw" == "$TS_M_EXEC_RAW" ]]; then
        TS_M_RB_WHY="${TS_M_RB_WORD} is not its last word"
        return 1
    fi
    if [[ "$TS_M_RB_IMPL" == "lnd" ]]; then
        if [[ "${TS_M_EXEC_ARGV[0]}" != "/usr/local/bin/lnd" ]]; then
            TS_M_RB_WHY="it does not run /usr/local/bin/lnd"
            return 1
        fi
        exec_line="ExecStart=${TS_M_EXEC_RAW}"
    else
        if [[ "$TS_M_EXEC_RAW" != "/bin/sh -c "* ]]; then
            TS_M_RB_WHY="it does not run /bin/sh -c"
            return 1
        fi
        exec_line="ExecStart=/bin/sh -c '${TS_M_EXEC_RAW#/bin/sh -c }'"
    fi
    if [[ "$(ts_m_unit_prop "$unit" NeedDaemonReload)" != "no" ]]; then
        TS_M_RB_WHY="its unit file changed since systemd loaded it (systemctl daemon-reload)"
        return 1
    fi
    read -r -a dropins <<< "$(ts_m_unit_prop "$unit" DropInPaths)"
    for p in "${dropins[@]}"; do
        if [[ "$p" != "${TS_M_UNIT_DIR}/${unit}.d/${TS_M_DROPIN_NAME}" ]]; then
            TS_M_RB_WHY="the drop-in ${p} can change it"
            return 1
        fi
    done
    frag=$(ts_m_unit_prop "$unit" FragmentPath)
    if [[ "$frag" != /* ]] || [[ ! -f "${TS_FS_ROOT}${frag}" ]] || [[ ! -r "${TS_FS_ROOT}${frag}" ]]; then
        TS_M_RB_WHY="its unit file (${frag:-none}) cannot be read"
        return 1
    fi
    env_line="Environment=${TS_M_RB_VAR}="
    envf_line="EnvironmentFile=-${TS_M_RB_ENVFILE}"
    guard_line="ExecStartPre=+/bin/sh -c 'if [ -x ${TS_M_RB_SCRIPT} ]; then exec ${TS_M_RB_SCRIPT} guard ${TS_M_RB_IMPL} ${TS_M_RB_CHAIN}; fi; echo tunnelsats-guard: internet.tunnelsats.sh is missing, Lightning starts Tor-only >&2; mkdir -p ${TS_M_RUN_DIR} && echo ${TS_M_RB_VAR}= > ${TS_M_RB_ENVFILE}'"
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        if [[ "$line" == [#\;]* ]]; then
            continue
        fi
        if [[ "$line" == *\\ ]]; then
            cont=1
        fi
        if [[ "$line" == \[*\] ]]; then
            section="$line"
            continue
        fi
        if [[ "$line" == *"$TS_M_RB_VAR"* ]]; then
            n_var=$((n_var + 1))
        fi
        if [[ "$section" != "[Service]" ]] || [[ "$line" != *=* ]]; then
            continue
        fi
        key="${line%%=*}"
        key="${key%"${key##*[![:space:]]}"}"
        val="${line#*=}"
        val="${val#"${val%%[![:space:]]*}"}"
        line="${key}=${val}"
        case "$key" in
            Environment)
                if [[ "$line" == "$env_line" ]]; then
                    n_env=$((n_env + 1))
                elif [[ -z "$val" ]] && [[ "$n_env" -gt 0 ]]; then
                    # An empty assignment clears the list, the default included
                    env_reset=1
                fi
                ;;
            EnvironmentFile)
                last_envf="$line"
                if [[ "$line" == "$envf_line" ]]; then
                    n_envf=$((n_envf + 1))
                fi
                ;;
            ExecStartPre)
                last_pre="$line"
                if [[ "$line" == "$guard_line" ]]; then
                    n_guard=$((n_guard + 1))
                fi
                ;;
            ExecStart)
                n_exec=$((n_exec + 1))
                exec_seen="$line"
                ;;
        esac
    done < "${TS_FS_ROOT}${frag}"
    if [[ "$cont" -eq 1 ]]; then
        TS_M_RB_WHY="its unit file continues lines with a backslash"
    elif [[ "$n_env" -ne 1 ]]; then
        TS_M_RB_WHY="it does not set ${env_line} once in [Service]"
    elif [[ "$env_reset" -eq 1 ]]; then
        TS_M_RB_WHY="an empty Environment= after ${env_line} clears that default"
    elif [[ "$n_envf" -ne 1 ]] || [[ "$last_envf" != "$envf_line" ]]; then
        TS_M_RB_WHY="it does not read ${TS_M_RB_ENVFILE} once, as its last EnvironmentFile="
    elif [[ "$n_guard" -ne 1 ]] || [[ "$last_pre" != "$guard_line" ]]; then
        TS_M_RB_WHY="it does not run the guard line (guard ${TS_M_RB_IMPL} ${TS_M_RB_CHAIN}) once, as its last ExecStartPre="
    elif [[ "$n_exec" -ne 1 ]] || [[ "$exec_seen" != "$exec_line" ]]; then
        TS_M_RB_WHY="the ExecStart= of its unit file differs from the one systemd runs"
    elif [[ "$n_var" -ne 3 ]]; then
        TS_M_RB_WHY="its unit file names ${TS_M_RB_VAR} elsewhere"
    else
        TS_M_EXEC_ARGV=("${TS_M_EXEC_ARGV[@]:0:n-1}")
        TS_M_EXEC_RAW="$raw"
        return 0
    fi
    return 1
}

# State of the env file $1 of RaspiBlitz's start guard for variable $2: absent, empty (no bytes, or
# "<VAR>=": the current start is Tor-only), flags ("<VAR>=<flags>" on one line: the clearnet flags of
# the current start) or invalid (anything else, or not a regular file that can be read).
ts_m_raspiblitz_env_state() {
    local f="$1" var="$2" content="" re
    if [[ ! -e "$f" ]] && [[ ! -L "$f" ]]; then
        echo "absent"
        return 0
    fi
    if [[ -L "$f" ]] || [[ ! -f "$f" ]] || ! content=$(head -c 4097 -- "$f" 2>/dev/null && printf x); then
        echo "invalid"
        return 0
    fi
    content="${content%x}"
    re="^${var}=[^[:cntrl:]]+"$'\n'"?\$"
    if [[ -z "$content" ]] || [[ "$content" == "${var}=" ]] || [[ "$content" == "${var}="$'\n' ]]; then
        echo "empty"
    elif [[ "${#content}" -le 4096 ]] && [[ "$content" =~ $re ]]; then
        echo "flags"
    else
        echo "invalid"
    fi
}

# Like ts_m_execstart_tokens, and succeeds only if the arguments can be checked reliably. Fails with
# TS_M_EXEC_REASON when the command line cannot be read, when a shell or a script runs (it can add
# arguments of its own) or when it uses $VAR or ${VAR} (systemd fills those in from Environment= or
# EnvironmentFile= when the unit starts). With profile $2 raspiblitz, RaspiBlitz's own shell command
# for CLN is read through (ts_m_raspiblitz_cln_argv), and so is the variable of RaspiBlitz's start
# guard (ts_m_raspiblitz_guard_argv): then the guard's env file decides, in state $3 if given (read
# before uninstall --managed cleared /run/tunnelsats), else as it is now (ts_m_raspiblitz_env_state).
# Absent or empty passes; flags mean TunnelSats is still on in RaspiBlitz, and fail like anything else.
ts_m_execstart_args() {
    local unit="$1" profile="${2:-}" rb_env="${3:-}" exe head="" rb_guard=0
    TS_M_EXEC_REASON=""
    if ! ts_m_execstart_tokens "$unit"; then
        TS_M_EXEC_REASON="the command line (ExecStart) of ${unit} cannot be read"
        return 1
    fi
    if [[ "$profile" == "raspiblitz" ]] && ts_m_raspiblitz_guard_ctx "$unit" && \
        [[ "${TS_M_EXEC_ARGV[${#TS_M_EXEC_ARGV[@]}-1]}" == "$TS_M_RB_WORD" ]]; then
        if ! ts_m_raspiblitz_guard_argv "$unit"; then
            TS_M_EXEC_REASON="the command line (ExecStart) of ${unit} ends with ${TS_M_RB_WORD} of the RaspiBlitz start guard, but the unit does not carry the guard in the expected form (${TS_M_RB_WHY})"
            return 1
        fi
        rb_guard=1
    fi
    if [[ "${TS_M_EXEC_ARGV[*]}" == *'$'* ]]; then
        TS_M_EXEC_REASON="the command line (ExecStart) of ${unit} takes values from environment variables (\$VAR or \${VAR})"
        return 1
    fi
    if [[ "$profile" == "raspiblitz" ]]; then
        ts_m_raspiblitz_cln_argv || true
    fi
    exe="${TS_M_EXEC_ARGV[0]}"
    case "${exe##*/}" in
        sh|bash|dash|zsh|ksh|mksh|ash|busybox)
            TS_M_EXEC_REASON="the command line (ExecStart) of ${unit} runs through a shell (${exe})"
            return 1
            ;;
    esac
    if [[ -f "${TS_FS_ROOT}${exe}" ]]; then
        head=$(head -c 2 "${TS_FS_ROOT}${exe}" 2>/dev/null) || head=""
        if [[ "$head" == "#!" ]]; then
            TS_M_EXEC_REASON="the command line (ExecStart) of ${unit} runs the script ${exe}, which can add arguments"
            return 1
        fi
    fi
    if [[ "$rb_guard" -eq 1 ]]; then
        if [[ -z "$rb_env" ]]; then
            rb_env=$(ts_m_raspiblitz_env_state "${TS_FS_ROOT}${TS_M_RB_ENVFILE}" "$TS_M_RB_VAR")
        fi
        case "$rb_env" in
            absent|empty) ;;
            flags)
                TS_M_EXEC_REASON="TunnelSats is still on in RaspiBlitz (${TS_M_RB_ENVFILE} holds the clearnet flags of the current start of ${unit}): remove it in the RaspiBlitz menu (SUBSCRIBE > TunnelSats > REMOVE), then enable and start ${unit}"
                return 1
                ;;
            *)
                TS_M_EXEC_REASON="${TS_M_RB_ENVFILE} of the RaspiBlitz start guard holds something other than ${TS_M_RB_VAR}=<flags>"
                return 1
                ;;
        esac
    fi
    return 0
}

# Prints the arguments of the first ExecStart of unit $1, one per line.
ts_m_unit_execstart_argv() {
    ts_m_execstart_tokens "$1" || return 1
    printf '%s\n' "${TS_M_EXEC_ARGV[@]}"
}

# Prints the home directory of user $1.
ts_m_user_home() {
    local entry home
    entry=$("$GETENT_BIN" passwd "$1" 2>/dev/null) || return 1
    home=$(printf '%s\n' "$entry" | head -n 1 | cut -d: -f6)
    if [[ "$home" != /* ]]; then
        return 1
    fi
    echo "$home"
}

# Finds the Lightning config files of unit $2 (implementation $1): the path given in ExecStart
# (--configfile, --conf, --lnddir, --lightning-dir, --lit-dir), else the default below the home of
# the unit's User. Sets TS_M_NC_FILES (files that exist and can be read) and TS_M_NC_REASON (why
# nothing usable was found). Read-only.
ts_m_node_config_files() {
    local impl="$1" unit="$2" arg prev="" conf="" dir="" user home candidates=() f
    TS_M_NC_FILES=()
    TS_M_NC_REASON=""
    while IFS= read -r arg; do
        case "$prev" in
            --configfile|-C) conf="$arg" ;;
            --conf) conf="$arg" ;;
            --lnddir|--lightning-dir|--lit-dir) dir="$arg" ;;
        esac
        case "$arg" in
            --configfile=*) conf="${arg#*=}" ;;
            --conf=*) conf="${arg#*=}" ;;
            --lnddir=*|--lightning-dir=*|--lit-dir=*) dir="${arg#*=}" ;;
        esac
        prev="$arg"
    done < <(ts_m_unit_execstart_argv "$unit" || true)
    if [[ -z "$conf" ]] && [[ -z "$dir" ]]; then
        user=$(ts_m_unit_prop "$unit" User)
        if [[ -z "$user" ]] || ! home=$(ts_m_user_home "$user"); then
            TS_M_NC_REASON="the config location is unknown (no path in ExecStart and no home directory for User=${user:-root})"
            return 0
        fi
        case "$impl" in
            lnd) dir="${home}/.lnd" ;;
            cln) dir="${home}/.lightning" ;;
            lit) dir="${home}/.lit" ;;
        esac
    fi
    if [[ -n "$conf" ]]; then
        candidates=("$conf")
    else
        case "$impl" in
            lnd) candidates=("${dir}/lnd.conf") ;;
            cln) candidates=("${dir}/config" "${dir}/bitcoin/config") ;;
            lit) candidates=("${dir}/lit.conf") ;;
        esac
    fi
    if [[ "$impl" == "lnd" ]] && { [[ -d "${TS_FS_ROOT}/usr/share/mynode" ]] || [[ -d "${TS_FS_ROOT}/mnt/hdd/mynode" ]]; } && \
        { [[ -z "$conf" ]] || [[ "$conf" == /mnt/hdd/mynode/* ]] || [[ "$conf" == */.lnd/lnd.conf ]] || \
          [[ "${TS_FS_ROOT}${conf}" -ef "${TS_FS_ROOT}/mnt/hdd/mynode/lnd/lnd.conf" ]]; }; then
        local -a mn_cands=(/mnt/hdd/mynode/settings/lnd_custom.conf /mnt/hdd/mynode/settings/lnd_extra_config.conf /mnt/hdd/mynode/lnd/lnd.conf)
        for f in "${candidates[@]}"; do
            if ! ts_in_list "$f" "${mn_cands[*]}"; then
                mn_cands+=("$f")
            fi
        done
        candidates=("${mn_cands[@]}")
    fi
    for f in "${candidates[@]}"; do
        if [[ "$f" != /* ]] || [[ "$f" == *'$'* ]]; then
            TS_M_NC_REASON="the config path ${f} cannot be resolved"
            continue
        fi
        if [[ -f "${TS_FS_ROOT}${f}" ]] && [[ -r "${TS_FS_ROOT}${f}" ]]; then
            local dup=0 existing_f
            for existing_f in "${TS_M_NC_FILES[@]}"; do
                if [[ "${TS_FS_ROOT}${f}" -ef "${TS_FS_ROOT}${existing_f}" ]]; then
                    dup=1
                    break
                fi
            done
            if [[ "$dup" -eq 0 ]]; then
                TS_M_NC_FILES+=("$f")
            fi
        elif [[ -e "${TS_FS_ROOT}${f}" ]]; then
            TS_M_NC_REASON="${f} cannot be read"
        fi
    done
    if [[ ${#TS_M_NC_FILES[@]} -eq 0 ]] && [[ -z "$TS_M_NC_REASON" ]]; then
        TS_M_NC_REASON="no config file found (${candidates[*]})"
    fi
    return 0
}

# Prints the active (uncommented) settings of config file $1 as "<line number>|<key>|<value>",
# keys lowercased; a bare flag has an empty value.
ts_m_config_settings() {
    awk '
        { sub(/\r$/, "") }
        {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            if (line == "" || line ~ /^[#;]/ || line ~ /^\[/) next
            key = line; val = ""
            eq = index(line, "=")
            if (eq > 0) { key = substr(line, 1, eq - 1); val = substr(line, eq + 1) }
            sub(/[[:space:]]+$/, "", key); sub(/^[[:space:]]+/, "", val); sub(/[[:space:]]+$/, "", val)
            print NR "|" tolower(key) "|" val
        }' "$1" 2>/dev/null
}

# Succeeds if CLN addr value $1 stays off the clearnet: a loopback address, a Tor address (onion,
# autotor:, statictor:) or a local socket path.
ts_m_cln_addr_private() {
    local v="${1,,}" host
    case "$v" in
        autotor:*|statictor:*|/*) return 0 ;;
    esac
    if [[ "$v" =~ \.onion(:[0-9]+)?$ ]]; then
        return 0
    fi
    host="$v"
    if [[ "$host" =~ ^(.*):[0-9]{1,5}$ ]]; then
        host="${BASH_REMATCH[1]}"
    fi
    case "$host" in
        localhost|127.*|"[::1]"|::1) return 0 ;;
    esac
    return 1
}

# Succeeds if setting $2 (key lowercased) with value $3 is a TunnelSats clearnet setting for
# implementation $1: for LND and LIT externalhosts or tor.skip-proxy-for-clearnet-targets as a bare
# flag, true or 1 (LIT also with the lnd. prefix); for CLN bind-addr=0.0.0.0:9735, an addr that is
# not loopback or Tor (it binds and announces), an announce-addr that is not an onion address, or
# always-use-proxy=false|0.
ts_m_nc_setting_hit() {
    local impl="$1" key="$2" val="$3"
    if [[ "$impl" == "lit" ]]; then
        key="${key#lnd.}"
    fi
    case "${impl}:${key}" in
        lnd:externalhosts|lit:externalhosts)
            if [[ -n "$val" ]]; then
                return 0
            fi
            ;;
        lnd:tor.skip-proxy-for-clearnet-targets|lit:tor.skip-proxy-for-clearnet-targets)
            case "${val,,}" in
                ""|true|1) return 0 ;;
            esac
            ;;
        cln:bind-addr)
            case "$val" in
                0.0.0.0:9735|:9735|"[::]:9735") return 0 ;;
            esac
            ;;
        cln:addr)
            # addr binds and announces: anything but loopback, Tor or a local socket
            if [[ -n "$val" ]] && ! ts_m_cln_addr_private "$val"; then
                return 0
            fi
            ;;
        cln:announce-addr)
            if [[ -n "$val" ]] && [[ ! "${val,,}" =~ \.onion(:[0-9]+)?$ ]]; then
                return 0
            fi
            ;;
        cln:always-use-proxy)
            case "${val,,}" in
                false|0) return 0 ;;
            esac
            ;;
    esac
    return 1
}

# Reports TunnelSats clearnet settings given on the command line (TS_M_EXEC_ARGV) of unit $2
# (implementation $1): --key=value, a bare --flag, or --key value for settings that take a value.
# Adds "<unit> ExecStart: --<key>[=<value>]" to TS_M_NC_LINES.
ts_m_execstart_clearnet() {
    local impl="$1" unit="$2" i n="${#TS_M_EXEC_ARGV[@]}" arg key val
    for (( i = 1; i < n; i++ )); do
        arg="${TS_M_EXEC_ARGV[$i]}"
        if [[ "$arg" != --?* ]]; then
            continue
        fi
        key="${arg#--}"
        val=""
        if [[ "$key" == *=* ]]; then
            val="${key#*=}"
            key="${key%%=*}"
        else
            case "${impl}:${key,,}" in
                lnd:externalhosts|lit:externalhosts|lit:lnd.externalhosts|cln:bind-addr|cln:addr|cln:announce-addr|cln:always-use-proxy)
                    if (( i + 1 < n )) && [[ "${TS_M_EXEC_ARGV[$((i + 1))]}" != --* ]]; then
                        i=$((i + 1))
                        val="${TS_M_EXEC_ARGV[$i]}"
                    fi
                    ;;
            esac
        fi
        key="${key,,}"
        if ts_m_nc_setting_hit "$impl" "$key" "$val"; then
            TS_M_NC_LINES+=("${unit} ExecStart: --${key}${val:+=${val}}")
        fi
    done
}

# Reports active TunnelSats clearnet settings of the Lightning unit $2 (implementation $1), in its
# config file and on its command line (ExecStart); see ts_m_nc_setting_hit. Sets TS_M_NC_STATUS to
# clearnet (settings found), unknown (config missing or unreadable, a CLN config that includes other
# files, or a command line that cannot be checked reliably: shell, script, $VAR) or clean,
# TS_M_NC_LINES to "<file>:<line>:<setting>" and "<unit> ExecStart: <argument>", followed by the
# include lines of a CLN config ("<file>:<line>:include <path>", also in TS_M_NC_INCLUDES), and
# TS_M_NC_REASON. $3 = managed profile (raspiblitz: RaspiBlitz's shell command for CLN and the
# variable of its start guard can be checked, see ts_m_raspiblitz_cln_argv and
# ts_m_raspiblitz_guard_argv), $4 = state of the start guard's env file read earlier
# (ts_m_execstart_args). Read-only; the bare-metal guard reuses it.
ts_m_node_config_clearnet() {
    local impl="$1" unit="$2" profile="${3:-}" rb_env="${4:-}" f entry num key val exec_ok=1
    TS_M_NC_STATUS="unknown"
    TS_M_NC_LINES=()
    TS_M_NC_INCLUDES=()
    ts_m_node_config_files "$impl" "$unit"
    for f in "${TS_M_NC_FILES[@]}"; do
        while IFS= read -r entry; do
            num="${entry%%|*}"
            entry="${entry#*|}"
            key="${entry%%|*}"
            val="${entry#*|}"
            if ts_m_nc_setting_hit "$impl" "$key" "$val"; then
                TS_M_NC_LINES+=("${f}:${num}:${key}=${val}")
            fi
        done < <(ts_m_config_settings "${TS_FS_ROOT}${f}")
        # lightningd reads an included file as part of its config; included files are not
        # followed here, so an include makes the config one that cannot be checked
        if [[ "$impl" == "cln" ]]; then
            while IFS= read -r entry; do
                TS_M_NC_INCLUDES+=("${f}:${entry%%|*}:include ${entry#*|}")
            done < <(ts_m_cln_config_includes "${TS_FS_ROOT}${f}")
        fi
    done
    # The command line counts like the config file; one that cannot be checked makes it unknown
    if ts_m_execstart_args "$unit" "$profile" "$rb_env"; then
        ts_m_execstart_clearnet "$impl" "$unit"
    else
        exec_ok=0
        if [[ ${#TS_M_NC_FILES[@]} -eq 0 ]] && [[ -n "$TS_M_NC_REASON" ]]; then
            TS_M_NC_REASON="${TS_M_NC_REASON}; ${TS_M_EXEC_REASON}"
        else
            TS_M_NC_REASON="$TS_M_EXEC_REASON"
        fi
    fi
    if [[ ${#TS_M_NC_INCLUDES[@]} -gt 0 ]]; then
        TS_M_NC_REASON="${TS_M_NC_REASON:+${TS_M_NC_REASON}; }the CLN config includes other files, which are not checked"
    fi
    if [[ ${#TS_M_NC_LINES[@]} -gt 0 ]]; then
        TS_M_NC_STATUS="clearnet"
    elif [[ ${#TS_M_NC_FILES[@]} -eq 0 ]] || [[ "$exec_ok" -eq 0 ]] || [[ ${#TS_M_NC_INCLUDES[@]} -gt 0 ]]; then
        TS_M_NC_STATUS="unknown"
    else
        TS_M_NC_STATUS="clean"
    fi
    TS_M_NC_LINES+=("${TS_M_NC_INCLUDES[@]}")
    return 0
}

# Prints the include directives of CLN config file $1 as "<line number>|<path>": active lines
# "include <path>" or "include=<path>", as lightningd reads them.
ts_m_cln_config_includes() {
    awk '
        { sub(/\r$/, "") }
        {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)
            if (match(line, /^include([[:space:]]+|=)/)) {
                path = substr(line, RLENGTH + 1)
                sub(/^[[:space:]]+/, "", path)
                if (path != "") print NR "|" path
            }
        }' "$1" 2>/dev/null
}

# Prints the TCP ports of the non-loopback Lightning listen addresses set in the node config of
# unit $2 (implementation $1): LND/LIT listen, CLN addr and bind-addr. Nothing if none is set.
ts_m_node_config_listen_ports() {
    local impl="$1" unit="$2" f entry key val host port
    ts_m_node_config_files "$impl" "$unit"
    for f in "${TS_M_NC_FILES[@]}"; do
        while IFS= read -r entry; do
            entry="${entry#*|}"
            key="${entry%%|*}"
            val="${entry#*|}"
            case "$impl:$key" in
                lnd:listen|lit:listen|lit:lnd.listen|cln:addr|cln:bind-addr) ;;
                *) continue ;;
            esac
            if [[ ! "$val" =~ ^(.*):([0-9]{1,5})$ ]]; then
                continue
            fi
            host="${BASH_REMATCH[1]}"
            port="${BASH_REMATCH[2]}"
            case "$host" in
                localhost|127.*|"[::1]"|::1) continue ;;
            esac
            echo "$port"
        done < <(ts_m_config_settings "${TS_FS_ROOT}${f}")
    done
    return 0
}

# ---------------------------------------------------------------------------
# Managed mode: install --managed baremetal|raspiblitz
# ---------------------------------------------------------------------------

# Succeeds on a unified cgroup v2 hierarchy mounted at /sys/fs/cgroup.
ts_m_cgroup2_unified() {
    local dev mp fs rest
    if [[ ! -f "${TS_FS_ROOT}${TS_M_CGROUP_ROOT}/cgroup.controllers" ]]; then
        return 1
    fi
    while read -r dev mp fs rest; do
        if [[ "$mp" == "$TS_M_CGROUP_ROOT" ]]; then
            if [[ "$fs" == "cgroup2" ]]; then
                return 0
            fi
            return 1
        fi
    done < "${TS_FS_ROOT}/proc/mounts"
    return 1
}

# Prints "<kind>|<evidence>|<ids of the artifacts found>" of an existing TunnelSats install, using
# detect's read-only classification (runs in a subshell, so detect's globals stay untouched).
ts_m_existing_install() {
    (
        found=" "
        ts_detect_artifacts
        ts_detect_config
        ts_detect_install_kind
        for i in "${!TSD_ART_ID[@]}"; do
            case "${TSD_ART_STATUS[$i]}" in
                absent|unavailable) continue ;;
            esac
            if [[ "${TSD_ART_ID[$i]}" == "managed_script" ]]; then
                continue
            fi
            if [[ "$found" != *" ${TSD_ART_ID[$i]} "* ]]; then
                found+="${TSD_ART_ID[$i]} "
            fi
        done
        found="${found# }"
        echo "${TSD_INSTALL_KIND}|${TSD_EVIDENCE[*]}|${found% }"
    )
}

# Picks the Lightning unit among lnd.service, lightningd.service, litd.service and lit.service
# (LoadState=loaded). With --impl, the unit of that implementation; it must be the only candidate
# (litd.service and lit.service both belong to lit). Without --impl, exactly one unit may be
# loaded. Units of other implementations may stay installed: they are not tunneled and are listed
# in TS_M_OTHER_UNITS. Sets TS_M_IMPL and TS_M_UNIT. The raspiblitz profile names its unit instead
# (ts_m_select_raspiblitz_unit).
ts_m_select_ln_unit() {
    local entry impl unit state loaded=() impls=() picked=() picked_impl="" unit_list="$TS_M_LN_UNITS"
    if [[ "$TS_OPT_PROFILE" == "raspiblitz" ]]; then
        ts_m_select_raspiblitz_unit
        return 0
    fi
    if [[ "$TS_OPT_PROFILE" == "mynode" ]]; then
        if [[ "$TS_OPT_IMPL" == "cln" ]]; then
            ts_usage_error "${TS_COMMAND:-install} --managed mynode supports --impl lnd or --impl lit, not cln (myNode does not ship Core Lightning)"
        fi
        unit_list="$TS_M_MYNODE_LN_UNITS"
    fi
    TS_M_OTHER_UNITS=()
    for entry in $unit_list; do
        impl="${entry%%:*}"
        unit="${entry#*:}"
        state=$(ts_m_unit_prop "$unit" LoadState)
        if [[ "$state" == "loaded" ]]; then
            loaded+=("$unit")
            impls+=("$impl")
        fi
    done
    if [[ -n "$TS_OPT_IMPL" ]]; then
        for entry in "${!loaded[@]}"; do
            if [[ "${impls[$entry]}" == "$TS_OPT_IMPL" ]]; then
                picked+=("${loaded[$entry]}")
                picked_impl="${impls[$entry]}"
            else
                TS_M_OTHER_UNITS+=("${loaded[$entry]}")
            fi
        done
        if [[ ${#picked[@]} -eq 0 ]]; then
            ts_fail 7 E_LN_UNIT refused "--impl ${TS_OPT_IMPL}: no unit of this implementation is installed (found: ${loaded[*]:-none})"
        fi
        if [[ ${#picked[@]} -gt 1 ]]; then
            ts_fail 7 E_LN_UNIT refused "--impl ${TS_OPT_IMPL}: several units are installed (${picked[*]}); managed mode tunnels exactly one"
        fi
        TS_M_IMPL="$picked_impl"
        TS_M_UNIT="${picked[0]}"
        return 0
    fi
    if [[ ${#loaded[@]} -eq 0 ]]; then
        if [[ "$TS_OPT_PROFILE" == "mynode" ]]; then
            ts_fail 7 E_LN_UNIT refused "No Lightning unit found (lnd.service, litd.service or lit.service)"
        fi
        ts_fail 7 E_LN_UNIT refused "No Lightning unit found (lnd.service, lightningd.service, litd.service or lit.service)"
    fi
    if [[ ${#loaded[@]} -gt 1 ]]; then
        ts_fail 7 E_LN_UNIT refused "Several Lightning units are installed (${loaded[*]}); choose the one to tunnel with --impl"
    fi
    TS_M_IMPL="${impls[0]}"
    TS_M_UNIT="${loaded[0]}"
}

# Prints the RaspiBlitz unit of implementation $1 (lnd or cln) on chain $2 (mainnet, testnet or
# signet). RaspiBlitz names the unit of a testnet instance with the prefix t and that of a signet
# instance with s (lnd.install.sh, cl.install-service.sh): lnd.service, tlnd.service, slnd.service,
# lightningd.service, tlightningd.service, slightningd.service. Fails for any other value.
ts_m_raspiblitz_unit() {
    local base prefix
    case "$1" in
        lnd) base="lnd.service" ;;
        cln) base="lightningd.service" ;;
        *) return 1 ;;
    esac
    case "$2" in
        mainnet) prefix="" ;;
        testnet) prefix="t" ;;
        signet) prefix="s" ;;
        *) return 1 ;;
    esac
    echo "${prefix}${base}"
}

# raspiblitz profile: the unit follows from --impl and --network (default mainnet) and must be
# loaded. The other RaspiBlitz Lightning units that are loaded are not tunneled; they are listed in
# TS_M_OTHER_UNITS. Sets TS_M_IMPL and TS_M_UNIT.
ts_m_select_raspiblitz_unit() {
    local network="${TS_OPT_NETWORK:-mainnet}" unit entry other state
    TS_M_OTHER_UNITS=()
    if ! unit=$(ts_m_raspiblitz_unit "$TS_OPT_IMPL" "$network"); then
        ts_usage_error "${TS_COMMAND} --managed raspiblitz requires --impl lnd or --impl cln and --network mainnet, testnet or signet"
    fi
    state=$(ts_m_unit_prop "$unit" LoadState)
    if [[ "$state" != "loaded" ]]; then
        ts_fail 7 E_LN_UNIT refused "--impl ${TS_OPT_IMPL} --network ${network}: ${unit} is not installed (LoadState ${state:-unknown})"
    fi
    for entry in $TS_M_RASPIBLITZ_LN_UNITS; do
        other="${entry#*:}"
        if [[ "$other" != "$unit" ]] && [[ "$(ts_m_unit_prop "$other" LoadState)" == "loaded" ]]; then
            TS_M_OTHER_UNITS+=("$other")
        fi
    done
    TS_M_IMPL="$TS_OPT_IMPL"
    TS_M_UNIT="$unit"
}

# Sets TS_M_USER and TS_M_UID for the Lightning unit: a dedicated non-root user is required, since
# the uid backstop and the emergency block select the daemon's traffic by uid.
ts_m_select_ln_user() {
    local user dyn entry uid
    user=$(ts_m_unit_prop "$TS_M_UNIT" User)
    dyn=$(ts_m_unit_prop "$TS_M_UNIT" DynamicUser)
    if [[ "$dyn" == "yes" ]]; then
        ts_fail 7 E_LN_USER refused "${TS_M_UNIT} uses DynamicUser=; managed mode needs a fixed, non-root User="
    fi
    if [[ -z "$user" ]] || [[ "$user" == "root" ]] || [[ "$user" == "0" ]]; then
        ts_fail 7 E_LN_USER refused "${TS_M_UNIT} runs as root; managed mode needs a dedicated, non-root User="
    fi
    entry=$("$GETENT_BIN" passwd "$user" 2>/dev/null | head -n 1) || entry=""
    uid=$(printf '%s\n' "$entry" | cut -d: -f3)
    if [[ ! "$uid" =~ ^[1-9][0-9]*$ ]]; then
        ts_fail 7 E_LN_USER refused "User=${user} of ${TS_M_UNIT} is unknown or root"
    fi
    TS_M_USER=$(printf '%s\n' "$entry" | cut -d: -f1)
    TS_M_UID="$uid"
    if [[ ! "$TS_M_USER" =~ ^[a-z_][a-z0-9_.-]{0,31}$ ]]; then
        ts_fail 7 E_LN_USER refused "User=${user} of ${TS_M_UNIT} has an unsupported name"
    fi
}

# Every check that can refuse the install before anything changes.
ts_m_install_preflight() {
    local guess existing kind evidence found listing line ports p port_ok=0 fam profile="${TS_OPT_PROFILE:-baremetal}"
    guess=$(ts_guess_platform "$TS_FS_ROOT")
    if [[ -n "$TS_OPT_PLATFORM" ]] && [[ "$TS_OPT_PLATFORM" != "$profile" ]]; then
        ts_fail 7 E_PLATFORM_UNSUPPORTED refused "--platform ${TS_OPT_PLATFORM} does not match the managed profile ${profile}"
    fi
    case "$profile:$guess" in
        baremetal:|raspiblitz:raspiblitz|mynode:mynode) ;;
        baremetal:raspiblitz)
            ts_fail 7 E_PLATFORM_UNSUPPORTED refused "This node is a RaspiBlitz: use 'install --managed raspiblitz --impl lnd|cln'"
            ;;
        baremetal:mynode)
            ts_fail 7 E_PLATFORM_UNSUPPORTED refused "This node is a myNode: use 'install --managed mynode'"
            ;;
        raspiblitz:*)
            ts_fail 7 E_PLATFORM_UNSUPPORTED refused "The raspiblitz profile needs a RaspiBlitz (detected: ${guess:-no RaspiBlitz})"
            ;;
        mynode:*)
            ts_fail 7 E_PLATFORM_UNSUPPORTED refused "The mynode profile needs a myNode (detected: ${guess:-no myNode})"
            ;;
        *)
            ts_fail 7 E_PLATFORM_UNSUPPORTED refused "Managed mode supports bare-metal systemd nodes, RaspiBlitz and myNode only for now (detected: ${guess})"
            ;;
    esac
    if [[ ! -d "${TS_FS_ROOT}/run/systemd/system" ]]; then
        ts_fail 6 E_SYSTEMD_MISSING capability "systemd is not running as PID 1"
    fi
    if ! ts_m_cgroup2_unified; then
        ts_fail 6 E_CGROUP_V2_MISSING capability "A unified cgroup v2 hierarchy at ${TS_M_CGROUP_ROOT} is required"
    fi
    if ! command -v "$PERL_BIN" >/dev/null 2>&1; then
        ts_fail 6 E_DEPENDENCY_MISSING capability "perl is missing; verify's kill switch and IPv6 probes need it (Debian and Ubuntu ship it as perl-base)"
    fi
    if ts_m_inventory_present; then
        ts_fail 7 E_MANAGED_PRESENT refused "A managed install already exists (complete, interrupted or partly removed); run 'tunnelsats.sh uninstall --managed' first"
    fi
    existing=$(ts_m_existing_install) || existing="unknown||"
    kind="${existing%%|*}"
    existing="${existing#*|}"
    evidence="${existing%%|*}"
    found="${existing#*|}"
    if [[ "$found" == "wg_config" ]] && [[ -e "${TS_FS_ROOT}${TS_M_WG_CONF}" ]]; then
        ts_fail 7 E_CONFIG_PRESENT refused "${TS_M_WG_CONF} already exists, without any other trace of a TunnelSats install. If it is left from a previous install, run 'tunnelsats.sh uninstall' first; if it is your own file, move it elsewhere and pass it with --config (managed mode installs its own copy)."
    fi
    if [[ "$kind" != "none" ]]; then
        ts_fail 7 E_LEGACY_INSTALL refused "An existing TunnelSats install was found (${kind}; evidence: ${evidence:-${found:-none}}). Run 'tunnelsats.sh uninstall' first; taking over an existing install comes in a later version."
    fi
    ts_m_select_ln_unit
    ts_m_select_ln_user
    listing=$("$IP_BIN" route show table 52 2>&1) || listing=""
    if printf '%s\n' "$listing" | grep -qE '^(default|0\.0\.0\.0/0)[[:space:]]'; then
        ts_fail 7 E_TAILSCALE_EXIT_NODE refused "A Tailscale exit node is active (default route in table 52); its rules come before the TunnelSats rules"
    fi
    for fam in 4 6; do
        if [[ "$fam" == "6" ]] && ! ts_m_ipv6_available; then
            continue
        fi
        if ! listing=$(ts_m_table_routes "$fam"); then
            ts_fail 1 E_KERNEL_STATE operational "IPv${fam} routing table ${TS_M_RT_TABLE} cannot be read"
        fi
        if [[ -n "$listing" ]]; then
            ts_fail 7 E_TABLE_51820_IN_USE refused "IPv${fam} routing table ${TS_M_RT_TABLE} is in use: ${listing%%$'\n'*}"
        fi
        if ! listing=$("$IP_BIN" "-${fam}" rule show 2>/dev/null); then
            ts_fail 1 E_KERNEL_STATE operational "IPv${fam} policy rules cannot be read"
        fi
        while IFS= read -r line; do
            case "$line" in
                21818:*|21819:*|21820:*|21821:*|21822:*)
                    ts_fail 7 E_RULE_PRIORITY_IN_USE refused "IPv${fam} policy rule priority ${line%%:*} is in use: ${line}"
                    ;;
            esac
        done < <(printf '%s\n' "$listing")
    done
    ports=$(ts_m_node_config_listen_ports "$TS_M_IMPL" "$TS_M_UNIT")
    if [[ -n "$ports" ]]; then
        for p in $ports; do
            if [[ "$p" == "$TS_M_LN_PORT" ]]; then
                port_ok=1
            fi
        done
        if [[ "$port_ok" -eq 0 ]]; then
            ts_fail 7 E_LN_PORT refused "Lightning listens on port(s) $(echo $ports); the TunnelSats server forwards to ${TS_M_LN_PORT}"
        fi
    fi
    if [[ ! -f "$TS_SCRIPT_PATH" ]] || [[ ! -r "$TS_SCRIPT_PATH" ]]; then
        ts_fail 2 E_USAGE usage "Run tunnelsats.sh from a file (not through a pipe): managed mode installs a copy of it"
    fi
    return 0
}

# Sanitizes the subscription config into a private temporary directory and checks what the
# managed tunnel needs. Sets TS_M_SANITIZED. Refuses with E_CONFIG_INVALID (exit 8).
ts_m_install_validate_config() {
    local line section="" key val priv="" pub="" addr=0 endpoint="" allowed=0 ips ip
    if [[ -z "$CONFIG_FILE" ]] || [[ ! -f "$CONFIG_FILE" ]]; then
        ts_fail 8 E_CONFIG_INVALID input "WireGuard config not found: ${CONFIG_FILE:-none}"
    fi
    TS_M_TMP_DIR=$(mktemp -d) || ts_fail 1 E_INTERNAL operational "Cannot create a temporary directory"
    chmod 0700 "$TS_M_TMP_DIR"
    TS_M_SANITIZED="${TS_M_TMP_DIR}/sanitized.conf"
    if ! sanitize_wireguard_config "$CONFIG_FILE" "$TS_M_SANITIZED" >&2; then
        ts_fail 8 E_CONFIG_INVALID input "The WireGuard config could not be sanitized (PrivateKey and Endpoint are required)"
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"
        if [[ "$line" =~ ^\[([A-Za-z]+)\] ]]; then
            section="${BASH_REMATCH[1],,}"
            continue
        fi
        if [[ ! "$line" =~ ^([A-Za-z]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            continue
        fi
        key="${BASH_REMATCH[1],,}"
        val="${BASH_REMATCH[2]%%#*}"
        val="${val%"${val##*[![:space:]]}"}"
        case "$section:$key" in
            interface:privatekey) priv="$val" ;;
            interface:address) addr=1 ;;
            peer:publickey) pub="$val" ;;
            peer:endpoint) endpoint="$val" ;;
            peer:allowedips)
                ips="${val//,/ }"
                for ip in $ips; do
                    if [[ "$ip" == "0.0.0.0/0" ]]; then
                        allowed=1
                    fi
                done
                ;;
        esac
    done < "$TS_M_SANITIZED"
    if ! ts_valid_wg_key "$priv" || ! ts_valid_wg_key "$pub"; then
        ts_fail 8 E_CONFIG_INVALID input "The WireGuard config needs a valid PrivateKey and peer PublicKey"
    fi
    if [[ "$addr" -eq 0 ]]; then
        ts_fail 8 E_CONFIG_INVALID input "The WireGuard config has no Address"
    fi
    if ! ts_detect_parse_endpoint "$endpoint"; then
        ts_fail 8 E_CONFIG_INVALID input "The WireGuard config has no valid Endpoint (host:port)"
    fi
    if [[ "$allowed" -eq 0 ]]; then
        ts_fail 8 E_CONFIG_INVALID input "AllowedIPs must include 0.0.0.0/0, so the tunnel carries every destination"
    fi
    return 0
}

# Installs wireguard-tools, nftables and curl (verify's probes) when missing; managed mode never
# installs resolvconf or cgroup-tools.
ts_m_install_packages() {
    local missing=0 tpl=0 p
    for p in /lib/systemd/system/wg-quick@.service /usr/lib/systemd/system/wg-quick@.service /etc/systemd/system/wg-quick@.service; do
        if [[ -f "${TS_FS_ROOT}${p}" ]]; then
            tpl=1
        fi
    done
    if ! command -v "$WG_BIN" >/dev/null 2>&1 || ! command -v "$WG_QUICK_BIN" >/dev/null 2>&1 || [[ "$tpl" -eq 0 ]] || \
        ! command -v "$NFT_BIN" >/dev/null 2>&1 || ! command -v "$CURL_BIN" >/dev/null 2>&1; then
        missing=1
    fi
    if [[ "$missing" -eq 0 ]]; then
        return 0
    fi
    print_info "Installing wireguard-tools, nftables and curl..."
    if ! apt-get update -qq >/dev/null 2>&1 || ! apt-get install -yqq wireguard-tools nftables curl >/dev/null 2>&1; then
        ts_fail 6 E_DEPENDENCY_MISSING capability "Installing wireguard-tools, nftables and curl failed"
    fi
    return 0
}

# Checks the commands managed mode runs (after the package step).
ts_m_check_tools() {
    local c
    for c in "$WG_BIN" "$WG_QUICK_BIN" "$NFT_BIN" "$SYSTEMCTL_BIN" "$SYSTEMD_RUN_BIN" "$UNSHARE_BIN" "$CURL_BIN" "$GETENT_BIN" flock sysctl sha256sum install; do
        if ! command -v "$c" >/dev/null 2>&1; then
            ts_fail 6 E_DEPENDENCY_MISSING capability "Required command not found: ${c}"
        fi
    done
    return 0
}

# Loads the complete kill switch ruleset into a throwaway network namespace, with a cgroup that
# exists now in place of the slice: proves that this kernel accepts every expression and hook
# combination (socket cgroupv2 among them) without changing the host. Fails with E_CAPABILITY_MISSING.
ts_m_capability_probe() {
    local cg="" probe err="" rc=0
    cg=$(sed -n 's|^0::/\([^/]\{1,\}\).*|\1|p' "${TS_FS_ROOT}/proc/self/cgroup" 2>/dev/null | head -n 1) || cg=""
    if [[ -z "$cg" ]] || [[ ! -d "${TS_FS_ROOT}${TS_M_CGROUP_ROOT}/${cg}" ]]; then
        cg="system.slice"
    fi
    probe="${TS_M_TMP_DIR}/probe.nft"
    if ! ts_m_render_ruleset "$cg" 1 > "$probe"; then
        ts_fail 1 E_INTERNAL operational "Cannot render the probe ruleset"
    fi
    err=$("$UNSHARE_BIN" --net -- "$NFT_BIN" -f "$probe" 2>&1) || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        err="${err//$'\n'/ }"
        ts_fail 6 E_CAPABILITY_MISSING capability "This kernel or nft does not accept the kill switch ruleset (socket cgroupv2 needs Linux 5.13+): ${err:0:300}"
    fi
    return 0
}

# Prints the files install writes, in the order it writes them: the planned file list of the
# write-ahead inventory.
ts_m_planned_files() {
    printf '%s\n' "$TS_M_BIN" "${TS_M_UNIT_DIR}/${TS_M_SLICE_UNIT}" "${TS_M_UNIT_DIR}/${TS_M_KILLSWITCH_UNIT}" \
        "${TS_M_UNIT_DIR}/${TS_M_VERIFIER_UNIT}" "${TS_M_UNIT_DIR}/${TS_M_TIMER_UNIT}" \
        "${TS_M_UNIT_DIR}/${TS_M_UNIT}.d/${TS_M_DROPIN_NAME}" "${TS_M_UNIT_DIR}/${TS_M_WG_UNIT}.d/${TS_M_DROPIN_NAME}" \
        "$TS_M_WG_CONF"
}

# Plans the install for the write-ahead inventory: every file install writes (sha256 still
# unknown) and every directory it will have to create.
ts_m_install_plan() {
    local p
    TS_M_FILES=()
    TS_M_FILE_SHA=()
    TS_M_CREATED_DIRS=()
    TS_M_ENABLED_UNITS=()
    while IFS= read -r p; do
        TS_M_FILES+=("$p")
        TS_M_FILE_SHA+=("")
    done < <(ts_m_planned_files)
    for p in "$TS_M_STATE_DIR" "${TS_M_UNIT_DIR}/${TS_M_UNIT}.d" "${TS_M_UNIT_DIR}/${TS_M_WG_UNIT}.d" "$TS_M_WG_DIR"; do
        if [[ ! -d "${TS_FS_ROOT}${p}" ]]; then
            TS_M_CREATED_DIRS+=("$p")
        fi
    done
}

# Writes the script copy, units, drop-ins and tunnel config. The inventory comes first (state
# "installing", every planned file and directory), so even an interrupted install leaves a record
# that uninstall --managed follows; each file's sha256 is recorded right after it is written. The
# recorder runs in this shell (input through process substitution, never a pipeline, which would
# run it in a subshell and lose the record).
ts_m_install_files() {
    local unit_dir="$TS_M_UNIT_DIR" dropin_dir="${TS_M_UNIT_DIR}/${TS_M_UNIT}.d" wg_dropin_dir="${TS_M_UNIT_DIR}/${TS_M_WG_UNIT}.d"
    local tmp sha_src="" sha_dst=""
    ts_m_install_plan
    TS_M_INV_STATE="installing"
    ts_m_ensure_dir "$TS_M_STATE_DIR" 0755 || return 1
    ts_m_inventory_write || return 1
    # Script copy (atomic: temporary file in the target directory, then rename)
    tmp=$(mktemp "${TS_FS_ROOT}${TS_M_BIN%/*}/.tunnelsats.XXXXXX") || return 1
    if ! install -m 0755 "$TS_SCRIPT_PATH" "$tmp" || ! mv -f "$tmp" "${TS_FS_ROOT}${TS_M_BIN}"; then
        rm -f "$tmp"
        return 1
    fi
    sha_src=$(ts_m_sha256 "$TS_SCRIPT_PATH") || sha_src=""
    sha_dst=$(ts_m_sha256 "${TS_FS_ROOT}${TS_M_BIN}") || sha_dst=""
    ts_m_record_file "$TS_M_BIN" "$sha_dst"
    if [[ -z "$sha_dst" ]] || [[ "$sha_src" != "$sha_dst" ]] || ! ts_m_inventory_write; then
        return 1
    fi
    ts_m_install_file "${unit_dir}/${TS_M_SLICE_UNIT}" 0644 < <(ts_m_render_slice_unit) || return 1
    ts_m_install_file "${unit_dir}/${TS_M_KILLSWITCH_UNIT}" 0644 < <(ts_m_render_killswitch_unit "$TS_M_UNIT" "$TS_M_INV_UID") || return 1
    ts_m_install_file "${unit_dir}/${TS_M_VERIFIER_UNIT}" 0644 < <(ts_m_render_verifier_service) || return 1
    ts_m_install_file "${unit_dir}/${TS_M_TIMER_UNIT}" 0644 < <(ts_m_render_verifier_timer) || return 1
    ts_m_ensure_dir "$dropin_dir" 0755 || return 1
    ts_m_install_file "${dropin_dir}/${TS_M_DROPIN_NAME}" 0644 < <(ts_m_render_ln_dropin) || return 1
    ts_m_ensure_dir "$wg_dropin_dir" 0755 || return 1
    ts_m_install_file "${wg_dropin_dir}/${TS_M_DROPIN_NAME}" 0644 < <(ts_m_render_wg_dropin) || return 1
    ts_m_ensure_dir "$TS_M_WG_DIR" 0700 || return 1
    ts_m_install_file "$TS_M_WG_CONF" 0600 < <(ts_m_render_wg_config "$TS_M_SANITIZED") || return 1
    return 0
}

# Prints the files only managed mode creates, one per line. Install refuses while any of them
# exists (detect reports each one), so removal deletes them even when the record misses one.
# The tunnel config is not among them: it is removed only when the record lists it.
ts_m_fixed_files() {
    local entry
    printf '%s\n' "$TS_M_BIN" "${TS_M_UNIT_DIR}/${TS_M_SLICE_UNIT}" "${TS_M_UNIT_DIR}/${TS_M_KILLSWITCH_UNIT}" \
        "${TS_M_UNIT_DIR}/${TS_M_VERIFIER_UNIT}" "${TS_M_UNIT_DIR}/${TS_M_TIMER_UNIT}" \
        "${TS_M_UNIT_DIR}/${TS_M_WG_UNIT}.d/${TS_M_DROPIN_NAME}"
    for entry in $TS_M_ALL_LN_UNITS; do
        printf '%s\n' "${TS_M_UNIT_DIR}/${entry#*:}.d/${TS_M_DROPIN_NAME}"
    done
}

# Keeps the inventory for a repeated uninstall --managed: state "removing" and the items in
# TS_M_REMAINING. Adds the inventory itself to TS_M_REMAINING if it cannot be written.
ts_m_keep_removal_record() {
    if [[ ! -d "${TS_FS_ROOT}${TS_M_STATE_DIR}" ]]; then
        return 0
    fi
    TS_M_INV_STATE="removing"
    TS_M_INV_REMAINING=("${TS_M_REMAINING[@]}")
    if ! ts_m_inventory_write; then
        TS_M_REMAINING+=("${TS_M_INVENTORY} could not be updated")
    fi
}

# Removes the managed dataplane recorded in TS_M_* (inventory or a partial install) plus the
# files only managed mode creates. The inventory says "removing" before the first change. Order:
# the Lightning drop-in, units, kernel state and the emergency block, files, runtime files. Then
# everything is read back from the file system and from systemd. Only when nothing remains go the
# script copy, the inventory, the directories install created and, last, the runtime state with the
# emergency records; otherwise the inventory stays (state "removing", with the items that remained),
# together with the script copy and the emergency records, so uninstall --managed can be repeated
# once the cause is fixed. Sets TS_M_REMAINING to whatever could not be removed.
ts_m_remove_dataplane() {
    local i rel unit frag active paths known
    local -a files=()
    TS_M_REMAINING=()
    mapfile -t files < <(ts_m_fixed_files)
    for i in "${!TS_M_FILES[@]}"; do
        known=0
        for rel in "${files[@]}"; do
            if [[ "$rel" == "${TS_M_FILES[$i]}" ]]; then
                known=1
            fi
        done
        if [[ "$known" -eq 0 ]]; then
            files+=("${TS_M_FILES[$i]}")
        fi
    done
    # 0. The record says "removing" before anything is removed
    if [[ -f "${TS_FS_ROOT}${TS_M_INVENTORY}" ]]; then
        TS_M_INV_STATE="removing"
        TS_M_INV_REMAINING=()
        if ! ts_m_inventory_write; then
            TS_M_REMAINING+=("${TS_M_INVENTORY} could not be updated")
        fi
    fi
    # 1. Lightning drop-in, so the next start of the unit is outside the slice
    for rel in "${files[@]}"; do
        if [[ "$rel" == "${TS_M_UNIT_DIR}/"*.service.d/"${TS_M_DROPIN_NAME}" ]] && [[ "$rel" != *"${TS_M_WG_UNIT}.d/"* ]]; then
            rm -f "${TS_FS_ROOT}${rel}"
        fi
    done
    "$SYSTEMCTL_BIN" daemon-reload >/dev/null 2>&1 || true
    # 2. Units: the verifier timer and service first (no check runs during the removal), then the
    # tunnel, the kill switch (its ExecStop removes the attestation) and the slice
    for unit in "$TS_M_TIMER_UNIT" "$TS_M_VERIFIER_UNIT" "$TS_M_WG_UNIT" "$TS_M_KILLSWITCH_UNIT" "$TS_M_SLICE_UNIT"; do
        "$SYSTEMCTL_BIN" stop "$unit" >/dev/null 2>&1 || true
    done
    for unit in "${TS_M_ENABLED_UNITS[@]}"; do
        "$SYSTEMCTL_BIN" disable "$unit" >/dev/null 2>&1 || true
    done
    # 3. Kernel state and the emergency block (its records go only with the rules)
    if ts_m_lock; then
        if ! ts_m_killswitch_remove "${TS_M_INV_UID:-}"; then
            TS_M_REMAINING+=("$TS_M_ERROR")
        fi
        if [[ -n "${TS_M_INV_UID:-}" ]] && ts_m_emergency_present "$TS_M_INV_UID"; then
            if ! ts_m_emergency_release "$TS_M_INV_UID"; then
                TS_M_REMAINING+=("emergency rules at priority 21817-21819")
            fi
        elif ! ts_m_emergency_lan_release; then
            TS_M_REMAINING+=("emergency local network rules at priority ${TS_M_EMERGENCY_LAN_PRIO}")
        fi
        ts_m_unlock
    else
        TS_M_REMAINING+=("${TS_M_LOCK} could not be taken; kernel state not removed")
    fi
    # 4. Files except the script copy, runtime files except the emergency records, units reloaded
    for rel in "${files[@]}"; do
        if [[ "$rel" != "$TS_M_BIN" ]]; then
            if [[ "$TS_OPT_KEEP_CONFIG" -eq 1 ]] && [[ "$rel" == "$TS_M_WG_CONF" ]]; then
                continue
            fi
            rm -f "${TS_FS_ROOT}${rel}"
        fi
    done
    local ufw_m="${TS_FS_ROOT}/etc/wireguard/.tunnelsats-ufw-9735-${TS_M_IFACE}.created"
    if [[ -e "$ufw_m" ]] || [[ -L "$ufw_m" ]]; then
        if command -v ufw >/dev/null 2>&1; then
            if ufw delete allow in on "$TS_M_IFACE" to any port 9735 proto tcp >/dev/null 2>&1; then
                rm -f "$ufw_m"
            else
                TS_M_REMAINING+=("/etc/wireguard/.tunnelsats-ufw-9735-${TS_M_IFACE}.created")
            fi
        else
            rm -f "$ufw_m"
        fi
    fi
    rm -f "${TS_FS_ROOT}${TS_M_ATTEST}" "${TS_FS_ROOT}${TS_M_RULESET_FILE}" "${TS_FS_ROOT}${TS_M_VERIFIER_STATE}" "${TS_FS_ROOT}${TS_M_STOPPED}" "${TS_FS_ROOT}${TS_M_STOPPED}.tmp"
    "$SYSTEMCTL_BIN" daemon-reload >/dev/null 2>&1 || true
    for unit in "$TS_M_WG_UNIT" "$TS_M_TIMER_UNIT" "$TS_M_VERIFIER_UNIT" "$TS_M_KILLSWITCH_UNIT" "$TS_M_SLICE_UNIT"; do
        "$SYSTEMCTL_BIN" reset-failed "$unit" >/dev/null 2>&1 || true
    done
    # 5. Read back: no file left, systemd no longer knows the managed units, and the Lightning
    # unit no longer loads the drop-in (its next start is outside the slice)
    for rel in "${files[@]}"; do
        if [[ "$rel" != "$TS_M_BIN" ]] && [[ -e "${TS_FS_ROOT}${rel}" ]]; then
            if [[ "$TS_OPT_KEEP_CONFIG" -eq 1 ]] && [[ "$rel" == "$TS_M_WG_CONF" ]]; then
                continue
            fi
            TS_M_REMAINING+=("$rel")
        fi
    done
    for unit in "$TS_M_KILLSWITCH_UNIT" "$TS_M_TIMER_UNIT" "$TS_M_WG_UNIT"; do
        for rel in "${TS_FS_ROOT}${TS_M_UNIT_DIR}"/*.wants/"$unit"; do
            if [[ -L "$rel" ]] || [[ -e "$rel" ]]; then
                TS_M_REMAINING+=("${rel#"$TS_FS_ROOT"}")
            fi
        done
    done
    # systemd loads a slice even without a unit file (LoadState stays "loaded"), so the test is
    # "no unit file and inactive" rather than LoadState=not-found
    for unit in "$TS_M_SLICE_UNIT" "$TS_M_KILLSWITCH_UNIT" "$TS_M_VERIFIER_UNIT" "$TS_M_TIMER_UNIT"; do
        frag=$(ts_m_unit_prop "$unit" FragmentPath)
        active=$(ts_m_unit_prop "$unit" ActiveState)
        if [[ -n "$frag" ]] || [[ "$active" != "inactive" ]]; then
            TS_M_REMAINING+=("${unit} (systemd: ${frag:-no unit file}, ${active:-state unknown})")
        fi
    done
    if [[ -n "${TS_M_INV_UNIT:-}" ]]; then
        paths=$(ts_m_unit_prop "$TS_M_INV_UNIT" DropInPaths)
        if [[ "$paths" == *"/${TS_M_DROPIN_NAME}"* ]]; then
            TS_M_REMAINING+=("${TS_M_INV_UNIT} still loads ${TS_M_DROPIN_NAME}")
        fi
    fi
    if [[ ${#TS_M_REMAINING[@]} -gt 0 ]]; then
        ts_m_keep_removal_record
        return 0
    fi
    # 6. Nothing else remains: the script copy, then the record and the directories install created
    # (only if empty by now, newest first)
    rm -f "${TS_FS_ROOT}${TS_M_BIN}"
    if [[ -e "${TS_FS_ROOT}${TS_M_BIN}" ]]; then
        TS_M_REMAINING+=("$TS_M_BIN")
        ts_m_keep_removal_record
        return 0
    fi
    rm -f "${TS_FS_ROOT}${TS_M_INVENTORY}"
    for (( i = ${#TS_M_CREATED_DIRS[@]} - 1; i >= 0; i-- )); do
        if [[ "$TS_OPT_KEEP_CONFIG" -eq 1 ]] && [[ "${TS_M_CREATED_DIRS[$i]}" == "$TS_M_WG_DIR" ]]; then
            continue
        fi
        rmdir "${TS_FS_ROOT}${TS_M_CREATED_DIRS[$i]}" 2>/dev/null || true
    done
    if [[ -e "${TS_FS_ROOT}${TS_M_INVENTORY}" ]]; then
        TS_M_REMAINING+=("$TS_M_INVENTORY")
        return 0
    fi
    # 7. Runtime state last, the lifecycle lock file with it: no other install or uninstall can take
    # a fresh lock while this removal still runs
    rm -rf "${TS_FS_ROOT}${TS_M_RUN_DIR}"
    return 0
}

TS_M_ROLLBACK_ARMED=0
TS_M_TMP_DIR=""
TS_M_ADOPT_BACKUP=""
TS_M_ADOPT_ORIG_CONF=""

# EXIT trap of install/adopt --managed: removes the temporary copy of the config (it holds the
# private key) and, after a failure, everything the install created so far. For adopt --managed,
# restores the original WireGuard config from TS_M_ADOPT_BACKUP if it was backed up. Keeps the JSON contract.
ts_m_install_exit_trap() {
    local rc=$?
    trap - EXIT
    if [[ "$rc" -ne 0 ]] && [[ "$TS_M_ROLLBACK_ARMED" -eq 1 ]]; then
        print_warning "Install failed; removing what it created so far..."
        ts_m_remove_dataplane
        if [[ ${#TS_M_REMAINING[@]} -gt 0 ]]; then
            print_error "Could not remove: ${TS_M_REMAINING[*]}. The inventory keeps the record: fix the cause, then run 'tunnelsats.sh uninstall --managed'."
        fi
    fi
    if [[ "$rc" -ne 0 ]] && [[ -n "$TS_M_ADOPT_BACKUP" ]] && [[ -f "$TS_M_ADOPT_BACKUP" ]]; then
        if [[ -n "$TS_M_ADOPT_ORIG_CONF" ]]; then
            mkdir -p "$(dirname "$TS_M_ADOPT_ORIG_CONF")" 2>/dev/null || true
            mv -f "$TS_M_ADOPT_BACKUP" "$TS_M_ADOPT_ORIG_CONF" 2>/dev/null || true
            chmod 0600 "$TS_M_ADOPT_ORIG_CONF" 2>/dev/null || true
            print_warning "Adopt did not complete: ${TS_M_ADOPT_ORIG_CONF} is restored, and ${TS_M_UNIT} stays stopped and disabled because the legacy tunnel setup may already be removed. Fix the cause and run adopt again; enable ${TS_M_UNIT} only once it is tunneled again or its TunnelSats clearnet settings are removed."
        else
            rm -f "$TS_M_ADOPT_BACKUP" 2>/dev/null || true
        fi
    elif [[ -n "$TS_M_ADOPT_BACKUP" ]]; then
        rm -f "$TS_M_ADOPT_BACKUP" 2>/dev/null || true
    fi
    if [[ -n "$TS_M_TMP_DIR" ]]; then
        rm -rf "$TS_M_TMP_DIR"
    fi
    if [[ "$rc" -ne 0 ]]; then
        ts_m_lifecycle_cleanup
    fi
    if [[ "$TS_JSON" -eq 1 ]] && [[ "$TS_JSON_EMITTED" -ne 1 ]]; then
        if [[ "$rc" -eq 0 ]]; then
            rc=1
        fi
        ts_j_error E_INTERNAL internal "'${TS_COMMAND}' ended without a result (exit code ${rc})"
        ts_json_document "$rc" "[${TS_R}]"
    fi
    exit "$rc"
}

# Fails the install after changes started (the EXIT trap rolls them back). $1 = error code, $2 = message.
ts_m_install_abort() {
    ts_fail 1 "$1" operational "$2"
}

# Succeeds if install has to restart the Lightning unit to move it into the slice, given its
# ActiveState $1 and SubState $2: it runs, starts, reloads or stops outside the slice. A unit that is
# not running is never started. On RaspiBlitz, a unit that waits for its next automatic restart
# (SubState auto-restart, for example while a start guard holds it back) is left to that restart,
# which runs inside the slice and behind the kill switch.
ts_m_ln_restart_needed() {
    case "$1" in
        active|reloading|deactivating) return 0 ;;
        activating)
            if [[ "$TS_OPT_PROFILE" == "raspiblitz" ]] && [[ "$2" == auto-restart* ]]; then
                return 1
            fi
            return 0
            ;;
    esac
    return 1
}

cmd_install_managed() {
    local answer="" ln_was_active=0 ln_restarted=0 tunnel_started=0 rc=0 out
    ts_m_require_root
    case "$TS_OPT_PROFILE" in
        baremetal|raspiblitz|mynode) ;;
        umbrel)
            ts_fail 7 E_PROFILE_UNSUPPORTED refused "Managed mode supports the baremetal, raspiblitz and mynode profiles only for now (requested: ${TS_OPT_PROFILE})"
            ;;
        *) ts_usage_error "--managed requires a profile for install (baremetal, raspiblitz or mynode)" ;;
    esac
    ts_m_lifecycle_lock
    if [[ "$TS_JSON" -ne 1 ]]; then
        print_header "Managed Install (preview)"
    fi
    trap ts_m_install_exit_trap EXIT
    ts_m_install_preflight
    ts_m_install_validate_config
    if command -v "$NFT_BIN" >/dev/null 2>&1 && command -v "$UNSHARE_BIN" >/dev/null 2>&1; then
        ts_m_capability_probe
    fi
    print_info "Platform: ${TS_OPT_PROFILE}, Lightning: ${TS_M_UNIT} (user ${TS_M_USER}), uid backstop: $([[ "$TS_OPT_UID_BACKSTOP" -eq 1 ]] && echo on || echo off)"
    if [[ ${#TS_M_OTHER_UNITS[@]} -gt 0 ]]; then
        print_warning "Also installed: ${TS_M_OTHER_UNITS[*]}. Managed mode tunnels ${TS_M_UNIT} only; the other units are not tunneled."
    fi
    ts_confirm answer "Install the managed dataplane and restart ${TS_M_UNIT} inside ${TS_M_SLICE}? [y/N]: "
    if [[ ! "$answer" =~ ^[Yy] ]]; then
        ts_fail 1 E_ABORTED operational "Install aborted; nothing was changed"
    fi
    ts_m_install_packages
    ts_m_check_tools
    ts_m_capability_probe

    TS_M_INV_PROFILE="$TS_OPT_PROFILE"
    TS_M_INV_IMPL="$TS_M_IMPL"
    TS_M_INV_UNIT="$TS_M_UNIT"
    TS_M_INV_USER="$TS_M_USER"
    TS_M_INV_UID="$TS_M_UID"
    TS_M_INV_BACKSTOP="$TS_OPT_UID_BACKSTOP"
    TS_M_FILES=()
    TS_M_FILE_SHA=()
    TS_M_CREATED_DIRS=()
    TS_M_ENABLED_UNITS=()
    TS_M_ROLLBACK_ARMED=1

    # Write-ahead: the inventory (state "installing") is on disk before the first change and is
    # updated before each further one, so an interrupted install leaves a complete record
    print_info "Writing units, drop-ins and the tunnel config..."
    if ! ts_m_install_files; then
        ts_m_install_abort E_WRITE_FAILED "Writing the managed files failed"
    fi
    rm -rf "$TS_M_TMP_DIR"
    TS_M_TMP_DIR=""
    if ! "$SYSTEMCTL_BIN" daemon-reload; then
        ts_m_install_abort E_SYSTEMD "systemctl daemon-reload failed"
    fi
    for out in "$TS_M_KILLSWITCH_UNIT" "$TS_M_TIMER_UNIT" "$TS_M_WG_UNIT"; do
        TS_M_ENABLED_UNITS+=("$out")
        if ! ts_m_inventory_write; then
            ts_m_install_abort E_WRITE_FAILED "Writing the inventory failed"
        fi
        if ! "$SYSTEMCTL_BIN" enable "$out" >/dev/null 2>&1; then
            ts_m_install_abort E_SYSTEMD "systemctl enable ${out} failed"
        fi
    done
    # Units start only once the inventory says "installed"
    TS_M_INV_STATE="installed"
    if ! ts_m_inventory_write; then
        ts_m_install_abort E_WRITE_FAILED "Writing the inventory failed"
    fi

    print_info "Arming the kill switch..."
    if ! "$SYSTEMCTL_BIN" start "$TS_M_KILLSWITCH_UNIT"; then
        ts_m_install_abort E_KILLSWITCH "The kill switch could not be armed (see: journalctl -u ${TS_M_KILLSWITCH_UNIT})"
    fi
    ts_m_read_attestation
    if [[ "$TS_M_ATT_STATUS" != "valid" ]]; then
        ts_m_install_abort E_KILLSWITCH "The kill switch unit ran, but the attestation is ${TS_M_ATT_STATUS//_/ }"
    fi
    print_success "Kill switch armed and attested"

    print_info "Starting the tunnel..."
    if "$SYSTEMCTL_BIN" start "$TS_M_WG_UNIT"; then
        tunnel_started=1
        print_success "${TS_M_WG_UNIT} started"
    else
        print_warning "${TS_M_WG_UNIT} did not start yet; it retries every 30 s and the kill switch blocks clearnet traffic meanwhile"
    fi
    local ln_state ln_sub=""
    ln_state=$(ts_m_unit_prop "$TS_M_UNIT" ActiveState)
    if [[ "$ln_state" == "activating" ]] && [[ "$TS_OPT_PROFILE" == "raspiblitz" ]]; then
        ln_sub=$(ts_m_unit_prop "$TS_M_UNIT" SubState)
    fi
    if ts_m_ln_restart_needed "$ln_state" "$ln_sub"; then
        ln_was_active=1
        print_info "Restarting ${TS_M_UNIT} inside ${TS_M_SLICE}..."
        if "$SYSTEMCTL_BIN" restart "$TS_M_UNIT"; then
            ln_restarted=1
        else
            rc=1
            print_error "${TS_M_UNIT} did not restart; the managed dataplane stays installed (see: journalctl -u ${TS_M_UNIT})"
        fi
    elif [[ "$ln_state" == "activating" ]]; then
        print_info "${TS_M_UNIT} waits for its next automatic restart (${ln_sub}); that start runs inside ${TS_M_SLICE}"
    else
        print_info "${TS_M_UNIT} is not running (${ln_state:-state unknown}); install does not start it, and its next start runs inside ${TS_M_SLICE}"
    fi
    if ! "$SYSTEMCTL_BIN" start "$TS_M_TIMER_UNIT"; then
        rc=1
        print_error "${TS_M_TIMER_UNIT} did not start"
    fi
    TS_M_ROLLBACK_ARMED=0
    trap - EXIT
    if [[ "$TS_JSON" -eq 1 ]]; then
        trap ts_json_exit_guard EXIT
    fi

    ts_m_node_config_clearnet "$TS_M_IMPL" "$TS_M_UNIT" "$TS_OPT_PROFILE"
    if [[ "$TS_JSON" -eq 1 ]]; then
        local errors="[]" items=() other_j
        if [[ "$rc" -ne 0 ]]; then
            ts_j_error E_PARTIAL operational "Installed, but ${TS_M_UNIT} or ${TS_M_TIMER_UNIT} did not start"
            errors="[${TS_R}]"
        fi
        for out in "${TS_M_OTHER_UNITS[@]}"; do
            ts_j_str "$out"
            items+=("$TS_R")
        done
        ts_j_arr "${items[@]}"
        other_j="$TS_R"
        ts_j_obj b:managed true s:profile "$TS_OPT_PROFILE" s:impl "$TS_M_IMPL" s:unit "$TS_M_UNIT" s:node_user "$TS_M_USER" \
            b:uid_backstop "$TS_OPT_UID_BACKSTOP" s:iface "$TS_M_IFACE" s:slice "$TS_M_SLICE" \
            b:tunnel_started "$tunnel_started" b:ln_was_active "$ln_was_active" b:ln_restarted "$ln_restarted" \
            s:node_config "$TS_M_NC_STATUS" r:other_ln_units "$other_j"
        ts_json_document "$rc" "$errors" "${TS_R:1:${#TS_R}-2}"
        exit "$rc"
    fi
    echo ""
    print_line
    print_success "Managed dataplane installed (preview)"
    print_line
    echo ""
    echo "Check it at any time with: sudo tunnelsats verify"
    echo ""
    if [[ "$TS_M_NC_STATUS" != "clearnet" ]]; then
        local vpn_dns vpn_port
        vpn_dns=$(sed -nE 's/^[[:space:]]*Endpoint[[:space:]]*=[[:space:]]*([^:[:space:]]+):.*/\1/Ip' "${TS_FS_ROOT}${TS_M_WG_CONF}" | head -n 1)
        vpn_port=$(ts_config_vpn_port "${TS_FS_ROOT}${TS_M_WG_CONF}")
        echo -e "${BOLD}Next: add the hybrid settings to your node configuration, then restart ${TS_M_UNIT}:${NC}"
        echo ""
        # On RaspiBlitz the config file depends on the chain (tlnd.conf, testnet/config): name the
        # file the unit reads
        local conf_file=""
        if [[ "$TS_OPT_PROFILE" == "raspiblitz" ]]; then
            conf_file="${TS_M_NC_FILES[0]:-}"
        fi
        LN_IMPL="$TS_M_IMPL" PLATFORM="$TS_OPT_PROFILE" node_user="$TS_M_USER" TS_NODE_CONF_FILE="$conf_file" \
            print_node_config_instructions "$vpn_dns" "$vpn_port" "install"
        echo ""
        echo "   sudo systemctl restart ${TS_M_UNIT}"
        echo ""
    fi
    exit "$rc"
}

TS_M_ADOPT_KIND=""

# Every check that can refuse adopt --managed before anything changes.
ts_m_adopt_preflight() {
    local guess existing kind evidence found listing line ports p port_ok=0 fam profile="${TS_OPT_PROFILE:-baremetal}"
    local wg_rel="${WG_DIR:-/etc/wireguard}"
    wg_rel="${wg_rel#"$TS_FS_ROOT"}"
    [[ -z "$wg_rel" ]] && wg_rel="/etc/wireguard"
    guess=$(ts_guess_platform "$TS_FS_ROOT")
    if [[ -n "$TS_OPT_PLATFORM" ]] && [[ "$TS_OPT_PLATFORM" != "$profile" ]]; then
        ts_fail 7 E_PLATFORM_UNSUPPORTED refused "--platform ${TS_OPT_PLATFORM} does not match the managed profile ${profile}"
    fi
    case "$profile:$guess" in
        baremetal:|raspiblitz:raspiblitz|mynode:mynode) ;;
        baremetal:raspiblitz)
            ts_fail 7 E_PLATFORM_UNSUPPORTED refused "This node is a RaspiBlitz: use 'adopt --managed raspiblitz --impl lnd|cln'"
            ;;
        baremetal:mynode)
            ts_fail 7 E_PLATFORM_UNSUPPORTED refused "This node is a myNode: use 'adopt --managed mynode'"
            ;;
        raspiblitz:*)
            ts_fail 7 E_PLATFORM_UNSUPPORTED refused "The raspiblitz profile needs a RaspiBlitz (detected: ${guess:-no RaspiBlitz})"
            ;;
        mynode:*)
            ts_fail 7 E_PLATFORM_UNSUPPORTED refused "The mynode profile needs a myNode (detected: ${guess:-no myNode})"
            ;;
        *)
            ts_fail 7 E_PLATFORM_UNSUPPORTED refused "Managed mode supports bare-metal systemd nodes, RaspiBlitz and myNode only for now (detected: ${guess})"
            ;;
    esac
    if [[ ! -d "${TS_FS_ROOT}/run/systemd/system" ]]; then
        ts_fail 6 E_SYSTEMD_MISSING capability "systemd is not running as PID 1"
    fi
    if ! ts_m_cgroup2_unified; then
        ts_fail 6 E_CGROUP_V2_MISSING capability "A unified cgroup v2 hierarchy at ${TS_M_CGROUP_ROOT} is required"
    fi
    if ! command -v "$PERL_BIN" >/dev/null 2>&1; then
        ts_fail 6 E_DEPENDENCY_MISSING capability "perl is missing; verify's kill switch and IPv6 probes need it (Debian and Ubuntu ship it as perl-base)"
    fi
    if ts_m_inventory_present; then
        ts_fail 7 E_MANAGED_PRESENT refused "A managed install already exists (complete, interrupted or partly removed); run 'tunnelsats.sh uninstall --managed' first"
    fi
    existing=$(ts_m_existing_install) || existing="unknown||"
    kind="${existing%%|*}"
    existing="${existing#*|}"
    evidence="${existing%%|*}"
    found="${existing#*|}"
    if [[ "$kind" == "unknown" ]] && [[ " $evidence " == *" managed_artifacts "* ]]; then
        ts_fail 7 E_MANAGED_PRESENT refused "Managed artifacts already exist (${found:-managed_artifacts}); run 'tunnelsats.sh uninstall --managed --legacy-artifacts' first"
    fi
    if [[ -z "$CONFIG_FILE" ]]; then
        ts_select_wg_config "" "$TS_FS_ROOT" "$wg_rel"
        case "$TS_WG_SELECTION" in
            canonical|single) CONFIG_FILE="${TS_FS_ROOT}${TS_WG_SELECTED}" ;;
            ambiguous)
                ts_fail 8 E_CONFIG_INVALID input "Multiple WireGuard configs found in ${wg_rel} (${TS_WG_CANDIDATES[*]}); pass the one to adopt with --config"
                ;;
        esac
    fi
    if [[ "$kind" == "none" ]] && [[ -z "$CONFIG_FILE" ]]; then
        ts_fail 3 E_NOT_INSTALLED state "No existing TunnelSats install found to adopt"
    fi
    if [[ -z "$CONFIG_FILE" ]] || [[ ! -f "$CONFIG_FILE" ]]; then
        ts_fail 8 E_CONFIG_INVALID input "WireGuard config not found: ${CONFIG_FILE:-none}"
    fi
    TS_M_ADOPT_KIND="$kind"
    ts_m_select_ln_unit
    ts_m_select_ln_user
    listing=$("$IP_BIN" route show table 52 2>&1) || listing=""
    if printf '%s\n' "$listing" | grep -qE '^(default|0\.0\.0\.0/0)[[:space:]]'; then
        ts_fail 7 E_TAILSCALE_EXIT_NODE refused "A Tailscale exit node is active (default route in table 52); its rules come before the TunnelSats rules"
    fi
    for fam in 4 6; do
        if [[ "$fam" == "6" ]] && ! ts_m_ipv6_available; then
            continue
        fi
        if ! listing=$(ts_m_table_routes "$fam"); then
            ts_fail 1 E_KERNEL_STATE operational "IPv${fam} routing table ${TS_M_RT_TABLE} cannot be read"
        fi
        if [[ -n "$listing" ]]; then
            if [[ "$fam" == "6" ]]; then
                ts_fail 7 E_TABLE_51820_IN_USE refused "IPv6 routing table ${TS_M_RT_TABLE} is in use: ${listing%%$'\n'*}"
            fi
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                if ! [[ "$line" =~ ^blackhole[[:space:]]+default[[:space:]]+metric[[:space:]]+3([[:space:]]|$) ]] && \
                    ! [[ "$line" =~ ^default[[:space:]]+dev[[:space:]]+tunnelsats[A-Za-z0-9_.-]*([[:space:]]|$) ]]; then
                    ts_fail 7 E_TABLE_51820_IN_USE refused "IPv4 routing table ${TS_M_RT_TABLE} has a non-TunnelSats route: ${line}"
                fi
            done < <(printf '%s\n' "$listing")
        fi
        if ! listing=$("$IP_BIN" "-${fam}" rule show 2>/dev/null); then
            ts_fail 1 E_KERNEL_STATE operational "IPv${fam} policy rules cannot be read"
        fi
        while IFS= read -r line; do
            case "$line" in
                21818:*|21819:*|21820:*|21821:*|21822:*)
                    if [[ "$fam" == "6" ]]; then
                        case "$line" in
                            21819:*blackhole*|21819:*unreachable*)
                                local fc6_sel=""
                                if [[ "$line" =~ ^21819:[[:space:]]+from[[:space:]]+all[[:space:]]+uidrange[[:space:]]+([0-9]+-[0-9]+)[[:space:]]+(blackhole|unreachable)([[:space:]]|$) ]]; then
                                    fc6_sel="${BASH_REMATCH[1]}"
                                fi
                                if [[ -z "$fc6_sel" ]] || [[ ! -f "${TS_FS_ROOT}${wg_rel}/.tunnelsats-failclosed-rules" ]] || \
                                    ! grep -qxF "uidrange6 ${fc6_sel}" "${TS_FS_ROOT}${wg_rel}/.tunnelsats-failclosed-rules" 2>/dev/null; then
                                    ts_fail 7 E_RULE_PRIORITY_IN_USE refused "IPv6 policy rule priority ${line%%:*} is in use: ${line}"
                                fi
                                ;;
                            *)
                                ts_fail 7 E_RULE_PRIORITY_IN_USE refused "IPv6 policy rule priority ${line%%:*} is in use: ${line}"
                                ;;
                        esac
                        continue
                    fi
                    case "$line" in
                        21820:*lookup[[:space:]]main[[:space:]]suppress_prefixlength[[:space:]]0*) ;;
                        21821:*0x1000000*lookup[[:space:]]51820*|21821:*uidrange*lookup[[:space:]]51820*) ;;
                        21818:*blackhole*|21818:*unreachable*)
                            local fc_sel=""
                            if [[ "$line" =~ ^21818:[[:space:]]+from[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+)[[:space:]]+(blackhole|unreachable)([[:space:]]|$) ]]; then
                                fc_sel="from ${BASH_REMATCH[1]}"
                            fi
                            if [[ -z "$fc_sel" ]] || [[ ! -f "${TS_FS_ROOT}${wg_rel}/.tunnelsats-failclosed-rules" ]] || \
                                ! grep -qxF "$fc_sel" "${TS_FS_ROOT}${wg_rel}/.tunnelsats-failclosed-rules" 2>/dev/null; then
                                ts_fail 7 E_RULE_PRIORITY_IN_USE refused "IPv4 policy rule priority ${line%%:*} is in use: ${line}"
                            fi
                            ;;
                        21819:*blackhole*|21819:*unreachable*)
                            local fc_sel=""
                            if [[ "$line" =~ ^21819:[[:space:]]+from[[:space:]]+all[[:space:]]+uidrange[[:space:]]+([0-9]+-[0-9]+)[[:space:]]+(blackhole|unreachable)([[:space:]]|$) ]]; then
                                fc_sel="uidrange ${BASH_REMATCH[1]}"
                            fi
                            if [[ -z "$fc_sel" ]] || [[ ! -f "${TS_FS_ROOT}${wg_rel}/.tunnelsats-failclosed-rules" ]] || \
                                ! grep -qxF "$fc_sel" "${TS_FS_ROOT}${wg_rel}/.tunnelsats-failclosed-rules" 2>/dev/null; then
                                ts_fail 7 E_RULE_PRIORITY_IN_USE refused "IPv4 policy rule priority ${line%%:*} is in use: ${line}"
                            fi
                            ;;
                        *)
                            ts_fail 7 E_RULE_PRIORITY_IN_USE refused "IPv4 policy rule priority ${line%%:*} is in use: ${line}"
                            ;;
                    esac
                    ;;
            esac
        done < <(printf '%s\n' "$listing")
    done
    ports=$(ts_m_node_config_listen_ports "$TS_M_IMPL" "$TS_M_UNIT")
    if [[ -n "$ports" ]]; then
        for p in $ports; do
            if [[ "$p" == "$TS_M_LN_PORT" ]]; then
                port_ok=1
            fi
        done
        if [[ "$port_ok" -eq 0 ]]; then
            ts_fail 7 E_LN_PORT refused "Lightning listens on port(s) $(echo $ports); the TunnelSats server forwards to ${TS_M_LN_PORT}"
        fi
    fi
    if [[ ! -f "$TS_SCRIPT_PATH" ]] || [[ ! -r "$TS_SCRIPT_PATH" ]]; then
        ts_fail 2 E_USAGE usage "Run tunnelsats.sh from a file (not through a pipe): managed mode installs a copy of it"
    fi
    return 0
}

cmd_adopt_managed() {
    local answer="" ln_was_active=0 ln_was_enabled=0 ln_ufile_state="" ln_restarted=0 tunnel_started=0 rc=0 out fam listing line
    local -a unit_edits=()
    local unit_reverted=0
    local wg_rel="${WG_DIR:-/etc/wireguard}"
    wg_rel="${wg_rel#"$TS_FS_ROOT"}"
    [[ -z "$wg_rel" ]] && wg_rel="/etc/wireguard"
    local wg_full="${TS_FS_ROOT}${wg_rel}"
    ts_m_require_root
    case "$TS_OPT_PROFILE" in
        baremetal|raspiblitz|mynode) ;;
        umbrel)
            ts_fail 7 E_PROFILE_UNSUPPORTED refused "Managed mode supports the baremetal, raspiblitz and mynode profiles only for now (requested: ${TS_OPT_PROFILE})"
            ;;
        *) ts_usage_error "--managed requires a profile for adopt (baremetal, raspiblitz or mynode)" ;;
    esac
    ts_m_lifecycle_lock
    if [[ "$TS_JSON" -ne 1 ]]; then
        print_header "Managed Adopt"
    fi
    trap ts_m_install_exit_trap EXIT
    ts_m_adopt_preflight
    ts_m_install_validate_config
    if command -v "$NFT_BIN" >/dev/null 2>&1 && command -v "$UNSHARE_BIN" >/dev/null 2>&1; then
        ts_m_capability_probe
    fi
    print_info "Adopting ${TS_M_ADOPT_KIND} install into managed mode (${TS_OPT_PROFILE}, ${TS_M_UNIT}, user ${TS_M_USER})"
    if [[ ${#TS_M_OTHER_UNITS[@]} -gt 0 ]]; then
        print_warning "Also installed: ${TS_M_OTHER_UNITS[*]}. Managed mode tunnels ${TS_M_UNIT} only; the other units are not tunneled."
    fi
    ts_confirm answer "Replace the existing ${TS_M_ADOPT_KIND} install with the managed dataplane for ${TS_M_UNIT}? [y/N]: "
    if [[ ! "$answer" =~ ^[Yy] ]]; then
        ts_fail 1 E_ABORTED operational "Adopt aborted; nothing was changed"
    fi
    ts_m_install_packages
    ts_m_check_tools
    ts_m_capability_probe

    # 1. Stop the Lightning unit FIRST while the legacy tunnel/killswitch is still active so the
    # daemon never runs without tunnel routing (or triggers an auto-restart timer) during legacy teardown
    local ln_state
    ln_state=$(ts_m_unit_prop "$TS_M_UNIT" ActiveState)
    case "$ln_state" in
        inactive|failed|"") ;;
        *)
            ln_was_active=1
            print_info "Stopping ${TS_M_UNIT} before removing legacy artifacts..."
            if ! "$SYSTEMCTL_BIN" stop "$TS_M_UNIT"; then
                ts_fail 1 E_LN_STOP operational "Could not stop ${TS_M_UNIT} before removing legacy artifacts"
            fi
            ln_state=$(ts_m_unit_prop "$TS_M_UNIT" ActiveState)
            case "$ln_state" in
                inactive|failed) ;;
                *)
                    ts_fail 1 E_LN_STOP operational "${TS_M_UNIT} is still ${ln_state:-active} after systemctl stop"
                    ;;
            esac
            ;;
    esac

    # Disable the Lightning unit before legacy teardown so a failed adopt cannot leave it enabled
    # with clearnet settings outside any tunnel on the next boot; re-enabled once the kill switch is armed
    ln_ufile_state=$(ts_m_unit_prop "$TS_M_UNIT" UnitFileState)
    if [[ "$ln_ufile_state" != "disabled" ]]; then
        if [[ "$ln_ufile_state" == "enabled"* ]] || [[ "$ln_was_active" -eq 1 ]]; then
            ln_was_enabled=1
        fi
        if ! "$SYSTEMCTL_BIN" disable "$TS_M_UNIT" >/dev/null 2>&1; then
            ts_fail 1 E_LN_DISABLE operational "Could not disable ${TS_M_UNIT} before removing legacy artifacts"
        fi
    fi

    # Back up the original WireGuard config so ts_m_install_exit_trap can restore it if adopt fails
    TS_M_ADOPT_ORIG_CONF="$CONFIG_FILE"
    TS_M_ADOPT_BACKUP="${TS_M_TMP_DIR}/adopt-orig-wg.conf"
    if ! cp -f "$CONFIG_FILE" "$TS_M_ADOPT_BACKUP" 2>/dev/null; then
        TS_M_ADOPT_BACKUP=""
        ts_fail 1 E_WRITE_FAILED operational "Could not back up ${CONFIG_FILE} before adopt"
    fi
    chmod 0600 "$TS_M_ADOPT_BACKUP" 2>/dev/null || true

    # 2. Revert legacy in-place edits on the guarded unit (never restoring from stale .service.bak)
    # and clean all legacy artifacts while keeping WireGuard configs on disk until step 4 succeeds
    ts_m_revert_legacy_unit_edits "/etc/systemd/system/${TS_M_UNIT}" || true
    unit_edits=("${TS_M_UNIT_EDITS_FOUND[@]}")
    unit_reverted="$TS_M_UNIT_REVERTED"
    TS_OPT_KEEP_CONFIG=1 ts_m_clean_legacy_artifacts
    local legacy_remaining=("${TS_M_REMAINING[@]}")
    if [[ "$unit_reverted" -eq 1 ]] && [[ " ${TS_M_LEGACY_REMOVED[*]} " != *" /etc/systemd/system/${TS_M_UNIT} "* ]]; then
        TS_M_LEGACY_REMOVED=("/etc/systemd/system/${TS_M_UNIT}" "${TS_M_LEGACY_REMOVED[@]}")
    fi

    # 3. Verify that routing table 51820 and rule priorities 21818-21822 are now empty
    for fam in 4 6; do
        if [[ "$fam" == "6" ]] && ! ts_m_ipv6_available; then
            continue
        fi
        if ! listing=$(ts_m_table_routes "$fam"); then
            ts_fail 1 E_KERNEL_STATE operational "IPv${fam} routing table ${TS_M_RT_TABLE} cannot be read"
        fi
        if [[ -n "$listing" ]]; then
            ts_fail 7 E_TABLE_51820_IN_USE refused "IPv${fam} routing table ${TS_M_RT_TABLE} is still in use after legacy cleanup: ${listing%%$'\n'*}"
        fi
        if ! listing=$("$IP_BIN" "-${fam}" rule show 2>/dev/null); then
            ts_fail 1 E_KERNEL_STATE operational "IPv${fam} policy rules cannot be read"
        fi
        while IFS= read -r line; do
            case "$line" in
                21818:*|21819:*|21820:*|21821:*|21822:*)
                    ts_fail 7 E_RULE_PRIORITY_IN_USE refused "IPv${fam} policy rule priority ${line%%:*} is still in use after legacy cleanup: ${line}"
                    ;;
            esac
        done < <(printf '%s\n' "$listing")
    done

    # 4. Install the managed dataplane
    TS_M_INV_PROFILE="$TS_OPT_PROFILE"
    TS_M_INV_IMPL="$TS_M_IMPL"
    TS_M_INV_UNIT="$TS_M_UNIT"
    TS_M_INV_USER="$TS_M_USER"
    TS_M_INV_UID="$TS_M_UID"
    TS_M_INV_BACKSTOP="$TS_OPT_UID_BACKSTOP"
    TS_M_FILES=()
    TS_M_FILE_SHA=()
    TS_M_CREATED_DIRS=()
    TS_M_ENABLED_UNITS=()
    TS_M_ROLLBACK_ARMED=1

    print_info "Writing units, drop-ins and the tunnel config..."
    if ! ts_m_install_files; then
        ts_m_install_abort E_WRITE_FAILED "Writing the managed files failed"
    fi
    if ! "$SYSTEMCTL_BIN" daemon-reload; then
        ts_m_install_abort E_SYSTEMD "systemctl daemon-reload failed"
    fi
    for out in "$TS_M_KILLSWITCH_UNIT" "$TS_M_TIMER_UNIT" "$TS_M_WG_UNIT"; do
        TS_M_ENABLED_UNITS+=("$out")
        if ! ts_m_inventory_write; then
            ts_m_install_abort E_WRITE_FAILED "Writing the inventory failed"
        fi
        if ! "$SYSTEMCTL_BIN" enable "$out" >/dev/null 2>&1; then
            ts_m_install_abort E_SYSTEMD "systemctl enable ${out} failed"
        fi
    done
    TS_M_INV_STATE="installed"
    if ! ts_m_inventory_write; then
        ts_m_install_abort E_WRITE_FAILED "Writing the inventory failed"
    fi

    print_info "Arming the kill switch..."
    if ! "$SYSTEMCTL_BIN" start "$TS_M_KILLSWITCH_UNIT"; then
        ts_m_install_abort E_KILLSWITCH "The kill switch could not be armed (see: journalctl -u ${TS_M_KILLSWITCH_UNIT})"
    fi
    ts_m_read_attestation
    if [[ "$TS_M_ATT_STATUS" != "valid" ]]; then
        ts_m_install_abort E_KILLSWITCH "The kill switch unit ran, but the attestation is ${TS_M_ATT_STATUS//_/ }"
    fi
    print_success "Kill switch armed and attested"

    # Managed dataplane is armed: remove the adopt backup and any non-canonical legacy tunnelsats-*.conf files
    rm -rf "$TS_M_TMP_DIR"
    TS_M_TMP_DIR=""
    TS_M_ADOPT_BACKUP=""
    TS_M_ADOPT_ORIG_CONF=""
    for out in "$wg_full"/tunnelsats-*.conf; do
        if [[ -e "$out" ]] || [[ -L "$out" ]]; then
            if [[ "$out" != "${TS_FS_ROOT}${TS_M_WG_CONF}" ]]; then
                if rm -f "$out" 2>/dev/null; then
                    TS_M_LEGACY_REMOVED+=("${out#"$TS_FS_ROOT"}")
                else
                    legacy_remaining+=("${out#"$TS_FS_ROOT"}")
                fi
            fi
        fi
    done
    if [[ ${#legacy_remaining[@]} -gt 0 ]]; then
        print_warning "Could not remove legacy artifacts: ${legacy_remaining[*]}"
    fi

    if [[ "$ln_was_enabled" -eq 1 ]]; then
        if ! "$SYSTEMCTL_BIN" enable "$TS_M_UNIT" >/dev/null 2>&1; then
            rc=1
            print_error "${TS_M_UNIT} could not be re-enabled"
        fi
    fi

    print_info "Starting the tunnel..."
    if "$SYSTEMCTL_BIN" start "$TS_M_WG_UNIT"; then
        tunnel_started=1
        print_success "${TS_M_WG_UNIT} started"
    else
        print_warning "${TS_M_WG_UNIT} did not start yet; it retries every 30 s and the kill switch blocks clearnet traffic meanwhile"
    fi
    if [[ "$ln_was_active" -eq 1 ]]; then
        print_info "Starting ${TS_M_UNIT} inside ${TS_M_SLICE}..."
        if "$SYSTEMCTL_BIN" start "$TS_M_UNIT"; then
            ln_restarted=1
        else
            rc=1
            print_error "${TS_M_UNIT} did not start; the managed dataplane stays installed (see: journalctl -u ${TS_M_UNIT})"
        fi
    else
        print_info "${TS_M_UNIT} was not running; adopt does not start it, and its next start runs inside ${TS_M_SLICE}"
    fi
    if ! "$SYSTEMCTL_BIN" start "$TS_M_TIMER_UNIT"; then
        rc=1
        print_error "${TS_M_TIMER_UNIT} did not start"
    fi
    TS_M_ROLLBACK_ARMED=0
    trap - EXIT
    if [[ "$TS_JSON" -eq 1 ]]; then
        trap ts_json_exit_guard EXIT
    fi

    ts_m_node_config_clearnet "$TS_M_IMPL" "$TS_M_UNIT" "$TS_OPT_PROFILE"
    if [[ "$TS_JSON" -eq 1 ]]; then
        local errors="[]" items=() other_j legacy_j legacy_rem_j edits_j nc_lines_j
        if [[ "$rc" -ne 0 ]]; then
            ts_j_error E_PARTIAL operational "Adopted, but ${TS_M_UNIT} or ${TS_M_TIMER_UNIT} did not start"
            errors="[${TS_R}]"
        fi
        for out in "${TS_M_OTHER_UNITS[@]}"; do
            ts_j_str "$out"
            items+=("$TS_R")
        done
        ts_j_arr "${items[@]}"
        other_j="$TS_R"
        items=()
        for out in "${TS_M_LEGACY_REMOVED[@]}"; do
            ts_j_str "$out"
            items+=("$TS_R")
        done
        ts_j_arr "${items[@]}"
        legacy_j="$TS_R"
        items=()
        for out in "${legacy_remaining[@]}"; do
            ts_j_str "$out"
            items+=("$TS_R")
        done
        ts_j_arr "${items[@]}"
        legacy_rem_j="$TS_R"
        items=()
        for out in "${unit_edits[@]}"; do
            ts_j_str "$out"
            items+=("$TS_R")
        done
        ts_j_arr "${items[@]}"
        edits_j="$TS_R"
        items=()
        for out in "${TS_M_NC_LINES[@]}"; do
            ts_j_str "$out"
            items+=("$TS_R")
        done
        ts_j_arr "${items[@]}"
        nc_lines_j="$TS_R"
        ts_j_obj b:adopted true b:managed true s:legacy_kind "$TS_M_ADOPT_KIND" \
            r:legacy_removed "$legacy_j" r:legacy_remaining "$legacy_rem_j" r:unit_edits "$edits_j" b:unit_reverted "$unit_reverted" \
            s:profile "$TS_OPT_PROFILE" s:impl "$TS_M_IMPL" s:unit "$TS_M_UNIT" s:node_user "$TS_M_USER" \
            b:uid_backstop "$TS_OPT_UID_BACKSTOP" s:iface "$TS_M_IFACE" s:slice "$TS_M_SLICE" \
            b:tunnel_started "$tunnel_started" b:ln_was_active "$ln_was_active" b:ln_restarted "$ln_restarted" \
            s:node_config "$TS_M_NC_STATUS" r:node_config_lines "$nc_lines_j" r:other_ln_units "$other_j"
        ts_json_document "$rc" "$errors" "${TS_R:1:${#TS_R}-2}"
        exit "$rc"
    fi
    echo ""
    print_line
    print_success "Adopted ${TS_M_ADOPT_KIND} install into managed mode"
    print_line
    echo ""
    echo "Check it at any time with: sudo tunnelsats verify"
    echo ""
    exit "$rc"
}

# ---------------------------------------------------------------------------
# Managed mode: uninstall --managed, status and restart on a managed install
# ---------------------------------------------------------------------------

TS_M_LEGACY_REMOVED=()
TS_M_UNIT_EDITS_FOUND=()
TS_M_UNIT_REVERTED=0

# Reverts legacy in-place edits in Lightning unit file $1 (relative to TS_FS_ROOT, e.g.
# /etc/systemd/system/lnd.service) without ever overwriting the unit from a stale .service.bak:
# strips "/usr/bin/cgexec -g net_cls:splitted_processes " from ExecStart= and uncomments
# "#ExecStartPre=...check.sh". Populates TS_M_UNIT_EDITS_FOUND and TS_M_UNIT_REVERTED.
ts_m_revert_legacy_unit_edits() {
    local rel="$1" full="${TS_FS_ROOT}${1}" tmp="${TS_FS_ROOT}${1}.tunnelsats.tmp.$$"
    TS_M_UNIT_EDITS_FOUND=()
    TS_M_UNIT_REVERTED=0
    if [[ ! -f "$full" ]] || [[ -L "$full" ]]; then
        return 0
    fi
    if grep -qE '^[[:space:]]*ExecStart[[:space:]]*=.*cgexec' "$full" 2>/dev/null; then
        TS_M_UNIT_EDITS_FOUND+=("ln_unit_cgexec")
    fi
    if grep -qE '^[[:space:]]*#[[:space:]]*ExecStartPre[[:space:]]*=.*(lnd|cl)\.check\.sh' "$full" 2>/dev/null; then
        TS_M_UNIT_EDITS_FOUND+=("ln_unit_check_disabled")
    fi
    if [[ ${#TS_M_UNIT_EDITS_FOUND[@]} -eq 0 ]]; then
        return 0
    fi
    if sed -E \
        -e 's|^([[:space:]]*ExecStart[[:space:]]*=[[:space:]]*[-@+:!]*[[:space:]]*)([^[:space:]]*/)?cgexec[[:space:]]+-g[[:space:]]+net_cls:splitted_processes[[:space:]]+|\1|' \
        -e 's/^([[:space:]]*)#[[:space:]]*(ExecStartPre[[:space:]]*=.*(lnd|cl)\.check\.sh)/\1\2/' \
        "$full" > "$tmp" && mv -f "$tmp" "$full"; then
        TS_M_UNIT_REVERTED=1
        return 0
    fi
    rm -f "$tmp" 2>/dev/null || true
    return 1
}

# Cleans legacy (v2/v3) artifacts from TS_FS_ROOT and kernel state, recording removed items in
# TS_M_LEGACY_REMOVED and any unremovable items in TS_M_REMAINING. Respects TS_OPT_KEEP_CONFIG.
ts_m_clean_legacy_artifacts() {
    local wg_rel="${WG_DIR:-/etc/wireguard}"
    wg_rel="${wg_rel#"$TS_FS_ROOT"}"
    [[ -z "$wg_rel" ]] && wg_rel="/etc/wireguard"
    local wg_full="${TS_FS_ROOT}${wg_rel}"
    local sd_rel="/etc/systemd/system"
    local sd_full="${TS_FS_ROOT}${sd_rel}"
    local unit f rel iface tbl_out line prio
    local -a ifaces=("tunnelsatsv2")
    TS_M_LEGACY_REMOVED=()

    # Discover legacy TunnelSats interfaces from configs and wants symlinks before removing files
    for f in "$wg_full"/tunnelsatsv2.conf "$wg_full"/tunnelsats-*.conf; do
        if [[ -f "$f" ]] || [[ -L "$f" ]]; then
            iface=$(basename "$f" .conf)
            if [[ " ${ifaces[*]} " != *" ${iface} "* ]]; then
                ifaces+=("$iface")
            fi
        fi
    done
    for f in "$sd_full"/multi-user.target.wants/wg-quick@tunnelsats*.service; do
        if [[ -e "$f" ]] || [[ -L "$f" ]]; then
            iface=$(basename "$f" .service)
            iface="${iface#wg-quick@}"
            if [[ " ${ifaces[*]} " != *" ${iface} "* ]]; then
                ifaces+=("$iface")
            fi
        fi
    done

    # 1. Legacy systemd units and timers
    for unit in tunnelsats-splitting-processes.timer tunnelsats-splitting-processes.service \
        tunnelsats-create-cgroup.service tunnelsats-resolve-dns-wg.timer \
        tunnelsats-resolve-dns-wg.service tunnelsats-docker-network.timer \
        tunnelsats-docker-network.service; do
        if [[ -e "${sd_full}/${unit}" ]] || [[ -L "${sd_full}/${unit}" ]]; then
            "$SYSTEMCTL_BIN" stop "$unit" >/dev/null 2>&1 || true
            "$SYSTEMCTL_BIN" disable "$unit" >/dev/null 2>&1 || true
            rm -f "${sd_full}/${unit}"
            rm -f "${sd_full}/multi-user.target.wants/${unit}" "${sd_full}/timers.target.wants/${unit}" 2>/dev/null || true
            if [[ -e "${sd_full}/${unit}" ]] || [[ -L "${sd_full}/${unit}" ]]; then
                TS_M_REMAINING+=("${sd_rel}/${unit}")
            else
                TS_M_LEGACY_REMOVED+=("${sd_rel}/${unit}")
            fi
        fi
    done

    # 2. Legacy wg-quick enablement symlinks and drop-ins (when not managed)
    if ! ts_m_inventory_present; then
        for iface in "${ifaces[@]}"; do
            "$SYSTEMCTL_BIN" stop "wg-quick@${iface}.service" >/dev/null 2>&1 || true
            "$SYSTEMCTL_BIN" disable "wg-quick@${iface}.service" >/dev/null 2>&1 || true
        done
        for f in "$sd_full"/multi-user.target.wants/wg-quick@tunnelsats*.service; do
            if [[ -e "$f" ]] || [[ -L "$f" ]]; then
                rel="${f#"$TS_FS_ROOT"}"
                rm -f "$f"
                if [[ -e "$f" ]] || [[ -L "$f" ]]; then
                    TS_M_REMAINING+=("$rel")
                else
                    TS_M_LEGACY_REMOVED+=("$rel")
                fi
            fi
        done
        for f in "$sd_full"/wg-quick@tunnelsats*.service.d; do
            if [[ -d "$f" ]]; then
                rel="${f#"$TS_FS_ROOT"}"
                rm -rf "$f"
                if [[ -d "$f" ]]; then
                    TS_M_REMAINING+=("$rel")
                else
                    TS_M_LEGACY_REMOVED+=("$rel")
                fi
            fi
        done
    fi

    # 3. Legacy drop-ins, in-place unit edits, and stale .service.bak files
    for unit in lnd.service tlnd.service slnd.service lightningd.service tlightningd.service slightningd.service litd.service lit.service; do
        rel="${sd_rel}/${unit}.d/tunnelsats-cgroup.conf"
        if [[ -e "${TS_FS_ROOT}${rel}" ]] || [[ -L "${TS_FS_ROOT}${rel}" ]]; then
            rm -f "${TS_FS_ROOT}${rel}"
            rmdir "${TS_FS_ROOT}${sd_rel}/${unit}.d" 2>/dev/null || true
            if [[ -e "${TS_FS_ROOT}${rel}" ]] || [[ -L "${TS_FS_ROOT}${rel}" ]]; then
                TS_M_REMAINING+=("$rel")
            else
                TS_M_LEGACY_REMOVED+=("$rel")
            fi
        fi
        if ! ts_m_revert_legacy_unit_edits "${sd_rel}/${unit}"; then
            TS_M_REMAINING+=("${sd_rel}/${unit}")
        elif [[ "$TS_M_UNIT_REVERTED" -eq 1 ]]; then
            TS_M_LEGACY_REMOVED+=("${sd_rel}/${unit}")
        fi
        rel="${sd_rel}/${unit}.bak"
        if [[ -e "${TS_FS_ROOT}${rel}" ]] || [[ -L "${TS_FS_ROOT}${rel}" ]]; then
            rm -f "${TS_FS_ROOT}${rel}"
            if [[ -e "${TS_FS_ROOT}${rel}" ]] || [[ -L "${TS_FS_ROOT}${rel}" ]]; then
                TS_M_REMAINING+=("$rel")
            else
                TS_M_LEGACY_REMOVED+=("$rel")
            fi
        fi
    done
    for rel in "${sd_rel}/blitzapi.service.d/tunnelsats-wg.conf" \
        "${sd_rel}/umbrel.service.d/tunnelsats_killswitch.conf" \
        "${sd_rel}/umbrel-startup.service.d/tunnelsats_killswitch.conf"; do
        if [[ -e "${TS_FS_ROOT}${rel}" ]] || [[ -L "${TS_FS_ROOT}${rel}" ]]; then
            rm -f "${TS_FS_ROOT}${rel}"
            rmdir "$(dirname "${TS_FS_ROOT}${rel}")" 2>/dev/null || true
            if [[ -e "${TS_FS_ROOT}${rel}" ]] || [[ -L "${TS_FS_ROOT}${rel}" ]]; then
                TS_M_REMAINING+=("$rel")
            else
                TS_M_LEGACY_REMOVED+=("$rel")
            fi
        fi
    done

    # 4. RaspiBlitz v2 renamed check scripts and nftables backup
    local check_base
    for check_base in lnd.check cl.check; do
        rel="/home/admin/config.scripts/${check_base}.bak"
        if [[ -f "${TS_FS_ROOT}${rel}" ]]; then
            if [[ ! -f "${TS_FS_ROOT}/home/admin/config.scripts/${check_base}.sh" ]]; then
                mv "${TS_FS_ROOT}${rel}" "${TS_FS_ROOT}/home/admin/config.scripts/${check_base}.sh" 2>/dev/null || true
            else
                rm -f "${TS_FS_ROOT}${rel}" 2>/dev/null || true
            fi
            if [[ -f "${TS_FS_ROOT}${rel}" ]]; then
                TS_M_REMAINING+=("$rel")
            else
                TS_M_LEGACY_REMOVED+=("$rel")
            fi
        fi
    done
    if [[ -f "${TS_FS_ROOT}/etc/nftablespriortunnelsats.backup" ]]; then
        if [[ ! -f "${TS_FS_ROOT}/etc/nftables.conf" ]] \
            || grep -qE 'tunnelsats|splitted_processes|0x1000000' "${TS_FS_ROOT}/etc/nftables.conf" 2>/dev/null \
            || cmp -s "${TS_FS_ROOT}/etc/nftablespriortunnelsats.backup" "${TS_FS_ROOT}/etc/nftables.conf" 2>/dev/null; then
            if mv "${TS_FS_ROOT}/etc/nftablespriortunnelsats.backup" "${TS_FS_ROOT}/etc/nftables.conf" 2>/dev/null; then
                TS_M_LEGACY_REMOVED+=("/etc/nftablespriortunnelsats.backup")
            else
                TS_M_REMAINING+=("/etc/nftablespriortunnelsats.backup")
            fi
        else
            # /etc/nftables.conf contains non-TunnelSats rules: preserve both files and report in remaining
            TS_M_REMAINING+=("/etc/nftablespriortunnelsats.backup")
        fi
    fi

    # 5. Legacy helper scripts, backups, markers, and (unless --keep-config) WireGuard configs
    for unit in tunnelsats-route-guard.sh tunnelsats-create-cgroup.sh \
        tunnelsats-splitting-processes.sh tunnelsats-resolve-dns-wg.sh \
        tunnelsats-docker-network.sh; do
        rel="${wg_rel}/${unit}"
        if [[ -e "${TS_FS_ROOT}${rel}" ]] || [[ -L "${TS_FS_ROOT}${rel}" ]]; then
            rm -f "${TS_FS_ROOT}${rel}"
            if [[ -e "${TS_FS_ROOT}${rel}" ]] || [[ -L "${TS_FS_ROOT}${rel}" ]]; then
                TS_M_REMAINING+=("$rel")
            else
                TS_M_LEGACY_REMOVED+=("$rel")
            fi
        fi
    done
    # Remove .tunnelsats-resolvconf.installed in legacy cleanup only when resolvconf is no longer installed
    rel="${wg_rel}/.tunnelsats-resolvconf.installed"
    if [[ -e "${TS_FS_ROOT}${rel}" ]] || [[ -L "${TS_FS_ROOT}${rel}" ]]; then
        if ! command -v resolvconf >/dev/null 2>&1; then
            rm -f "${TS_FS_ROOT}${rel}"
            TS_M_LEGACY_REMOVED+=("$rel")
        fi
    fi
    # Reset IPv6 sysctls when .tunnelsats-ipv6-disabled marker is present
    rel="${wg_rel}/.tunnelsats-ipv6-disabled"
    if [[ -e "${TS_FS_ROOT}${rel}" ]] || [[ -L "${TS_FS_ROOT}${rel}" ]]; then
        sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1 || true
        sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null 2>&1 || true
        rm -f "${TS_FS_ROOT}${rel}"
        TS_M_LEGACY_REMOVED+=("$rel")
    fi
    for f in "$wg_full"/tunnelsats*.conf.bak.*; do
        if [[ -e "$f" ]] || [[ -L "$f" ]]; then
            rel="${f#"$TS_FS_ROOT"}"
            rm -f "$f"
            TS_M_LEGACY_REMOVED+=("$rel")
        fi
    done
    for f in "$wg_full"/.tunnelsats-ufw-9735-*.created; do
        if [[ -e "$f" ]] || [[ -L "$f" ]]; then
            rel="${f#"$TS_FS_ROOT"}"
            local ufw_iface="${f##*/.tunnelsats-ufw-9735-}"
            ufw_iface="${ufw_iface%.created}"
            if [[ "${TS_COMMAND:-}" == "adopt" ]]; then
                if [[ "$ufw_iface" == "$TS_M_IFACE" ]]; then
                    continue
                fi
                if command -v ufw >/dev/null 2>&1; then
                    local ufw_st ufw_out
                    ufw_st=$(LC_ALL=C ufw status 2>/dev/null || true)
                    if ! printf '%s\n' "$ufw_st" | grep -qE "^[[:space:]]*9735/tcp[[:space:]]+on[[:space:]]+${TS_M_IFACE}[[:space:]]+ALLOW([[:space:]]+IN)?[[:space:]]+Anywhere([[:space:]]|\$)"; then
                        if ufw_out=$(LC_ALL=C ufw allow in on "$TS_M_IFACE" to any port 9735 proto tcp 2>/dev/null); then
                            if [[ "$ufw_out" != *"Skipping"* ]]; then
                                : > "${wg_full}/.tunnelsats-ufw-9735-${TS_M_IFACE}.created" 2>/dev/null || true
                            fi
                        fi
                    fi
                fi
            fi
            if command -v ufw >/dev/null 2>&1; then
                if ufw delete allow in on "$ufw_iface" to any port 9735 proto tcp >/dev/null 2>&1; then
                    rm -f "$f"
                    TS_M_LEGACY_REMOVED+=("$rel")
                else
                    TS_M_REMAINING+=("$rel")
                fi
            else
                rm -f "$f"
                TS_M_LEGACY_REMOVED+=("$rel")
            fi
        fi
    done
    if [[ "$TS_OPT_KEEP_CONFIG" -ne 1 ]]; then
        for f in "$wg_full"/tunnelsatsv2.conf "$wg_full"/tunnelsats-*.conf; do
            if [[ -e "$f" ]] || [[ -L "$f" ]]; then
                rel="${f#"$TS_FS_ROOT"}"
                rm -f "$f"
                if [[ -e "$f" ]] || [[ -L "$f" ]]; then
                    TS_M_REMAINING+=("$rel")
                else
                    TS_M_LEGACY_REMOVED+=("$rel")
                fi
            fi
        done
    fi

    # 6. Legacy kernel state: nft tables, failclosed rules, legacy ip rules, and table 51820 routes
    if command -v "$NFT_BIN" >/dev/null 2>&1; then
        tbl_out=$("$NFT_BIN" list tables 2>/dev/null) || tbl_out=""
        while IFS= read -r line; do
            if [[ "$line" =~ ^table[[:space:]]+(ip|ip6|inet)[[:space:]]+(tunnelsats[A-Za-z0-9_.-]*)[[:space:]]*$ ]]; then
                if [[ "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}" == "inet ${TS_M_NFT_TABLE}" ]] && ts_m_inventory_present; then
                    continue
                fi
                if "$NFT_BIN" delete table "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" 2>/dev/null; then
                    TS_M_LEGACY_REMOVED+=("nft table ${BASH_REMATCH[1]} ${BASH_REMATCH[2]}")
                else
                    TS_M_REMAINING+=("nft table ${BASH_REMATCH[1]} ${BASH_REMATCH[2]}")
                fi
            fi
        done < <(printf '%s\n' "$tbl_out")
    fi

    if [[ -f "${wg_full}/.tunnelsats-failclosed-rules" ]]; then
        local fc_failed=0 fc_has_v4=0 fc_has_v6=0
        if grep -qE '^(from |uidrange )' "${wg_full}/.tunnelsats-failclosed-rules" 2>/dev/null; then
            fc_has_v4=1
        fi
        if grep -qE '^uidrange6 ' "${wg_full}/.tunnelsats-failclosed-rules" 2>/dev/null; then
            fc_has_v6=1
        fi
        if command -v "$IP_BIN" >/dev/null 2>&1; then
            local fc_entry fc_after="" fc6_after=""
            while IFS= read -r fc_entry || [[ -n "$fc_entry" ]]; do
                case "$fc_entry" in
                    "from "[0-9]*.[0-9]*.[0-9]*.[0-9]*/*)
                        "$IP_BIN" -4 rule del priority 21818 from "${fc_entry#from }" blackhole 2>/dev/null \
                            || "$IP_BIN" -4 rule del priority 21818 from "${fc_entry#from }" unreachable 2>/dev/null || true
                        ;;
                    "uidrange "[1-9][0-9]*-[1-9][0-9]*)
                        "$IP_BIN" -4 rule del priority 21819 uidrange "${fc_entry#uidrange }" blackhole 2>/dev/null \
                            || "$IP_BIN" -4 rule del priority 21819 uidrange "${fc_entry#uidrange }" unreachable 2>/dev/null || true
                        ;;
                    "uidrange6 "[1-9][0-9]*-[1-9][0-9]*)
                        "$IP_BIN" -6 rule del priority 21819 uidrange "${fc_entry#uidrange6 }" blackhole 2>/dev/null \
                            || "$IP_BIN" -6 rule del priority 21819 uidrange "${fc_entry#uidrange6 }" unreachable 2>/dev/null || true
                        ;;
                esac
            done < "${wg_full}/.tunnelsats-failclosed-rules"
            if [[ "$fc_has_v4" -eq 1 ]]; then
                if ! fc_after=$("$IP_BIN" -4 rule show 2>/dev/null); then
                    fc_failed=1
                fi
            fi
            if [[ "$fc_has_v6" -eq 1 ]] && ts_m_ipv6_available; then
                if ! fc6_after=$("$IP_BIN" -6 rule show 2>/dev/null); then
                    fc_failed=1
                fi
            fi
            while IFS= read -r fc_entry || [[ -n "$fc_entry" ]]; do
                case "$fc_entry" in
                    "from "[0-9]*.[0-9]*.[0-9]*.[0-9]*/*)
                        if printf '%s\n' "$fc_after" | grep -qE "^21818:[[:space:]]+from[[:space:]]+${fc_entry#from }[[:space:]]+(blackhole|unreachable)([[:space:]]|$)"; then
                            fc_failed=1
                        fi
                        ;;
                    "uidrange "[1-9][0-9]*-[1-9][0-9]*)
                        if printf '%s\n' "$fc_after" | grep -qE "^21819:[[:space:]]+from[[:space:]]+all[[:space:]]+uidrange[[:space:]]+${fc_entry#uidrange }[[:space:]]+(blackhole|unreachable)([[:space:]]|$)"; then
                            fc_failed=1
                        fi
                        ;;
                    "uidrange6 "[1-9][0-9]*-[1-9][0-9]*)
                        if printf '%s\n' "$fc6_after" | grep -qE "^21819:[[:space:]]+from[[:space:]]+all[[:space:]]+uidrange[[:space:]]+${fc_entry#uidrange6 }[[:space:]]+(blackhole|unreachable)([[:space:]]|$)"; then
                            fc_failed=1
                        fi
                        ;;
                esac
            done < "${wg_full}/.tunnelsats-failclosed-rules"
        elif [[ "$fc_has_v4" -eq 1 ]] || [[ "$fc_has_v6" -eq 1 ]]; then
            fc_failed=1
        fi
        if [[ "$fc_failed" -eq 0 ]]; then
            rm -f "${wg_full}/.tunnelsats-failclosed-rules"
            TS_M_LEGACY_REMOVED+=("${wg_rel}/.tunnelsats-failclosed-rules")
        else
            TS_M_REMAINING+=("${wg_rel}/.tunnelsats-failclosed-rules")
        fi
    fi

    if command -v "$IP_BIN" >/dev/null 2>&1 && ! ts_m_inventory_present; then
        local rules_out had_legacy_fwmark=0 n
        for n in 1 2 3 4 5; do
            rules_out=$("$IP_BIN" -4 rule show 2>/dev/null) || break
            local removed_any=0
            while IFS= read -r line; do
                if [[ "$line" =~ ^([0-9]+):[[:space:]]+from\ all\ fwmark\ 0x1000000/0xff000000\ lookup\ 51820([[:space:]]|$) ]]; then
                    prio="${BASH_REMATCH[1]}"
                    if "$IP_BIN" -4 rule del from all fwmark 0x1000000/0xff000000 lookup 51820 priority "$prio" 2>/dev/null; then
                        had_legacy_fwmark=1
                        removed_any=1
                        TS_M_LEGACY_REMOVED+=("ip -4 rule ${prio} (fwmark 0x1000000/0xff000000 lookup 51820)")
                    else
                        TS_M_REMAINING+=("ip -4 rule ${prio} (fwmark 0x1000000/0xff000000 lookup 51820)")
                    fi
                elif [[ "$line" =~ ^21821:[[:space:]]+from\ all\ uidrange\ ([0-9]+-[0-9]+)\ lookup\ 51820([[:space:]]|$) ]]; then
                    if "$IP_BIN" -4 rule del from all uidrange "${BASH_REMATCH[1]}" lookup 51820 priority 21821 2>/dev/null; then
                        removed_any=1
                        TS_M_LEGACY_REMOVED+=("ip -4 rule 21821 (uidrange ${BASH_REMATCH[1]} lookup 51820)")
                    else
                        TS_M_REMAINING+=("ip -4 rule 21821 (uidrange ${BASH_REMATCH[1]} lookup 51820)")
                    fi
                elif [[ "$line" =~ ^21820:[[:space:]]+from\ all\ lookup\ main\ suppress_prefixlength\ 0([[:space:]]|$) ]]; then
                    if "$IP_BIN" -4 rule del from all lookup main suppress_prefixlength 0 priority 21820 2>/dev/null; then
                        removed_any=1
                        TS_M_LEGACY_REMOVED+=("ip -4 rule 21820 (lookup main suppress_prefixlength 0)")
                    else
                        TS_M_REMAINING+=("ip -4 rule 21820 (lookup main suppress_prefixlength 0)")
                    fi
                fi
            done < <(printf '%s\n' "$rules_out")
            [[ "$removed_any" -eq 0 ]] && break
        done
        if [[ "$had_legacy_fwmark" -eq 1 ]]; then
            rules_out=$("$IP_BIN" -4 rule show 2>/dev/null) || rules_out=""
            while IFS= read -r line; do
                if [[ "$line" =~ ^([0-9]+):[[:space:]]+from\ all\ lookup\ main\ suppress_prefixlength\ 0([[:space:]]|$) ]]; then
                    prio="${BASH_REMATCH[1]}"
                    if "$IP_BIN" -4 rule del from all lookup main suppress_prefixlength 0 priority "$prio" 2>/dev/null; then
                        TS_M_LEGACY_REMOVED+=("ip -4 rule ${prio} (lookup main suppress_prefixlength 0)")
                    else
                        TS_M_REMAINING+=("ip -4 rule ${prio} (lookup main suppress_prefixlength 0)")
                    fi
                fi
            done < <(printf '%s\n' "$rules_out")
        fi

        local routes_out
        routes_out=$("$IP_BIN" -4 route show table 51820 2>/dev/null) || routes_out=""
        if printf '%s\n' "$routes_out" | grep -qE '^blackhole[[:space:]]+default[[:space:]]+metric[[:space:]]+3([[:space:]]|$)'; then
            if "$IP_BIN" -4 route del blackhole default metric 3 table 51820 2>/dev/null; then
                TS_M_LEGACY_REMOVED+=("ip -4 route table 51820 blackhole metric 3")
            else
                TS_M_REMAINING+=("ip -4 route table 51820 blackhole metric 3")
            fi
        fi
        for iface in "${ifaces[@]}"; do
            if printf '%s\n' "$routes_out" | grep -qE "^default[[:space:]]+dev[[:space:]]+${iface}([[:space:]]|$)"; then
                if "$IP_BIN" -4 route del default dev "$iface" table 51820 2>/dev/null; then
                    TS_M_LEGACY_REMOVED+=("ip -4 route table 51820 default dev ${iface}")
                else
                    TS_M_REMAINING+=("ip -4 route table 51820 default dev ${iface}")
                fi
            fi
        done
    fi

    "$SYSTEMCTL_BIN" daemon-reload >/dev/null 2>&1 || true
    return 0
}

cmd_uninstall_managed() {
    local answer="" ln_was_active=0 ln_was_stopped=0 ln_state="" locked=0 ln_started=0 ln_disabled=0 disable_err="" reason="" rc=0 rb_env="" i
    ts_m_require_root
    if ! ts_m_inventory_present; then
        if [[ "$TS_OPT_LEGACY_ARTIFACTS" -eq 1 ]]; then
            ts_m_lifecycle_lock
            if ! ts_m_inventory_present; then
                if [[ "$TS_JSON" -ne 1 ]]; then
                    print_header "Managed Uninstall (legacy artifact cleanup)"
                fi
                ts_confirm answer "Clean legacy TunnelSats artifacts? [y/N]: "
                if [[ ! "$answer" =~ ^[Yy] ]]; then
                    ts_m_lifecycle_cleanup
                    ts_fail 1 E_ABORTED operational "Uninstall aborted; nothing was changed"
                fi
                local -a leg_units=() leg_active_units=() leg_disabled_units=() leg_nc_lines=()
                local leg_u leg_state leg_impl leg_prof leg_nc_reason=""
                leg_prof=$(ts_guess_platform "$TS_FS_ROOT")
                [[ "$leg_prof" != "raspiblitz" && "$leg_prof" != "mynode" ]] && leg_prof="baremetal"
                for leg_u in lnd.service tlnd.service slnd.service lightningd.service tlightningd.service slightningd.service litd.service lit.service; do
                    if [[ -f "${TS_FS_ROOT}/etc/systemd/system/${leg_u}" ]] || [[ "$(ts_m_unit_prop "$leg_u" LoadState)" == "loaded" ]]; then
                        leg_units+=("$leg_u")
                        leg_state=$(ts_m_unit_prop "$leg_u" ActiveState)
                        case "$leg_state" in
                            inactive|failed|"") ;;
                            *)
                                leg_active_units+=("$leg_u")
                                if ! "$SYSTEMCTL_BIN" stop "$leg_u"; then
                                    ts_m_lifecycle_cleanup
                                    ts_fail 1 E_LN_STOP operational "${leg_u} could not be stopped; nothing was removed"
                                fi
                                leg_state=$(ts_m_unit_prop "$leg_u" ActiveState)
                                case "$leg_state" in
                                    inactive|failed) ;;
                                    *)
                                        ts_m_lifecycle_cleanup
                                        ts_fail 1 E_LN_STOP operational "${leg_u} did not stop (state ${leg_state:-unknown}); nothing was removed"
                                        ;;
                                esac
                                ;;
                        esac
                    fi
                done
                TS_M_REMAINING=()
                ts_m_clean_legacy_artifacts
                if [[ -e "${TS_FS_ROOT}${TS_M_BIN}" ]] || [[ -L "${TS_FS_ROOT}${TS_M_BIN}" ]]; then
                    rm -f "${TS_FS_ROOT}${TS_M_BIN}"
                    if [[ -e "${TS_FS_ROOT}${TS_M_BIN}" ]]; then
                        TS_M_REMAINING+=("$TS_M_BIN")
                    else
                        TS_M_LEGACY_REMOVED+=("$TS_M_BIN")
                    fi
                fi
                for leg_u in "${leg_units[@]}"; do
                    case "$leg_u" in
                        *lnd.service) leg_impl="lnd" ;;
                        *lightningd.service) leg_impl="cln" ;;
                        *) leg_impl="lit" ;;
                    esac
                    ts_m_node_config_clearnet "$leg_impl" "$leg_u" "$leg_prof"
                    if [[ "$TS_M_NC_STATUS" != "clean" ]]; then
                        [[ -z "$leg_nc_reason" ]] && leg_nc_reason="node_config_${TS_M_NC_STATUS}"
                        leg_nc_lines+=("${TS_M_NC_LINES[@]}")
                        print_warning "${leg_u} stays stopped: without the tunnel, its clearnet settings would use the regular internet connection."
                        ts_m_uninstall_print_lines
                        if "$SYSTEMCTL_BIN" disable "$leg_u" >/dev/null 2>&1; then
                            leg_disabled_units+=("$leg_u")
                            if [[ "$TS_JSON" -ne 1 ]]; then
                                echo "The unit was disabled, so it does not start with these settings on the next boot." >&2
                                echo "Once clean, enable and start it with: sudo systemctl enable --now ${leg_u}" >&2
                            fi
                        else
                            TS_M_REMAINING+=("${leg_u} (could not be disabled)")
                        fi
                    elif [[ " ${leg_active_units[*]} " == *" ${leg_u} "* ]] && [[ ${#TS_M_REMAINING[@]} -eq 0 ]]; then
                        if ! "$SYSTEMCTL_BIN" start "$leg_u" >/dev/null 2>&1; then
                            TS_M_REMAINING+=("${leg_u} (could not be started)")
                        fi
                    fi
                done
                ts_m_lifecycle_cleanup
                if [[ ${#TS_M_REMAINING[@]} -gt 0 ]]; then
                    rc=1
                fi
                if [[ "$TS_JSON" -eq 1 ]]; then
                    local items=() errors=() remaining_j legacy_j disabled_j nc_lines_j action_j="null"
                    for i in "${TS_M_REMAINING[@]}"; do
                        ts_j_str "$i"
                        items+=("$TS_R")
                    done
                    ts_j_arr "${items[@]}"
                    remaining_j="$TS_R"
                    items=()
                    for i in "${TS_M_LEGACY_REMOVED[@]}"; do
                        ts_j_str "$i"
                        items+=("$TS_R")
                    done
                    ts_j_arr "${items[@]}"
                    legacy_j="$TS_R"
                    items=()
                    for i in "${leg_disabled_units[@]}"; do
                        ts_j_str "$i"
                        items+=("$TS_R")
                    done
                    ts_j_arr "${items[@]}"
                    disabled_j="$TS_R"
                    items=()
                    for i in "${leg_nc_lines[@]}"; do
                        ts_j_str "$i"
                        items+=("$TS_R")
                    done
                    ts_j_arr "${items[@]}"
                    nc_lines_j="$TS_R"
                    if [[ ${#leg_disabled_units[@]} -gt 0 ]]; then
                        ts_j_obj s:reason "${leg_nc_reason:-node_config_clearnet}" r:units "$disabled_j" \
                            r:lines "$nc_lines_j" s:then "systemctl enable --now ${leg_disabled_units[*]}"
                        action_j="$TS_R"
                    fi
                    if [[ "$rc" -ne 0 ]]; then
                        ts_j_error E_UNINSTALL_INCOMPLETE operational "Could not remove: ${TS_M_REMAINING[*]}"
                        errors+=("$TS_R")
                    fi
                    ts_j_obj b:managed false b:removed "$([[ "$rc" -eq 0 ]] && echo 1 || echo 0)" \
                        r:remaining "$remaining_j" r:legacy_removed "$legacy_j" b:config_kept "$TS_OPT_KEEP_CONFIG" \
                        r:disabled_units "$disabled_j" r:node_config_lines "$nc_lines_j" r:action_required "$action_j"
                    ts_json_document "$rc" "$(IFS=,; echo "[${errors[*]}]")" "${TS_R:1:${#TS_R}-2}"
                else
                    print_success "Legacy TunnelSats artifacts cleaned (${#TS_M_LEGACY_REMOVED[@]} item(s) removed)"
                fi
                exit "$rc"
            fi
        else
            ts_fail 3 E_NOT_INSTALLED not_installed "No managed install found (${TS_M_INVENTORY})"
        fi
    else
        ts_m_lifecycle_lock
    fi
    if ! ts_m_inventory_present; then
        # Another uninstall finished between the check and the lock
        ts_m_lifecycle_cleanup
        ts_fail 3 E_NOT_INSTALLED not_installed "No managed install found (${TS_M_INVENTORY})"
    fi
    if ! ts_m_inventory_read; then
        ts_fail 1 E_INVENTORY operational "$TS_M_ERROR"
    fi
    if [[ -n "$TS_OPT_PROFILE" ]] && [[ "$TS_OPT_PROFILE" != "$TS_M_INV_PROFILE" ]]; then
        ts_fail 2 E_USAGE usage "The managed install uses profile ${TS_M_INV_PROFILE}, not ${TS_OPT_PROFILE}"
    fi
    if [[ "$TS_JSON" -ne 1 ]]; then
        print_header "Managed Uninstall"
    fi
    ts_confirm answer "Stop ${TS_M_INV_UNIT} and remove the managed dataplane? [y/N]: "
    if [[ ! "$answer" =~ ^[Yy] ]]; then
        ts_fail 1 E_ABORTED operational "Uninstall aborted; nothing was changed"
    fi
    # The record of units the verifier stopped goes first, under the kill switch lock (when it can
    # be taken), so no verifier run starts Lightning again while it is being removed
    if ts_m_lock; then
        locked=1
    fi
    if ts_m_stopped_status "$TS_M_INV_UNIT" >/dev/null; then
        ln_was_stopped=1
    fi
    rm -f "${TS_FS_ROOT}${TS_M_STOPPED}" "${TS_FS_ROOT}${TS_M_STOPPED}.tmp"
    if [[ "$locked" -eq 1 ]]; then
        ts_m_unlock
    fi
    # Every state but inactive and failed means the unit runs, starts (ExecStartPre, LND before
    # READY=1), reloads, stops or waits for its next automatic restart (Restart=always, also after a
    # start a start guard refused). disable ends none of these, and a start that completes after the
    # removal runs outside the tunnel: the unit is stopped (which also cancels a pending restart) and
    # has to read back stopped before anything is removed. It was meant to run.
    ln_state=$(ts_m_unit_prop "$TS_M_INV_UNIT" ActiveState)
    case "$ln_state" in
        inactive|failed)
            if [[ "$ln_was_stopped" -eq 1 ]]; then
                # Stopped by the verifier while no protection held; it was meant to run
                ln_was_active=1
            fi
            ;;
        *)
            ln_was_active=1
            print_info "Stopping ${TS_M_INV_UNIT} (${ln_state:-state unknown}; still inside the slice and protected)..."
            if ! "$SYSTEMCTL_BIN" stop "$TS_M_INV_UNIT"; then
                ts_fail 1 E_LN_STOP operational "${TS_M_INV_UNIT} could not be stopped; nothing was removed"
            fi
            ln_state=$(ts_m_unit_prop "$TS_M_INV_UNIT" ActiveState)
            case "$ln_state" in
                inactive|failed) ;;
                *) ts_fail 1 E_LN_STOP operational "${TS_M_INV_UNIT} did not stop (state ${ln_state:-unknown}); nothing was removed" ;;
            esac
            ;;
    esac
    # RaspiBlitz's start guard keeps the flags of the current start below /run/tunnelsats, which the
    # removal clears: their state is read first (ts_m_execstart_args)
    if [[ "$TS_M_INV_PROFILE" == "raspiblitz" ]] && ts_m_raspiblitz_guard_ctx "$TS_M_INV_UNIT"; then
        rb_env=$(ts_m_raspiblitz_env_state "${TS_FS_ROOT}${TS_M_RB_ENVFILE}" "$TS_M_RB_VAR")
    fi
    # LND announces the addresses it saved again at every start: the former VPN addresses are read
    # before the removal deletes the tunnel config, and the record of the removal keeps them until
    # an uninstall completes (ts_m_announce_cleanup)
    TS_M_ANN_ADDRS=()
    TS_M_ANN_PORT=""
    TS_M_ANN_WHY="not read"
    if [[ "$TS_M_INV_IMPL" == "lnd" ]] || [[ "$TS_M_INV_IMPL" == "lit" ]]; then
        ts_m_announce_read
        TS_M_INV_ANNOUNCE="${TS_M_ANN_ADDRS[*]}"
    fi
    print_info "Removing the managed dataplane..."
    ts_m_remove_dataplane
    TS_M_LEGACY_REMOVED=()
    if [[ "$TS_OPT_LEGACY_ARTIFACTS" -eq 1 ]]; then
        ts_m_clean_legacy_artifacts
    fi
    if [[ ${#TS_M_REMAINING[@]} -gt 0 ]]; then
        rc=1
        print_error "Could not remove: ${TS_M_REMAINING[*]}"
        print_info "The inventory keeps the record (state removing): fix the cause, then run 'tunnelsats.sh uninstall --managed' again."
    else
        print_success "Managed dataplane removed"
    fi

    # The node config is the operator's: Lightning starts again only if it holds no TunnelSats
    # clearnet settings, because outside the slice they would use the regular internet connection.
    # Flags of the start guard are no setting to remove here, so they get no re-check.
    ts_m_node_config_clearnet "$TS_M_INV_IMPL" "$TS_M_INV_UNIT" "$TS_M_INV_PROFILE" "$rb_env"
    if [[ "$ln_was_active" -eq 1 ]] && [[ "$TS_M_NC_STATUS" != "clean" ]] && [[ "$TS_NONINTERACTIVE" -ne 1 ]] && [[ "$rc" -eq 0 ]] && \
        [[ "$rb_env" != "flags" ]]; then
        for i in 1 2 3; do
            ts_m_uninstall_print_lines
            ts_ask answer "--yes" "Remove these settings now, then press Enter to check again (or type 'skip'): " "skip"
            if [[ "$answer" == "skip" ]]; then
                break
            fi
            ts_m_node_config_clearnet "$TS_M_INV_IMPL" "$TS_M_INV_UNIT" "$TS_M_INV_PROFILE" "$rb_env"
            if [[ "$TS_M_NC_STATUS" == "clean" ]]; then
                break
            fi
        done
    fi
    if [[ "$TS_M_NC_STATUS" != "clean" ]]; then
        # Outside the slice, these settings would use the regular internet connection: the unit
        # stays stopped and is disabled, whether it ran before or not, so no boot starts it so
        reason="node_config_${TS_M_NC_STATUS}"
        print_warning "${TS_M_INV_UNIT} stays stopped: without the tunnel, its clearnet settings would use the regular internet connection."
        ts_m_uninstall_print_lines
        if disable_err=$("$SYSTEMCTL_BIN" disable "$TS_M_INV_UNIT" 2>&1); then
            ln_disabled=1
            echo "The unit was disabled, so it does not start with these settings on the next boot." >&2
            echo "Once clean, enable and start it with: sudo systemctl enable --now ${TS_M_INV_UNIT}" >&2
        else
            rc=1
            print_error "${TS_M_INV_UNIT} could not be disabled (${disable_err:-no reason given}): it would start with these settings on the next boot. Disable it with: sudo systemctl disable ${TS_M_INV_UNIT}"
        fi
    elif [[ "$ln_was_active" -eq 0 ]]; then
        reason="not_running_before"
    elif [[ "$rc" -ne 0 ]]; then
        reason="removal_incomplete"
    elif "$SYSTEMCTL_BIN" start "$TS_M_INV_UNIT"; then
        ln_started=1
        print_success "${TS_M_INV_UNIT} started (outside the slice; the node config holds no TunnelSats clearnet settings)"
    else
        rc=1
        reason="start_failed"
        print_error "${TS_M_INV_UNIT} did not start (see: journalctl -u ${TS_M_INV_UNIT})"
    fi
    ts_m_announce_cleanup

    if [[ "$TS_JSON" -eq 1 ]]; then
        local items=() errors=() remaining_j lines_j action_j="null" then_cmd warnings_j legacy_j
        for i in "${TS_M_REMAINING[@]}"; do
            ts_j_str "$i"
            items+=("$TS_R")
        done
        ts_j_arr "${items[@]}"
        remaining_j="$TS_R"
        items=()
        for i in "${TS_M_LEGACY_REMOVED[@]}"; do
            ts_j_str "$i"
            items+=("$TS_R")
        done
        ts_j_arr "${items[@]}"
        legacy_j="$TS_R"
        items=()
        for i in "${TS_M_ANN_WARNINGS[@]}"; do
            ts_j_str "$i"
            items+=("$TS_R")
        done
        ts_j_arr "${items[@]}"
        warnings_j="$TS_R"
        if [[ "$TS_M_NC_STATUS" != "clean" ]]; then
            items=()
            for i in "${TS_M_NC_LINES[@]}"; do
                ts_j_str "$i"
                items+=("$TS_R")
            done
            ts_j_arr "${items[@]}"
            lines_j="$TS_R"
            if [[ "$ln_disabled" -eq 1 ]]; then
                then_cmd="systemctl enable --now ${TS_M_INV_UNIT}"
            else
                then_cmd="systemctl disable ${TS_M_INV_UNIT}"
            fi
            ts_j_obj s:reason "$reason" sn:detail "$TS_M_NC_REASON" r:lines "$lines_j" s:then "$then_cmd"
            action_j="$TS_R"
        fi
        if [[ ${#TS_M_REMAINING[@]} -gt 0 ]] || [[ "$reason" == "start_failed" ]]; then
            ts_j_error E_UNINSTALL_INCOMPLETE operational "Uninstall did not complete: ${TS_M_REMAINING[*]:-${reason}}. The inventory keeps the record; run 'tunnelsats.sh uninstall --managed' again once the cause is fixed"
            errors+=("$TS_R")
        fi
        if [[ "$TS_M_NC_STATUS" != "clean" ]] && [[ "$ln_disabled" -eq 0 ]]; then
            ts_j_error E_LN_DISABLE operational "${TS_M_INV_UNIT} could not be disabled (${disable_err:-no reason given}); it would start with TunnelSats clearnet settings outside the tunnel on the next boot: run 'systemctl disable ${TS_M_INV_UNIT}'"
            errors+=("$TS_R")
        fi
        ts_j_obj b:managed true s:unit "$TS_M_INV_UNIT" r:remaining "$remaining_j" r:legacy_removed "$legacy_j" \
            b:config_kept "$TS_OPT_KEEP_CONFIG" b:ln_was_active "$ln_was_active" \
            b:ln_started "$ln_started" b:ln_disabled "$ln_disabled" s:node_config "$TS_M_NC_STATUS" r:action_required "$action_j" \
            s:announce_cleanup "$TS_M_ANN_RESULT" r:warnings "$warnings_j"
        ts_json_document "$rc" "$(IFS=,; echo "[${errors[*]}]")" "${TS_R:1:${#TS_R}-2}"
    fi
    exit "$rc"
}

# Prints the TunnelSats clearnet settings found in the node config or on the unit's command line
# (or why they could not be checked), and the includes of a CLN config, which are not checked (they
# end TS_M_NC_LINES, see ts_m_node_config_clearnet).
ts_m_uninstall_print_lines() {
    local l i n_set=$(( ${#TS_M_NC_LINES[@]} - ${#TS_M_NC_INCLUDES[@]} ))
    if [[ "$TS_M_NC_STATUS" == "unknown" ]]; then
        echo "The Lightning settings could not be checked: ${TS_M_NC_REASON}." >&2
        for l in "${TS_M_NC_INCLUDES[@]}"; do
            echo "  ${l}" >&2
        done
        echo "Make sure neither the node config nor the command line (ExecStart) of ${TS_M_INV_UNIT} holds TunnelSats clearnet settings (LND: externalhosts, tor.skip-proxy-for-clearnet-targets; CLN: bind-addr=0.0.0.0:9735, addr or announce-addr with a clearnet address, always-use-proxy=false)." >&2
        return 0
    fi
    echo "Remove these TunnelSats settings (node config, or the command line of ${TS_M_INV_UNIT}):" >&2
    for (( i = 0; i < n_set; i++ )); do
        echo "  ${TS_M_NC_LINES[$i]}" >&2
    done
    if [[ ${#TS_M_NC_INCLUDES[@]} -gt 0 ]]; then
        echo "The config also includes other files, which are not checked; check them for these settings as well:" >&2
        for l in "${TS_M_NC_INCLUDES[@]}"; do
            echo "  ${l}" >&2
        done
    fi
}

# LND 0.20 and later saves the addresses it announces and announces them again at every start when
# its config sets no externalip, so after the uninstall it would go on announcing the former VPN
# address: an IPv4 of the endpoint with the forwarded port, which externalhosts resolved to. Reads the
# candidates into TS_M_ANN_ADDRS before the removal deletes the tunnel config: the endpoint's IPv4 now
# (looked up for at most TS_V_RESOLVE_TIMEOUT seconds, as in verify) and the one WireGuard uses, which
# it resolved when the tunnel started (LND may have saved that one before a DNS change), each with the
# forwarded port (TS_M_ANN_PORT), plus those an earlier uninstall that did not complete saved in the
# install record (TS_M_INV_ANNOUNCE). TS_M_ANN_WHY says why TS_M_ANN_ADDRS is empty.
ts_m_announce_read() {
    local live="" a
    TS_M_ANN_ADDRS=()
    TS_M_ANN_PORT=""
    TS_M_ANN_WHY=""
    ts_v_read_endpoint
    TS_M_ANN_PORT="$TS_V_VPN_PORT"
    if [[ -n "$TS_M_ANN_PORT" ]]; then
        if [[ -n "$TS_V_ENDPOINT_IP" ]] && valid_ipv4 "$TS_V_ENDPOINT_IP"; then
            TS_M_ANN_ADDRS+=("${TS_V_ENDPOINT_IP}:${TS_M_ANN_PORT}")
        fi
        live=$("$WG_BIN" show "$TS_M_IFACE" endpoints 2>/dev/null | awk 'NR == 1 { print $2 }') || live=""
        live="${live%:*}"
        if valid_ipv4 "$live" && ! ts_in_list "${live}:${TS_M_ANN_PORT}" "${TS_M_ANN_ADDRS[*]}"; then
            TS_M_ANN_ADDRS+=("${live}:${TS_M_ANN_PORT}")
        fi
    fi
    for a in $TS_M_INV_ANNOUNCE; do
        if valid_ipv4 "${a%:*}" && ! ts_in_list "$a" "${TS_M_ANN_ADDRS[*]}"; then
            TS_M_ANN_ADDRS+=("$a")
            TS_M_ANN_PORT="${TS_M_ANN_PORT:-${a##*:}}"
        fi
    done
    if [[ ${#TS_M_ANN_ADDRS[@]} -gt 0 ]]; then
        return 0
    elif [[ -z "$TS_V_EP_HOST" ]]; then
        TS_M_ANN_WHY="no endpoint in ${TS_M_WG_CONF}"
    elif [[ -z "$TS_V_VPN_PORT" ]]; then
        TS_M_ANN_WHY="no forwarded port in ${TS_M_WG_CONF}"
    else
        TS_M_ANN_WHY="${TS_V_EP_HOST} did not resolve"
    fi
}

# Sets TS_M_LNCLI to the lncli command line for LND unit $1, without the user it runs as: LNCLI_BIN,
# else the lncli next to the unit's lnd, else lncli on the PATH; --lnddir from the unit's command line,
# else lnddir in the node config, else ~/.lnd of the node user; --network and --rpcserver when the
# command line or the node config sets bitcoin.<network> or rpclisten. Leaves TS_M_NC_* as they were.
ts_m_lncli_argv() {
    local unit="$1" arg prev="" dir="" net="" rpc="" bin="lncli" home="" f key val nc_reason="$TS_M_NC_REASON"
    local -a files=() nc_files=("${TS_M_NC_FILES[@]}")
    TS_M_LNCLI=()
    if ts_m_execstart_tokens "$unit"; then
        if [[ "${TS_M_EXEC_ARGV[0]}" == /*/lnd ]] && [[ -x "${TS_M_EXEC_ARGV[0]%/lnd}/lncli" ]]; then
            bin="${TS_M_EXEC_ARGV[0]%/lnd}/lncli"
        fi
        for arg in "${TS_M_EXEC_ARGV[@]:1}"; do
            case "$prev" in
                --lnddir) dir="$arg" ;;
                --rpclisten) rpc="${rpc:-$arg}" ;;
            esac
            case "$arg" in
                --lnddir=*) dir="${arg#*=}" ;;
                --rpclisten=*) rpc="${rpc:-${arg#*=}}" ;;
            esac
            if [[ "$arg" =~ ^--bitcoin\.(testnet4|testnet|signet|regtest|simnet)(=(true|1))?$ ]]; then
                net="${BASH_REMATCH[1]}"
            fi
            prev="$arg"
        done
    fi
    ts_m_node_config_files lnd "$unit"
    files=("${TS_M_NC_FILES[@]}")
    TS_M_NC_FILES=("${nc_files[@]}")
    TS_M_NC_REASON="$nc_reason"
    for f in "${files[@]}"; do
        while IFS='|' read -r _ key val; do
            case "$key" in
                lnddir) dir="${dir:-$val}" ;;
                rpclisten) rpc="${rpc:-$val}" ;;
                bitcoin.testnet4|bitcoin.testnet|bitcoin.signet|bitcoin.regtest|bitcoin.simnet)
                    case "${val,,}" in
                        ""|true|1) net="${net:-${key#bitcoin.}}" ;;
                    esac
                    ;;
            esac
        done < <(ts_m_config_settings "${TS_FS_ROOT}${f}")
    done
    home=$(ts_m_user_home "$TS_M_INV_USER") || home=""
    if [[ -n "$home" ]]; then
        dir="${dir:-${home}/.lnd}"
        case "$dir" in
            \~/*) dir="${home}/${dir:2}" ;;
        esac
    fi
    # The node config belongs to the node user, and root is asked to paste the printed command: lnddir
    # and rpclisten pass only as plain values, for the executed command line and the printed one alike.
    # An unusable one is left out (lncli takes its default) and named in TS_M_LNCLI_UNUSABLE.
    local dir_re='^/[A-Za-z0-9._/-]{1,255}$' rpc_re='^(localhost|[A-Za-z0-9.-]{1,253}|\[[0-9A-Fa-f:]+\]):[0-9]{1,5}$'
    TS_M_LNCLI=("${LNCLI_BIN:-$bin}")
    TS_M_LNCLI_UNUSABLE=()
    if [[ -n "$dir" ]]; then
        if [[ "$dir" =~ $dir_re ]] && [[ "/${dir}/" != */../* ]]; then
            TS_M_LNCLI+=("--lnddir=${dir}")
        else
            TS_M_LNCLI_UNUSABLE+=("lnddir")
        fi
    fi
    if [[ -n "$net" ]]; then
        TS_M_LNCLI+=("--network=${net}")
    fi
    case "$rpc" in
        0.0.0.0:*|"[::]:"*|:*) rpc="localhost:${rpc##*:}" ;;
    esac
    if [[ -n "$rpc" ]]; then
        if [[ "$rpc" =~ $rpc_re ]]; then
            TS_M_LNCLI+=("--rpcserver=${rpc}")
        else
            TS_M_LNCLI_UNUSABLE+=("rpclisten")
        fi
    fi
}

# Prints the command that takes addresses $1... out of LND's node announcement (TS_M_LNCLI, as the
# node user; lncli takes --address_remove more than once), every word shell-quoted (%q) so that the
# printed line is safe to paste.
ts_m_announce_command() {
    local a
    local -a argv=(sudo -u "$TS_M_INV_USER" "${TS_M_LNCLI[@]}" peers updatenodeannouncement)
    for a in "$@"; do
        argv+=(--address_remove "$a")
    done
    printf '%q' "${argv[0]}"
    printf ' %q' "${argv[@]:1}"
}

# Records warning $1 of the announcement step (JSON warnings) and prints it as one line, as
# print_warning does but without interpreting backslash escapes in the text.
ts_m_announce_warn() {
    TS_M_ANN_WARNINGS+=("$1")
    printf '%b  %s\n' "${YELLOW}⚠${NC}" "$1" >&2
}

# After uninstall --managed, LND only: once LND answers lncli getinfo (TS_M_ANNOUNCE_WAIT seconds at
# most), takes every candidate of TS_M_ANN_ADDRS that LND announces out of its node announcement
# (lncli peers updatenodeannouncement --address_remove, as the node user), never the onion address or
# any other one. Another IPv4 address with the forwarded port stays, but a warning names it with its
# command. Sets TS_M_ANN_RESULT (removed, none, lnd_not_ready, failed, or skipped: CLN, LIT, or LND
# not running) and TS_M_ANN_WARNINGS (the exact command whenever a former VPN address may remain),
# and prints one line.
ts_m_announce_cleanup() {
    local cmd info="" state deadline limit="$TS_M_ANNOUNCE_WAIT" a unit="$TS_M_INV_UNIT"
    local -a stale=() failed=() others=()
    TS_M_ANN_RESULT="skipped"
    TS_M_ANN_WARNINGS=()
    case "$TS_M_INV_IMPL" in
        lnd|lit) ;;
        *) return 0 ;;
    esac
    if [[ ${#TS_M_ANN_ADDRS[@]} -eq 0 ]]; then
        ts_m_announce_warn "The former VPN address could not be determined (${TS_M_ANN_WHY}); if lncli getinfo still lists it under uris, remove it with: lncli peers updatenodeannouncement --address_remove <ip>:<port>"
        return 0
    fi
    if [[ "$TS_M_INV_IMPL" == "lit" ]]; then
        TS_M_LNCLI=(lncli)
        ts_m_announce_warn "LND in ${unit} may still announce the former VPN address ${TS_M_ANN_ADDRS[*]}; once it runs, remove it with: $(ts_m_announce_command "${TS_M_ANN_ADDRS[@]}")"
        return 0
    fi
    ts_m_lncli_argv "$unit"
    for a in "${TS_M_LNCLI_UNUSABLE[@]}"; do
        ts_m_announce_warn "The ${a} setting of ${unit} in its node config or on its command line is not a plain value, so lncli runs without it"
    done
    cmd=$(ts_m_announce_command "${TS_M_ANN_ADDRS[@]}")
    state=$(ts_m_unit_prop "$unit" ActiveState)
    case "$state" in
        active|activating|reloading) ;;
        *)
            ts_m_announce_warn "${unit} does not run; when it starts, it may announce the former VPN address ${TS_M_ANN_ADDRS[*]} again. Once it runs, remove it with: ${cmd}"
            return 0
            ;;
    esac
    if [[ ! "$limit" =~ ^[0-9]{1,3}$ ]]; then
        limit=120
    fi
    deadline=$((SECONDS + limit))
    until info=$(timeout --kill-after=2 15 "$RUNUSER_BIN" -u "$TS_M_INV_USER" -- "${TS_M_LNCLI[@]}" getinfo 2>/dev/null); do
        if [[ "$SECONDS" -ge "$deadline" ]]; then
            TS_M_ANN_RESULT="lnd_not_ready"
            ts_m_announce_warn "${unit} did not answer lncli getinfo within ${limit} s, so it may still announce the former VPN address ${TS_M_ANN_ADDRS[*]}. Once it answers, remove it with: ${cmd}"
            return 0
        fi
        sleep 2
    done
    for a in "${TS_M_ANN_ADDRS[@]}"; do
        if [[ "$info" == *"@${a}\""* ]]; then
            stale+=("$a")
        fi
    done
    while IFS= read -r a; do
        a="${a#@}"
        a="${a%\"}"
        if [[ -n "$a" ]] && ! ts_in_list "$a" "${TS_M_ANN_ADDRS[*]} ${others[*]}"; then
            others+=("$a")
        fi
    done < <(printf '%s\n' "$info" | grep -oE "@[0-9]{1,3}(\.[0-9]{1,3}){3}:${TS_M_ANN_PORT}\"" || true)
    for a in "${stale[@]}"; do
        if ! timeout --kill-after=2 30 "$RUNUSER_BIN" -u "$TS_M_INV_USER" -- "${TS_M_LNCLI[@]}" peers updatenodeannouncement \
            --address_remove "$a" >/dev/null 2>&1; then
            failed+=("$a")
        fi
    done
    if [[ ${#failed[@]} -gt 0 ]]; then
        TS_M_ANN_RESULT="failed"
        ts_m_announce_warn "${unit} still announces the former VPN address ${failed[*]}: the update failed. Remove it with: $(ts_m_announce_command "${failed[@]}")"
    elif [[ ${#stale[@]} -gt 0 ]]; then
        TS_M_ANN_RESULT="removed"
        print_success "Removed the former VPN address from the node announcement of ${unit}: ${stale[*]}"
    else
        TS_M_ANN_RESULT="none"
        if [[ ${#others[@]} -eq 0 ]]; then
            print_info "${unit} does not announce the former VPN address ${TS_M_ANN_ADDRS[*]}"
        fi
    fi
    if [[ ${#others[@]} -gt 0 ]]; then
        ts_m_announce_warn "${unit} also announces ${others[*]}, with the forwarded port of the TunnelSats config; if that is a former VPN address, remove it with: $(ts_m_announce_command "${others[@]}")"
    fi
}

# restart on a managed install: restarts only the tunnel; the kill switch keeps clearnet traffic
# blocked meanwhile, so Lightning keeps running.
ts_m_cmd_restart() {
    print_header "Restarting TunnelSats (managed)"
    print_info "Restarting ${TS_M_WG_UNIT}; the kill switch stays armed and keeps clearnet traffic blocked until the tunnel is back."
    if "$SYSTEMCTL_BIN" restart "$TS_M_WG_UNIT"; then
        print_success "${TS_M_WG_UNIT} restarted"
    else
        print_error "${TS_M_WG_UNIT} did not restart"
        journalctl -n 10 -u "$TS_M_WG_UNIT" --no-pager >&2 || true
        exit 1
    fi
    echo "Check the tunnel with: sudo tunnelsats verify"
    exit 0
}

# ---------------------------------------------------------------------------
# Managed mode: verify [--json] [--no-probe]
# Checks the kernel state and, unless --no-probe, probes from inside the slice. Verdicts:
#   protected (exit 0)  every check passes
#   degraded  (exit 5)  the kill switch holds and clearnet traffic is blocked, but the tunnel does
#                       not carry traffic (down, no handshake), or the emergency block is in effect
#                       (verified, no rule of another tool before it) and no probe got through
#   unsafe    (exit 4)  anything else; a check that cannot run counts as unsafe
#   unmanaged (exit 9)  a standard install: its kill switch is part of the tunnel; verify reports
#                       the checks that apply and never rates it protected or unsafe
# Configuration alone is never enough for "protected": every verdict rests on kernel state.
# The kill switch probe sends one datagram to the VPN server, which must be stopped on this host;
# the echo services and the IPv6 probe follow only when every kernel check of the unsafe class and
# the kill switch probe passed, so no probe shows the node's address to anyone new.
# A start guard in the Lightning unit (RaspiBlitz) relies on "verify --json --no-probe": exit 0 or
# 5 only while the dataplane holds for the unit named in "unit", never without a managed install,
# and no long wait: its one name lookup (the endpoint) is bounded (docs/managed-mode.md, RaspiBlitz).
# ---------------------------------------------------------------------------

TS_V_ID=()
TS_V_CLASS=()
TS_V_RESULT=()
TS_V_DETAIL=()
TS_V_GOT_THROUGH=0
TS_V_EMERGENCY_STATE="none"
# action_required of the verify document (raw JSON), set when the operator has to act
TS_V_ACTION_J="null"
TS_V_ACTION_TEXT=""
# Time limit of the endpoint lookup in seconds (ts_v_resolve_timeout), and "timeout" when the
# lookup got no answer within it (ts_v_read_endpoint)
TS_V_RESOLVE_TIMEOUT=5
TS_V_EP_LOOKUP=""

# Records check $1 with class $2 (unsafe or degraded, the class a failure falls into), result $3
# (pass, fail, skip) and detail $4.
ts_v_add() {
    TS_V_ID+=("$1")
    TS_V_CLASS+=("$2")
    TS_V_RESULT+=("$3")
    TS_V_DETAIL+=("$4")
}

# An install that was interrupted (state "installing") or an uninstall that did not complete
# (state "removing") is never rated protected.
ts_v_check_state() {
    case "$TS_M_INV_STATE" in
        installed)
            ts_v_add install_state unsafe pass "installed"
            ;;
        removing)
            ts_v_add install_state unsafe fail "an uninstall did not complete (state removing); run 'tunnelsats.sh uninstall --managed' again"
            ;;
        *)
            ts_v_add install_state unsafe fail "the install did not complete (state ${TS_M_INV_STATE:-unknown}); run 'tunnelsats.sh uninstall --managed', then install again"
            ;;
    esac
}

ts_v_check_attest() {
    local cur=""
    ts_m_read_attestation
    cur=$(ts_m_slice_cgroup_id) || cur=""
    if [[ "$TS_M_ATT_STATUS" != "valid" ]]; then
        ts_v_add attest unsafe fail "attestation ${TS_M_ATT_STATUS//_/ }"
    elif [[ -z "$cur" ]] || [[ "$cur" != "$TS_M_ATT_SLICE_ID" ]]; then
        ts_v_add attest unsafe fail "attested slice id ${TS_M_ATT_SLICE_ID} differs from the current one (${cur:-none})"
    else
        ts_v_add attest unsafe pass "armed for this boot, slice id ${cur}"
    fi
}

ts_v_check_nft() {
    local live="" ref="" rsfile
    live=$(ts_m_nft_live_listing) || live=""
    if [[ -z "$live" ]]; then
        ts_v_add nft_killswitch unsafe fail "table inet ${TS_M_NFT_TABLE} is missing"
        return 0
    fi
    rsfile=$(mktemp) || rsfile=""
    if [[ -n "$rsfile" ]] && ts_m_render_ruleset > "$rsfile"; then
        ref=$(ts_m_nft_reference_listing "$rsfile") || ref=""
    fi
    rm -f "$rsfile"
    if [[ -z "$ref" ]]; then
        ts_v_add nft_killswitch unsafe fail "the expected ruleset could not be loaded for comparison"
    elif [[ "$(printf '%s\n' "$live" | ts_m_nft_normalize)" == "$(printf '%s\n' "$ref" | ts_m_nft_normalize)" ]]; then
        ts_v_add nft_killswitch unsafe pass "table inet ${TS_M_NFT_TABLE} matches the expected ruleset"
    else
        ts_v_add nft_killswitch unsafe fail "table inet ${TS_M_NFT_TABLE} differs from the expected ruleset"
    fi
}

ts_v_check_slice() {
    local cur="" live="" named=0 line
    if ! cur=$(ts_m_slice_cgroup_id); then
        ts_v_add slice_id unsafe fail "${TS_M_SLICE} has no cgroup"
        return 0
    fi
    live=$(ts_m_nft_live_listing) || live=""
    while IFS= read -r line; do
        if [[ "$line" == *"socket cgroupv2 level 1 \"${TS_M_SLICE}\""* ]]; then
            named=$((named + 1))
        fi
    done < <(printf '%s\n' "$live")
    if [[ "$named" -ne 3 ]]; then
        ts_v_add slice_id unsafe fail "the rules name ${TS_M_SLICE} ${named} of 3 times (a stale cgroup id is listed as a number)"
    elif [[ -n "$TS_M_ATT_SLICE_ID" ]] && [[ "$cur" != "$TS_M_ATT_SLICE_ID" ]]; then
        ts_v_add slice_id unsafe fail "slice id ${cur} differs from the attested ${TS_M_ATT_SLICE_ID}"
    else
        ts_v_add slice_id unsafe pass "${TS_M_SLICE} id ${cur}, named by all 3 slice rules"
    fi
}

# The emergency block, checked only while any of its rules is present. $1 = 1 if it is in effect
# (ts_m_emergency_effective), $2 = the reason it is not. A block that is present but not in effect
# (incomplete, or a rule of another tool routes around it) is unsafe while it is the protection, so
# verify never reports clearnet traffic as blocked then. While the kill switch table matches
# (nft_killswitch, checked before), such rules are leftovers the verifier removes after its re-arm,
# as during a release: degraded. A rule of another tool before them comes before the kill switch's
# rules as well, and ip_rules reports it as unsafe.
ts_v_check_emergency() {
    if [[ "$1" -eq 1 ]]; then
        ts_v_add emergency_block unsafe pass "in effect for uid ${TS_M_INV_UID} (priority 21818 and 21819), no rule of another tool before it"
    elif ts_v_passed nft_killswitch; then
        ts_v_add emergency_block degraded fail "present for uid ${TS_M_INV_UID} but not in effect: ${2}; the kill switch is armed, and the verifier removes these rules"
    else
        ts_v_add emergency_block unsafe fail "present for uid ${TS_M_INV_UID} but not in effect: ${2}"
    fi
}

# The local network exemptions of the emergency block for node uid $1 (checked with the block).
# Missing ones cost only that local network, never safety: class degraded.
ts_v_check_emergency_lan() {
    local counts missing total
    counts=$(ts_m_emergency_lan_missing "$1")
    missing="${counts%% *}"
    total="${counts##* }"
    if [[ "$missing" -eq 0 ]]; then
        ts_v_add emergency_lan degraded pass "the local network stays reachable (${total} exemptions at priority ${TS_M_EMERGENCY_LAN_PRIO})"
    else
        ts_v_add emergency_lan degraded fail "${missing} of ${total} local network exemptions at priority ${TS_M_EMERGENCY_LAN_PRIO} are missing: Lightning cannot reach those local networks"
    fi
}

ts_v_check_rules() {
    local fam listing name n line problems=() exit_node=0
    if ts_m_tailscale_exit_node; then
        exit_node=1
    fi
    for fam in 4 6; do
        if [[ "$fam" == "6" ]] && ! ts_m_ipv6_available; then
            continue
        fi
        if ! listing=$("$IP_BIN" "-${fam}" rule show 2>/dev/null); then
            problems+=("IPv${fam} rules cannot be read")
            continue
        fi
        for name in main mark uid; do
            if [[ "$name" == "uid" ]] && [[ "$TS_M_INV_BACKSTOP" != "1" ]]; then
                continue
            fi
            n=$(ts_m_rule_count "$listing" "$(ts_m_rule_prio "$name")" "$(ts_m_rule_selector "$name" "$TS_M_INV_UID")")
            if [[ "$n" -ne 1 ]]; then
                problems+=("IPv${fam} rule $(ts_m_rule_prio "$name") present ${n} times")
            fi
        done
        # Rules of other tools before 21820 (the emergency block is checked on its own)
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                problems+=("$line")
            fi
        done < <(ts_m_rules_before "$fam" "$listing" "$TS_M_PRIO_MAIN" "$exit_node")
    done
    if [[ ${#problems[@]} -eq 0 ]]; then
        ts_v_add ip_rules unsafe pass "${TS_M_PRIO_MAIN} and ${TS_M_PRIO_MARK}$([[ "$TS_M_INV_BACKSTOP" == "1" ]] && echo " and ${TS_M_PRIO_UID}") present, nothing unexpected before them"
    else
        ts_v_add ip_rules unsafe fail "$(IFS=';'; echo "${problems[*]}")"
    fi
}

ts_v_check_table() {
    local fam routes line bh tun other iface_up=0 problems=() route_missing=0 missing_msg
    if "$IP_BIN" link show dev "$TS_M_IFACE" >/dev/null 2>&1; then
        iface_up=1
    fi
    for fam in 4 6; do
        if [[ "$fam" == "6" ]] && ! ts_m_ipv6_available; then
            continue
        fi
        if ! routes=$(ts_m_table_routes "$fam"); then
            problems+=("IPv${fam} table cannot be read")
            continue
        fi
        bh=0
        tun=0
        other=0
        while IFS= read -r line; do
            if [[ -z "${line//[[:space:]]/}" ]]; then
                continue
            fi
            if ts_m_is_blackhole_line "$line"; then
                bh=$((bh + 1))
            elif [[ "$fam" == "4" ]] && ts_m_is_tunnel_route_line "$line"; then
                tun=$((tun + 1))
            else
                other=$((other + 1))
            fi
        done < <(printf '%s\n' "$routes")
        if [[ "$bh" -ne 1 ]]; then
            problems+=("IPv${fam} blackhole present ${bh} times")
        fi
        if [[ "$other" -gt 0 ]]; then
            problems+=("IPv${fam} table holds ${other} foreign route(s)")
        fi
        if [[ "$fam" == "4" ]] && [[ "$iface_up" -eq 1 ]] && [[ "$tun" -eq 0 ]]; then
            route_missing=1
        fi
    done
    missing_msg="${TS_M_IFACE} is up but its route in table ${TS_M_RT_TABLE} is missing"
    if [[ ${#problems[@]} -gt 0 ]]; then
        # Any problem other than the missing tunnel route (either family) is unsafe
        if [[ "$route_missing" -eq 1 ]]; then
            problems+=("$missing_msg")
        fi
        ts_v_add table_51820 unsafe fail "$(IFS=';'; echo "${problems[*]}")"
    elif [[ "$route_missing" -eq 1 ]]; then
        # Only the tunnel route is missing: marked traffic ends in the blackhole, nothing leaves
        # outside the tunnel
        ts_v_add table_51820 degraded fail "$missing_msg"
    elif [[ "$iface_up" -eq 1 ]]; then
        ts_v_add table_51820 unsafe pass "blackhole present, default dev ${TS_M_IFACE} while the tunnel is up"
    else
        ts_v_add table_51820 unsafe pass "blackhole present, tunnel route absent while the tunnel is down"
    fi
}

ts_v_check_dropin() {
    local paths slice want="${TS_M_UNIT_DIR}/${TS_M_INV_UNIT}.d/${TS_M_DROPIN_NAME}"
    paths=$(ts_m_unit_prop "$TS_M_INV_UNIT" DropInPaths)
    slice=$(ts_m_unit_prop "$TS_M_INV_UNIT" Slice)
    if [[ " ${paths} " != *" ${want} "* ]]; then
        ts_v_add ln_dropin unsafe fail "${want} is not loaded for ${TS_M_INV_UNIT}"
    elif [[ "$slice" != "$TS_M_SLICE" ]]; then
        ts_v_add ln_dropin unsafe fail "${TS_M_INV_UNIT} is configured for slice ${slice:-unknown}"
    else
        ts_v_add ln_dropin unsafe pass "drop-in loaded, Slice=${TS_M_SLICE}"
    fi
}

ts_v_check_membership() {
    local state cg dir pid path total=0 outside=0 f
    state=$(ts_m_unit_prop "$TS_M_INV_UNIT" ActiveState)
    if [[ "$state" != "active" ]] && [[ "$state" != "reloading" ]]; then
        ts_v_add ln_membership degraded fail "${TS_M_INV_UNIT} is ${state:-unknown}"
        return 0
    fi
    cg=$(ts_m_unit_prop "$TS_M_INV_UNIT" ControlGroup)
    if [[ "$cg" != "/${TS_M_SLICE}/"* ]]; then
        ts_v_add ln_membership unsafe fail "${TS_M_INV_UNIT} runs in ${cg:-an unknown cgroup}, outside ${TS_M_SLICE}"
        return 0
    fi
    dir="${TS_FS_ROOT}${TS_M_CGROUP_ROOT}${cg}"
    while IFS= read -r f; do
        while IFS= read -r pid; do
            if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
                continue
            fi
            path=$(sed -n 's/^0:://p' "${TS_FS_ROOT}/proc/${pid}/cgroup" 2>/dev/null | head -n 1) || path=""
            if [[ -z "$path" ]]; then
                # The process ended between the two reads
                continue
            fi
            total=$((total + 1))
            if [[ "$path" != "/${TS_M_SLICE}/"* ]]; then
                outside=$((outside + 1))
            fi
        done < "$f"
    done < <(find "$dir" -name cgroup.procs -type f 2>/dev/null)
    if [[ "$total" -eq 0 ]]; then
        ts_v_add ln_membership unsafe fail "no processes found in ${cg}"
    elif [[ "$outside" -gt 0 ]]; then
        ts_v_add ln_membership unsafe fail "${outside} of ${total} process(es) of ${TS_M_INV_UNIT} run outside ${TS_M_SLICE}"
    else
        ts_v_add ln_membership unsafe pass "${total} process(es), all under /${TS_M_SLICE}/"
    fi
}

# Runs probe "$@" (see ts_m_cmd_probe) in a transient unit of the slice; $1 = user ("" for root).
ts_v_run_probe() {
    local user="$1"
    shift
    local -a args=(--quiet --wait --pipe --collect "--slice=${TS_M_SLICE}" -p RuntimeMaxSec=60)
    if [[ -n "$user" ]]; then
        args+=("--uid=${user}")
    fi
    "$SYSTEMD_RUN_BIN" "${args[@]}" "$TS_M_BIN" managed-probe "$@" </dev/null 2>/dev/null
}

# Prints the result for key $2 (an echo URL or a probe address) in probe output $1: the last word of
# its "answer" or "send" line. Fails if the probe did not run inside the slice or reported nothing.
ts_v_probe_answer() {
    local out="$1" key="$2" line cg=""
    while IFS= read -r line; do
        case "$line" in
            "cgroup "*) cg="${line#cgroup }" ;;
        esac
    done < <(printf '%s\n' "$out")
    if [[ "$cg" != "/${TS_M_SLICE}/"* ]]; then
        return 1
    fi
    while IFS= read -r line; do
        if [[ "$line" == "answer ${key} "* ]] || [[ "$line" == "send ${key} "* ]]; then
            echo "${line##* }"
            return 0
        fi
    done < <(printf '%s\n' "$out")
    return 1
}

# Resolves the host of URL $1 for IP family $2 (4 or 6) as root, outside the slice, into TS_V_T_IP.
# Fails if the URL cannot be parsed or the host has no address of that family.
ts_v_target() {
    local url="$1" fam="$2" rest host=""
    TS_V_T_IP=""
    rest="${url#*://}"
    rest="${rest%%/*}"
    if [[ "$rest" =~ ^\[([0-9A-Fa-f:.]+)\](:[0-9]{1,5})?$ ]]; then
        host="${BASH_REMATCH[1]}"
    elif [[ "$rest" =~ ^([A-Za-z0-9.-]+)(:[0-9]{1,5})?$ ]]; then
        host="${BASH_REMATCH[1]}"
    else
        return 1
    fi
    if [[ "$fam" == "4" ]] && valid_ipv4 "$host"; then
        TS_V_T_IP="$host"
    elif [[ "$fam" == "6" ]] && [[ "$host" == *:* ]]; then
        TS_V_T_IP="$host"
    elif valid_ipv4 "$host" || [[ "$host" == *:* ]]; then
        # An address of the other family
        return 1
    else
        # IPv4-mapped answers of ahostsv6 are IPv4 traffic, not IPv6
        TS_V_T_IP=$("$GETENT_BIN" "ahostsv${fam}" "$host" 2>/dev/null | awk '$1 !~ /^::ffff:/ { print $1; exit }') || TS_V_T_IP=""
        if [[ -z "$TS_V_T_IP" ]]; then
            return 1
        fi
    fi
    return 0
}

# Prints the interface of the route to address $2 (IP family $1), as root sees it outside the slice;
# nothing if there is none.
ts_v_route_dev() {
    local out=""
    out=$("$IP_BIN" "-${1}" route get "$2" 2>/dev/null) || out=""
    if [[ "$out" =~ [[:space:]]dev[[:space:]]+([^[:space:]]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
    return 0
}

# Prints why the probes after the kill switch probe must not run, nothing if they may: a kernel check
# of the unsafe class that did not pass, a kill switch probe that did not pass ($1 = 1 if it did), or
# emergency rules that are present ($2 = 1 if any is). A check that fails only in its degraded class
# (Lightning stopped, the tunnel route missing) does not stop them. While emergency rules are present
# the verdict cannot be protected, so the echo services are not contacted then; the kill switch
# probe still tests whichever protection holds.
ts_v_probe_gate() {
    local ks_pass="$1" block="$2" i
    for i in "${!TS_V_ID[@]}"; do
        case "${TS_V_ID[$i]}" in
            install_state|attest|nft_killswitch|slice_id|ip_rules|emergency_block|table_51820|ln_dropin|ln_membership)
                if [[ "${TS_V_RESULT[$i]}" != "pass" ]] && [[ "${TS_V_CLASS[$i]}" == "unsafe" ]]; then
                    echo "${TS_V_ID[$i]} did not pass"
                    return 0
                fi
                ;;
        esac
    done
    if [[ "$ks_pass" -ne 1 ]]; then
        echo "the kill switch probe did not pass"
    elif [[ "$block" -eq 1 ]]; then
        echo "emergency rules are present (the verifier removes them once the kill switch is armed)"
    fi
    return 0
}

# Succeeds if check $1 is recorded and passed.
ts_v_passed() {
    local i
    for i in "${!TS_V_ID[@]}"; do
        if [[ "${TS_V_ID[$i]}" == "$1" ]] && [[ "${TS_V_RESULT[$i]}" == "pass" ]]; then
            return 0
        fi
    done
    return 1
}

# Probes from inside the slice. $1 = 1 while any emergency rule is present (in effect or not). Uses
# TS_V_ENDPOINT_IP, TS_V_ECHO_URLS and TS_V_V6_URL, and sets TS_V_GOT_THROUGH to 1 if a datagram left
# this host.
#   killswitch_probe  one UDP datagram from the slice to the VPN server (the WireGuard endpoint,
#                     port 9) must be stopped on this host. It needs no DNS and no reply, and if the
#                     protection were broken it would reach only the VPN server, which knows the
#                     node's address as its WireGuard peer anyway. Normally it runs as root (the
#                     cgroup classification on its own; the uid backstop does not cover root) with
#                     the socket bound to the regular interface, which forces that interface while
#                     the tunnel is up. A bound socket skips route errors (the kernel then treats the
#                     destination as on-link), so this exercises the nft kill chain, which drops the
#                     datagram (EPERM). While emergency rules are present (in effect or not) and the
#                     kill switch table does not match (nft_killswitch did not pass), it runs as the
#                     node user with an unbound socket, as the daemon's sockets are, and exercises
#                     the uid blackhole (EINVAL) and any rule before it. With the table in place,
#                     the kill chain is what stops the slice's direct path, so the root probe tests
#                     that: the node user's datagram would be routed into the tunnel, and its "sent"
#                     could not be told apart from a datagram that left this host.
#   egress_probe      both echo services must see the endpoint address. Asked only when every kernel
#                     check of the unsafe class and the kill switch probe passed and no emergency
#                     rule is present (ts_v_probe_gate), that is, once the direct path was shown
#                     closed.
#   ipv6_probe        one UDP datagram from the slice to the TunnelSats host's IPv6 address must be
#                     stopped on this host (the IPv6 drop, EPERM); behind the same gate.
ts_v_check_probes() {
    local block="$1" user="" iface="-" via="" out="" w="" a1="" a2="" a wrong="" ks_pass=0 gate=""
    TS_V_GOT_THROUGH=0
    if [[ "$block" -eq 1 ]] && ! ts_v_passed nft_killswitch; then
        user="$TS_M_INV_USER"
    elif [[ -n "$TS_V_ENDPOINT_IP" ]]; then
        iface=$(ts_v_route_dev 4 "$TS_V_ENDPOINT_IP")
        via=" through ${iface}"
    fi
    if [[ -z "$TS_V_ENDPOINT_IP" ]]; then
        ts_v_add killswitch_probe unsafe fail "could not run: the endpoint address is unknown"
    elif [[ -z "$iface" ]]; then
        ts_v_add killswitch_probe unsafe fail "could not run: no route to ${TS_V_ENDPOINT_IP}"
    elif ! out=$(ts_v_run_probe "$user" send 4 "$iface" "$TS_V_ENDPOINT_IP") || \
        ! w=$(ts_v_probe_answer "$out" "$TS_V_ENDPOINT_IP"); then
        ts_v_add killswitch_probe unsafe fail "could not run a probe unit inside ${TS_M_SLICE}"
    else
        case "$(ts_m_probe_classify "$w")" in
            blocked)
                ks_pass=1
                ts_v_add killswitch_probe unsafe pass "a datagram from inside the slice to ${TS_V_ENDPOINT_IP}${via} was stopped on this host (${w})"
                ;;
            left)
                TS_V_GOT_THROUGH=1
                ts_v_add killswitch_probe unsafe fail "a datagram from inside the slice to ${TS_V_ENDPOINT_IP}${via} left this host; nothing stopped it"
                ;;
            *)
                ts_v_add killswitch_probe unsafe fail "could not run (${w})"
                ;;
        esac
    fi
    gate=$(ts_v_probe_gate "$ks_pass" "$block")

    # Egress: the node user inside the slice must appear with the endpoint address
    if [[ -n "$gate" ]]; then
        ts_v_add egress_probe unsafe skip "not run: ${gate}, so the echo services were not contacted"
    elif ! out=$(ts_v_run_probe "$TS_M_INV_USER" egress4 "${TS_V_ECHO_URLS[@]}") || \
        ! a1=$(ts_v_probe_answer "$out" "${TS_V_ECHO_URLS[0]}") || ! a2=$(ts_v_probe_answer "$out" "${TS_V_ECHO_URLS[1]}"); then
        ts_v_add egress_probe unsafe fail "could not run a probe unit inside ${TS_M_SLICE} as ${TS_M_INV_USER}"
    else
        for a in "$a1" "$a2"; do
            if [[ "$a" != "-" ]] && [[ "$a" != "$TS_V_ENDPOINT_IP" ]]; then
                wrong="$a"
            fi
        done
        if [[ -n "$wrong" ]]; then
            ts_v_add egress_probe unsafe fail "egress address ${wrong} differs from the endpoint address ${TS_V_ENDPOINT_IP:-unknown}"
        elif [[ "$a1" == "-" ]] && [[ "$a2" == "-" ]]; then
            ts_v_add egress_probe degraded fail "no answer from inside the slice (clearnet traffic is blocked)"
        elif [[ "$a1" == "-" ]] || [[ "$a2" == "-" ]]; then
            ts_v_add egress_probe degraded fail "only one echo service answered (${TS_V_ENDPOINT_IP}); the egress is not confirmed"
        else
            ts_v_add egress_probe unsafe pass "egress ${a1} equals the endpoint address"
        fi
    fi

    # IPv6: a datagram from the slice to the TunnelSats host's IPv6 address must be stopped here
    if [[ -n "$gate" ]]; then
        ts_v_add ipv6_probe unsafe skip "not run: ${gate}"
    elif ! ts_m_ipv6_available; then
        ts_v_add ipv6_probe unsafe skip "not run: this host has no IPv6"
    elif ! ts_v_target "$TS_V_V6_URL" 6; then
        ts_v_add ipv6_probe unsafe skip "not run: ${TS_V_V6_URL} has no IPv6 address"
    elif ! out=$(ts_v_run_probe "$TS_M_INV_USER" send 6 - "$TS_V_T_IP") || \
        ! w=$(ts_v_probe_answer "$out" "$TS_V_T_IP"); then
        ts_v_add ipv6_probe unsafe fail "could not run a probe unit inside ${TS_M_SLICE} as ${TS_M_INV_USER}"
    else
        case "$(ts_m_probe_classify "$w")" in
            blocked)
                ts_v_add ipv6_probe unsafe pass "an IPv6 datagram from inside the slice to ${TS_V_T_IP} was stopped on this host (${w})"
                ;;
            left)
                TS_V_GOT_THROUGH=1
                ts_v_add ipv6_probe unsafe fail "an IPv6 datagram from inside the slice to ${TS_V_T_IP} left this host; nothing stopped it"
                ;;
            *)
                ts_v_add ipv6_probe unsafe fail "could not run (${w})"
                ;;
        esac
    fi
}

# $1 = interface (default: the managed tunnel).
ts_v_check_handshake() {
    local iface="${1:-$TS_M_IFACE}" out="" ts="" age now
    if ! out=$("$WG_BIN" show "$iface" latest-handshakes 2>/dev/null); then
        ts_v_add wg_handshake degraded fail "${iface} is down"
        return 0
    fi
    ts=$(printf '%s\n' "$out" | awk 'NR == 1 { print $2 }')
    if [[ ! "$ts" =~ ^[0-9]+$ ]] || [[ "$ts" -eq 0 ]]; then
        ts_v_add wg_handshake degraded fail "no handshake yet"
        return 0
    fi
    now=$(date +%s)
    age=$((now - ts))
    if [[ "$age" -lt "$TS_M_HANDSHAKE_MAX_AGE" ]]; then
        ts_v_add wg_handshake degraded pass "${age} s ago"
    else
        ts_v_add wg_handshake degraded fail "last handshake ${age} s ago"
    fi
}

# Prints the time limit of the endpoint lookup in seconds: TS_VERIFY_RESOLVE_TIMEOUT (tests), else 5.
# Fails for anything but a whole number from 1 to 999.
ts_v_resolve_timeout() {
    local t="${TS_VERIFY_RESOLVE_TIMEOUT:-5}"
    if [[ ! "$t" =~ ^[1-9][0-9]{0,2}$ ]]; then
        return 1
    fi
    echo "$t"
}

# Reads the endpoint of the managed tunnel config (or of config $1) into TS_V_EP_HOST, TS_V_EP_PORT,
# TS_V_ENDPOINT_IP and TS_V_VPN_PORT (the private key is never read into a variable). A host name is
# resolved once, for at most TS_V_RESOLVE_TIMEOUT seconds: a start guard runs verify before every
# Lightning start, so a name server that does not answer must not hold it up. TS_V_EP_LOOKUP is
# "timeout" when the lookup got no answer in time, else empty.
ts_v_read_endpoint() {
    local conf="${1:-${TS_FS_ROOT}${TS_M_WG_CONF}}" ep="" out="" rc=0
    TS_V_EP_HOST=""
    TS_V_EP_PORT=""
    TS_V_ENDPOINT_IP=""
    TS_V_EP_LOOKUP=""
    TS_V_VPN_PORT=""
    ep=$(sed -nE 's/^[[:space:]]*Endpoint[[:space:]]*=[[:space:]]*([^[:space:]#]+).*/\1/Ip' "$conf" 2>/dev/null | head -n 1) || ep=""
    if ts_detect_parse_endpoint "$ep"; then
        TS_V_EP_HOST="$TSD_CFG_EP_HOST"
        TS_V_EP_PORT="$TSD_CFG_EP_PORT"
        if valid_ipv4 "$TS_V_EP_HOST"; then
            TS_V_ENDPOINT_IP="$TS_V_EP_HOST"
        else
            out=$(timeout --kill-after=1 "${TS_V_RESOLVE_TIMEOUT:-5}" "$GETENT_BIN" ahostsv4 "$TS_V_EP_HOST" 2>/dev/null) || rc=$?
            TS_V_ENDPOINT_IP=$(printf '%s\n' "$out" | awk 'NR == 1 { print $1 }')
            if [[ -z "$TS_V_ENDPOINT_IP" ]] && { [[ "$rc" -eq 124 ]] || [[ "$rc" -eq 137 ]]; }; then
                TS_V_EP_LOOKUP="timeout"
            fi
        fi
    fi
    TS_V_VPN_PORT=$(ts_config_vpn_port "$conf" 2>/dev/null) || TS_V_VPN_PORT=""
}

ts_v_check_endpoint() {
    local out="" live=""
    if ! out=$("$WG_BIN" show "$TS_M_IFACE" endpoints 2>/dev/null); then
        ts_v_add wg_endpoint degraded fail "${TS_M_IFACE} is down"
        return 0
    fi
    live=$(printf '%s\n' "$out" | awk 'NR == 1 { print $2 }')
    if [[ -z "$TS_V_ENDPOINT_IP" ]] && [[ "$TS_V_EP_LOOKUP" == "timeout" ]]; then
        ts_v_add wg_endpoint degraded fail "the lookup of the configured endpoint ${TS_V_EP_HOST} got no answer within ${TS_V_RESOLVE_TIMEOUT:-5} s"
    elif [[ -z "$TS_V_ENDPOINT_IP" ]]; then
        ts_v_add wg_endpoint degraded fail "the configured endpoint ${TS_V_EP_HOST:-?} does not resolve"
    elif [[ "$live" == "${TS_V_ENDPOINT_IP}:${TS_V_EP_PORT}" ]]; then
        ts_v_add wg_endpoint degraded pass "${live}"
    else
        ts_v_add wg_endpoint degraded fail "live endpoint ${live:-none} differs from ${TS_V_ENDPOINT_IP}:${TS_V_EP_PORT}"
    fi
}

# Computes TS_V_VERDICT, TS_V_EXIT and TS_V_CLEARNET_BLOCKED from the recorded checks and $1 (1 if
# the emergency block is in effect, ts_m_emergency_effective). While it is, the verdict is degraded
# unless a probe got through (TS_V_GOT_THROUGH), which makes it unsafe. A block that is present but
# not in effect is a failed emergency_block check, so the verdict is unsafe.
ts_v_verdict() {
    local emergency="$1" i unsafe=0 degraded=0
    for i in "${!TS_V_ID[@]}"; do
        if [[ "${TS_V_RESULT[$i]}" != "fail" ]]; then
            continue
        fi
        if [[ "${TS_V_CLASS[$i]}" == "unsafe" ]]; then
            unsafe=$((unsafe + 1))
        else
            degraded=$((degraded + 1))
        fi
    done
    TS_V_CLEARNET_BLOCKED=0
    if [[ "$emergency" -eq 1 ]] && [[ "${TS_V_GOT_THROUGH:-0}" -eq 1 ]]; then
        TS_V_VERDICT="unsafe"
        TS_V_EXIT=4
    elif [[ "$emergency" -eq 1 ]]; then
        TS_V_VERDICT="degraded"
        TS_V_EXIT=5
        TS_V_CLEARNET_BLOCKED=1
    elif [[ "$unsafe" -gt 0 ]]; then
        TS_V_VERDICT="unsafe"
        TS_V_EXIT=4
    elif [[ "$degraded" -gt 0 ]]; then
        TS_V_VERDICT="degraded"
        TS_V_EXIT=5
        if [[ "${TS_V_GOT_THROUGH:-0}" -eq 0 ]]; then
            TS_V_CLEARNET_BLOCKED=1
        fi
    else
        TS_V_VERDICT="protected"
        TS_V_EXIT=0
    fi
}

# Succeeds if a check about the tunnel itself failed (handshake, endpoint, egress, tunnel route).
ts_v_tunnel_failed() {
    local i
    for i in "${!TS_V_ID[@]}"; do
        if [[ "${TS_V_RESULT[$i]}" == "fail" ]]; then
            case "${TS_V_ID[$i]}" in
                wg_handshake|wg_endpoint|egress_probe|table_51820) return 0 ;;
            esac
        fi
    done
    return 1
}

# Prints the checks that failed, one per line.
ts_v_print_failed() {
    local i
    for i in "${!TS_V_ID[@]}"; do
        if [[ "${TS_V_RESULT[$i]}" == "fail" ]]; then
            echo "  - ${TS_V_ID[$i]}: ${TS_V_DETAIL[$i]}"
        fi
    done
}

# Prints the check list as a JSON array into TS_R.
ts_v_checks_json() {
    local i items=()
    for i in "${!TS_V_ID[@]}"; do
        ts_j_obj s:id "${TS_V_ID[$i]}" s:class "${TS_V_CLASS[$i]}" s:result "${TS_V_RESULT[$i]}" s:detail "${TS_V_DETAIL[$i]}"
        items+=("$TS_R")
    done
    ts_j_arr "${items[@]}"
}

# Prints the result of verify on a managed install (human summary or the contract-1 document) and
# exits with its code. $1 = emergency block (1|0), $2 = probes (run|skipped).
ts_v_report() {
    local emergency="$1" probes="$2" i errors=() checks_j errors_j ep_j code suffix=""
    if [[ "$TS_JSON" -eq 1 ]]; then
        for i in "${!TS_V_ID[@]}"; do
            if [[ "${TS_V_RESULT[$i]}" == "fail" ]]; then
                code="E_${TS_V_ID[$i]^^}"
                ts_j_error "$code" "${TS_V_CLASS[$i]}" "${TS_V_DETAIL[$i]}"
                errors+=("$TS_R")
            fi
        done
        ts_v_checks_json
        checks_j="$TS_R"
        ts_j_arr "${errors[@]}"
        errors_j="$TS_R"
        ts_j_obj sn:host "${TS_V_EP_HOST:-}" sn:ipv4 "${TS_V_ENDPOINT_IP:-}" i:port "${TS_V_EP_PORT:-}" i:vpn_port "${TS_V_VPN_PORT:-}"
        ep_j="$TS_R"
        ts_j_obj s:verdict "$TS_V_VERDICT" b:clearnet_blocked "$TS_V_CLEARNET_BLOCKED" b:emergency_block "$emergency" \
            s:emergency_state "${TS_V_EMERGENCY_STATE:-none}" \
            b:managed 1 s:install_state "$TS_M_INV_STATE" sn:profile "${TS_M_INV_PROFILE:-}" sn:impl "${TS_M_INV_IMPL:-}" \
            sn:unit "${TS_M_INV_UNIT:-}" s:iface "$TS_M_IFACE" s:probes "$probes" r:endpoint "$ep_j" r:checks "$checks_j" \
            r:action_required "${TS_V_ACTION_J:-null}"
        ts_json_document "$TS_V_EXIT" "$errors_j" "${TS_R:1:${#TS_R}-2}"
        exit "$TS_V_EXIT"
    fi
    if [[ "$TS_M_INV_STATE" == "damaged" ]]; then
        echo -e "${BOLD}TunnelSats verify${NC}: managed, install record damaged, interface ${TS_M_IFACE}"
    else
        echo -e "${BOLD}TunnelSats verify${NC}: managed (${TS_M_INV_PROFILE}), ${TS_M_INV_UNIT}, interface ${TS_M_IFACE}"
    fi
    print_line
    for i in "${!TS_V_ID[@]}"; do
        printf '  %-17s %-5s %s\n' "${TS_V_ID[$i]}" "${TS_V_RESULT[$i]}" "${TS_V_DETAIL[$i]}"
    done
    print_line
    if [[ "$probes" == "skipped" ]]; then
        suffix=" (kernel checks only, probes skipped)"
    fi
    case "$TS_V_VERDICT" in
        protected)
            echo -e "${GREEN}Protected${suffix}${NC}"
            ;;
        degraded)
            if [[ "$emergency" -eq 1 ]]; then
                echo -e "${YELLOW}Emergency block active: Lightning clearnet traffic blocked, Tor and the local network keep working${suffix}${NC}"
            elif ts_v_tunnel_failed; then
                echo -e "${YELLOW}Tunnel down: clearnet traffic blocked, the kill switch holds${suffix}${NC}"
                ts_v_print_failed
            else
                echo -e "${YELLOW}Degraded: clearnet traffic blocked, the kill switch holds${suffix}${NC}"
                ts_v_print_failed
            fi
            ;;
        *)
            echo -e "${RED}Not protected${suffix}${NC}"
            ts_v_print_failed
            ;;
    esac
    if [[ -n "$TS_V_ACTION_TEXT" ]]; then
        echo "Action required: ${TS_V_ACTION_TEXT}"
    fi
    exit "$TS_V_EXIT"
}

# Prints the numeric host UID (>0) of the Lightning daemon for an unmanaged install, or nothing if
# none can be determined (for example on a Docker install or when no Lightning account exists).
ts_v_unmanaged_uid() {
    local conf="${1:-}" uid="" user="" unit=""
    if [[ -n "$conf" ]] && [[ ! -f "$conf" ]] && [[ -f "${TS_FS_ROOT}${conf}" ]]; then
        conf="${TS_FS_ROOT}${conf}"
    fi
    if [[ -n "$conf" ]] && [[ -f "$conf" ]]; then
        uid=$(sed -nE 's/.*tunnelsats-route-guard\.sh[[:space:]]+(arm|check|release)[[:space:]]+[^[:space:]]+[[:space:]]+([1-9][0-9]{0,9})([[:space:]"#]|$).*/\2/p' "$conf" 2>/dev/null | head -n 1) || uid=""
        if [[ "$uid" =~ ^[1-9][0-9]{0,9}$ ]]; then
            echo "$uid"
            return 0
        fi
        user=$(sed -nE 's/.*[[:space:]]skuid[[:space:]]+([a-z_][a-z0-9_.-]{0,31})[[:space:]].*/\1/p' "$conf" 2>/dev/null | head -n 1) || user=""
        if [[ -n "$user" ]] && [[ "$user" != "root" ]]; then
            uid=$(id -u "$user" 2>/dev/null) || uid=$("$GETENT_BIN" passwd "$user" 2>/dev/null | awk -F: 'NR == 1 { print $3 }') || uid=""
            if [[ "$uid" =~ ^[1-9][0-9]{0,9}$ ]]; then
                echo "$uid"
                return 0
            fi
        fi
    fi
    for unit in lnd.service tlnd.service slnd.service lightningd.service tlightningd.service slightningd.service litd.service lit.service; do
        if [[ -f "${TS_FS_ROOT}/etc/systemd/system/${unit}.d/tunnelsats-cgroup.conf" ]] || \
            grep -qE '^[[:space:]]*ExecStart[[:space:]]*=.*cgexec' "${TS_FS_ROOT}/etc/systemd/system/${unit}" 2>/dev/null; then
            user=$(ts_m_unit_prop "$unit" User)
            if [[ -z "$user" ]] && [[ -f "${TS_FS_ROOT}/etc/systemd/system/${unit}" ]]; then
                user=$(sed -nE 's/^[[:space:]]*User[[:space:]]*=[[:space:]]*([^[:space:]#]+).*/\1/p' "${TS_FS_ROOT}/etc/systemd/system/${unit}" 2>/dev/null | head -n 1) || user=""
            fi
            if [[ "$user" =~ ^[1-9][0-9]{0,9}$ ]]; then
                echo "$user"
                return 0
            elif [[ -n "$user" ]] && [[ "$user" != "root" ]]; then
                uid=$(id -u "$user" 2>/dev/null) || uid=$("$GETENT_BIN" passwd "$user" 2>/dev/null | awk -F: 'NR == 1 { print $3 }') || uid=""
                if [[ "$uid" =~ ^[1-9][0-9]{0,9}$ ]]; then
                    echo "$uid"
                    return 0
                fi
            fi
        fi
    done
    return 0
}

# verify on a standard (not managed) install, $1 = its kind, $2 = probes (run|skipped): runs the
# checks that apply (handshake of the installed tunnel, its kill switch table, and ipv6_probe when
# probes run) and reports "unmanaged" (exit 9), or "unsafe" (exit 4) if an IPv6 datagram leaves the host.
ts_v_unmanaged() {
    local kind="$1" probes="${2:-skipped}" iface="" age="" up=0 ks=0 n checks_j ep_j text probe_state="skipped" ipv6_leak_detail=""
    ts_detect_config
    iface="$TSD_CFG_IFACE"
    if [[ -z "$iface" ]]; then
        ts_v_add wg_handshake degraded skip "no single TunnelSats config to check (${TSD_CFG_SELECTION:-none})"
        ts_v_add legacy_killswitch degraded skip "no single TunnelSats config to check"
    else
        ts_v_check_handshake "$iface"
        n=$((${#TS_V_ID[@]} - 1))
        if [[ "${TS_V_RESULT[$n]}" == "pass" ]]; then
            up=1
            age="${TS_V_DETAIL[$n]}"
        fi
        if "$NFT_BIN" list table ip "$iface" >/dev/null 2>&1 || "$NFT_BIN" list table inet "$iface" >/dev/null 2>&1; then
            ks=1
            ts_v_add legacy_killswitch degraded pass "nft table ${iface} present (it exists while the tunnel is up)"
        else
            ts_v_add legacy_killswitch degraded fail "nft table ${iface} not present (it exists only while the tunnel is up)"
        fi
        if [[ "$probes" == "run" ]]; then
            probe_state="run"
            local probe_bin="$TS_M_BIN" probe_tmp="" probe_uid="" probe_out="" probe_w="" probe_line
            local -a probe_cmd=()
            if ! ts_m_ipv6_available; then
                ts_v_add ipv6_probe unsafe skip "not run: this host has no IPv6"
            elif ! ts_v_target "$TS_V_V6_URL" 6; then
                ts_v_add ipv6_probe unsafe skip "not run: ${TS_V_V6_URL} has no IPv6 address"
            else
                if [[ -x "${TS_FS_ROOT}${probe_bin}" ]]; then
                    probe_cmd=("$probe_bin")
                elif [[ -n "${TS_SCRIPT_PATH:-}" ]] && [[ -r "$TS_SCRIPT_PATH" ]]; then
                    local stage_dir="${TS_FS_ROOT}/usr/local/sbin"
                    mkdir -p "$stage_dir" 2>/dev/null || stage_dir="${TMPDIR:-/tmp}"
                    probe_tmp=$(mktemp "${stage_dir}/.tunnelsats-probe.XXXXXX" 2>/dev/null) || probe_tmp=""
                    if [[ -n "$probe_tmp" ]] && install -m 0644 "$TS_SCRIPT_PATH" "$probe_tmp" 2>/dev/null; then
                        probe_cmd=(/bin/bash "$probe_tmp")
                    else
                        rm -f "$probe_tmp" 2>/dev/null || true
                        probe_tmp=""
                        probe_cmd=(/bin/bash "$TS_SCRIPT_PATH")
                    fi
                else
                    probe_cmd=(/bin/bash "${TS_SCRIPT_PATH:-$probe_bin}")
                fi
                probe_uid=$(ts_v_unmanaged_uid "$TSD_CFG_PATH")
                local -a probe_args=(--quiet --wait --pipe --collect -p RuntimeMaxSec=60)
                if [[ "$probe_uid" =~ ^[1-9][0-9]{0,9}$ ]]; then
                    probe_args+=("--uid=${probe_uid}")
                fi
                probe_out=$("$SYSTEMD_RUN_BIN" "${probe_args[@]}" "${probe_cmd[@]}" managed-probe send 6 - "$TS_V_T_IP" </dev/null 2>/dev/null) || probe_out=""
                if [[ -n "$probe_tmp" ]]; then
                    rm -f "$probe_tmp" 2>/dev/null || true
                fi
                while IFS= read -r probe_line; do
                    if [[ "$probe_line" == "send ${TS_V_T_IP} "* ]]; then
                        probe_w="${probe_line##* }"
                        break
                    fi
                done < <(printf '%s\n' "$probe_out")
                case "$(ts_m_probe_classify "$probe_w")" in
                    blocked)
                        ts_v_add ipv6_probe unsafe pass "an IPv6 datagram to ${TS_V_T_IP} was stopped on this host (${probe_w})"
                        ;;
                    left)
                        TS_V_GOT_THROUGH=1
                        ipv6_leak_detail="an IPv6 datagram to ${TS_V_T_IP} left this host; nothing stopped it"
                        ts_v_add ipv6_probe unsafe fail "$ipv6_leak_detail"
                        ;;
                    *)
                        ipv6_leak_detail="could not run (${probe_w:-no-answer})"
                        ts_v_add ipv6_probe unsafe fail "$ipv6_leak_detail"
                        ;;
                esac
            fi
        fi
    fi
    if [[ -n "$ipv6_leak_detail" ]]; then
        TS_V_VERDICT="unsafe"
        TS_V_EXIT=4
        text="Standard install: ${ipv6_leak_detail}."
    else
        TS_V_VERDICT="unmanaged"
        TS_V_EXIT=9
        if [[ "$up" -eq 1 ]] && [[ "$ks" -eq 1 ]]; then
            text="Standard install: the tunnel is up (handshake ${age}) and its kill switch is active while the tunnel stays up. Managed mode keeps it armed across restarts: see https://github.com/Tunnelsats/tunnelsats/blob/main/docs/managed-mode.md."
        elif [[ "$up" -eq 1 ]]; then
            text="Standard install: the tunnel is up (handshake ${age}), but its kill switch table is not loaded. Managed mode keeps a kill switch armed across restarts: see https://github.com/Tunnelsats/tunnelsats/blob/main/docs/managed-mode.md."
        else
            text="Standard install: the tunnel is not up right now; its kill switch is active while the tunnel is up. Managed mode keeps it armed across restarts: see https://github.com/Tunnelsats/tunnelsats/blob/main/docs/managed-mode.md."
        fi
    fi
    if [[ "$TS_JSON" -eq 1 ]]; then
        ts_v_checks_json
        checks_j="$TS_R"
        ts_j_obj sn:host "$TSD_CFG_EP_HOST" sn:ipv4 "" i:port "$TSD_CFG_EP_PORT" i:vpn_port "$TSD_CFG_VPN_PORT"
        ep_j="$TS_R"
        if [[ "$TS_V_VERDICT" == "unsafe" ]]; then
            ts_j_error E_IPV6_PROBE unsafe "$ipv6_leak_detail"
        else
            ts_j_error E_UNMANAGED unmanaged "$text"
        fi
        local errors_j="[${TS_R}]"
        ts_j_obj s:verdict "$TS_V_VERDICT" b:clearnet_blocked 0 b:emergency_block 0 s:emergency_state none b:managed 0 s:install_kind "$kind" \
            sn:profile "" sn:impl "" sn:unit "" sn:iface "$iface" s:probes "$probe_state" r:endpoint "$ep_j" r:checks "$checks_j"
        ts_json_document "$TS_V_EXIT" "$errors_j" "${TS_R:1:${#TS_R}-2}"
        exit "$TS_V_EXIT"
    fi
    echo -e "${BOLD}TunnelSats verify${NC}: standard install (${kind})${iface:+, interface ${iface}}"
    print_line
    for n in "${!TS_V_ID[@]}"; do
        printf '  %-17s %-5s %s\n' "${TS_V_ID[$n]}" "${TS_V_RESULT[$n]}" "${TS_V_DETAIL[$n]}"
    done
    print_line
    if [[ "$TS_V_VERDICT" == "unsafe" ]]; then
        echo -e "${RED}Not protected${NC}"
        ts_v_print_failed
    fi
    echo "$text"
    exit "$TS_V_EXIT"
}

# verify while the install record cannot be read ($1 = why; $2 = probes run or skipped). The kill
# switch unit then keeps Lightning behind the emergency block for the uid its ExecStart carries
# (--fallback-uid): install_state "damaged", the block checked for that uid and, unless --no-probe,
# the kill switch probe as that uid. Degraded with clearnet_blocked while the block is in effect,
# unsafe otherwise; action_required asks to restore the record or reinstall.
ts_v_damaged() {
    local why="$1" probes="$2" uid="" emergency=0 block=0 reason=""
    TS_M_INV_STATE="damaged"
    TS_M_INV_PROFILE=""
    TS_M_INV_IMPL=""
    TS_M_INV_UNIT=""
    ts_v_add install_state unsafe fail "the install record cannot be read (${why})"
    uid=$(ts_m_fallback_uid)
    if [[ -z "$uid" ]]; then
        ts_v_add emergency_block unsafe fail "${TS_M_KILLSWITCH_UNIT} carries no fallback uid, so the emergency block cannot be checked"
    elif ! ts_m_emergency_present "$uid"; then
        ts_v_add emergency_block unsafe fail "not armed for uid ${uid}"
    else
        block=1
        TS_M_INV_UID="$uid"
        TS_M_INV_USER="$uid"
        if ts_m_emergency_effective "$uid"; then
            emergency=1
            TS_V_EMERGENCY_STATE="active"
        else
            reason="$TS_M_ERROR"
            TS_V_EMERGENCY_STATE="$TS_M_EMERG_FAIL"
        fi
        ts_v_check_emergency "$emergency" "$reason"
        ts_v_check_emergency_lan "$uid"
    fi
    ts_v_read_endpoint
    if [[ "$probes" == "run" ]] && [[ "$block" -eq 1 ]]; then
        ts_v_check_probes 1
    fi
    ts_v_check_handshake
    ts_v_check_endpoint
    ts_v_verdict "$emergency"
    TS_V_ACTION_TEXT="restore ${TS_M_INVENTORY} (for example from a backup) or reinstall"
    ts_j_obj s:reason install_record_damaged s:detail "The install record cannot be read (${why}); ${TS_V_ACTION_TEXT}"
    TS_V_ACTION_J="$TS_R"
    ts_v_report "$emergency" "$probes"
}

cmd_verify() {
    local emergency=0 block=0 block_reason="" probes="run" kind="" existing=""
    ts_m_require_root
    TS_V_ID=()
    TS_V_CLASS=()
    TS_V_RESULT=()
    TS_V_DETAIL=()
    TS_V_GOT_THROUGH=0
    # Probe targets, overridable for tests. The two echo services must agree; they are asked only
    # through the tunnel. The kill switch probe goes to the WireGuard endpoint; the IPv6 probe goes
    # to the TunnelSats host's IPv6 address (TS_VERIFY_ECHO_URLS="URL1 URL2", TS_VERIFY_IPV6_URL).
    read -r -a TS_V_ECHO_URLS <<< "${TS_VERIFY_ECHO_URLS:-https://api.ipify.org https://ipv4.icanhazip.com}"
    if [[ ${#TS_V_ECHO_URLS[@]} -lt 2 ]]; then
        ts_usage_error "TS_VERIFY_ECHO_URLS needs two URLs"
    fi
    TS_V_V6_URL="${TS_VERIFY_IPV6_URL:-https://tunnelsats.com}"
    # The endpoint lookup gets TS_VERIFY_RESOLVE_TIMEOUT seconds (default 5), overridable for tests
    if ! TS_V_RESOLVE_TIMEOUT=$(ts_v_resolve_timeout); then
        ts_usage_error "TS_VERIFY_RESOLVE_TIMEOUT must be a whole number of seconds from 1 to 999"
    fi
    if [[ "$TS_OPT_NO_PROBE" -eq 1 ]]; then
        probes="skipped"
    fi

    if ! ts_m_inventory_present; then
        # A managed install whose record is gone: its kill switch unit still carries the uid
        if [[ -n "$(ts_m_fallback_uid)" ]]; then
            ts_v_damaged "${TS_M_INVENTORY} is missing" "$probes"
        fi
        existing=$(ts_m_existing_install) || existing="unknown||"
        kind="${existing%%|*}"
        if [[ "$kind" == "none" ]]; then
            ts_fail 3 E_NOT_INSTALLED not_installed "No TunnelSats install found"
        fi
        ts_v_unmanaged "$kind" "$probes"
    fi
    if ! ts_m_inventory_read; then
        ts_v_damaged "$TS_M_ERROR" "$probes"
    fi
    # The emergency block counts as blocking only while it is in effect (ts_m_emergency_effective),
    # with or without --no-probe; present but not in effect, it is reported as unsafe
    TS_V_EMERGENCY_STATE="none"
    if ts_m_emergency_present "$TS_M_INV_UID"; then
        block=1
        if ts_m_emergency_effective "$TS_M_INV_UID"; then
            emergency=1
            TS_V_EMERGENCY_STATE="active"
        else
            block_reason="$TS_M_ERROR"
            TS_V_EMERGENCY_STATE="$TS_M_EMERG_FAIL"
        fi
    fi
    ts_v_read_endpoint
    ts_v_check_state
    ts_v_check_attest
    ts_v_check_nft
    ts_v_check_slice
    ts_v_check_rules
    if [[ "$block" -eq 1 ]]; then
        ts_v_check_emergency "$emergency" "$block_reason"
        ts_v_check_emergency_lan "$TS_M_INV_UID"
    fi
    ts_v_check_table
    ts_v_check_dropin
    ts_v_check_membership
    if [[ "$probes" == "run" ]]; then
        ts_v_check_probes "$block"
    fi
    ts_v_check_handshake
    ts_v_check_endpoint
    ts_v_verdict "$emergency"
    ts_v_report "$emergency" "$probes"
}

# ---------------------------------------------------------------------------
# MAIN ENTRY POINT
# ---------------------------------------------------------------------------

main() {
    parse_args "$@"
}

# Run the script only when executed directly, not when sourced by tests.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
