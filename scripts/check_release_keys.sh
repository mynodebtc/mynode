#!/bin/bash

# Check the release signing keys shipped in rootfs/standard/usr/share/mynode/release_keys/.
# The device imports these files instead of fetching keys from keyservers, so a key that is
# missing or out of date here means a failed app upgrade on every device.
#
# Each <APP>_SIGNER_FINGERPRINTS fingerprint in mynode_app_versions.sh needs a file
# release_keys/<FINGERPRINT>.asc that holds only that key.
#
# Run from the repository root:
#   scripts/check_release_keys.sh              check the shipped keys (offline): missing, revoked,
#                                              expired or unused keys
#   scripts/check_release_keys.sh --releases   also download the signatures of every pinned
#                                              release and verify them with only the shipped keys,
#                                              which is what the device does. Run this after
#                                              changing an app version.
#   scripts/check_release_keys.sh --refresh    fetch each key from its sources (see KEY_SOURCES),
#                                              merge it with the shipped copy and rewrite the file
#                                              when it changed (new expiry, subkeys, revocation).
#                                              Also creates the file for a newly added fingerprint.
#
# Exits with an error if a key is missing, wrong or revoked, or a pinned release does not verify.
# An expired key only gets a warning: gpg still accepts signatures from an expired key, but it is
# a sign that the shipped copy may be stale (run --refresh).
#
# To add a signer: add the fingerprint to <APP>_SIGNER_FINGERPRINTS (and the signature URL to
# mynode_app_versions.sh if it is a new file), add the fingerprint to KEY_SOURCES below, check the
# fingerprint against a source you trust, then run --refresh and --releases.

set -e

VERSIONS_FILE=rootfs/standard/usr/share/mynode/mynode_app_versions.sh
UPGRADE_FILE=rootfs/standard/usr/bin/mynode_post_upgrade.sh
KEYS_DIR=rootfs/standard/usr/share/mynode/release_keys
WARN_DAYS=90

# Where --refresh looks for each key, in addition to keyserver.ubuntu.com and keys.openpgp.org.
# Sources that cannot be reached are skipped. <fingerprint> <name> [URL...]
KEY_SOURCES="
A5B61896952D9FDA83BC054CDC42612E89237182 roasbeef https://raw.githubusercontent.com/lightningnetwork/lnd/master/scripts/keys/roasbeef.asc https://keybase.io/roasbeef/pgp_keys.asc
F4FC70F07310028424EFC20A8E4256593F177720 guggero https://keybase.io/guggero/pgp_keys.asc https://github.com/guggero.gpg
3E9BD4436C288039CA827A9200C9E2BC2E45666F suheb https://raw.githubusercontent.com/lightningnetwork/lnd/master/scripts/keys/suheb.asc https://keybase.io/suheb/pgp_keys.asc
C20A78516A0944900EBFCA29961CC8259AE675D4 ViktorT-11 https://raw.githubusercontent.com/lightningnetwork/lnd/master/scripts/keys/ViktorT-11.asc https://github.com/ViktorT-11.gpg
9FC6B0BFD597A94DBF09708280E5375C094198D8 bhandras https://raw.githubusercontent.com/lightningnetwork/lnd/master/scripts/keys/bhandras.asc https://github.com/bhandras.gpg
DE23E73BFA8A0AD5587D2FCDE80D2F3F311FD87E alexbosworth https://github.com/alexbosworth.gpg
26984CB69EB8C4A26196F7A4D7D916376026F177 ellemouton https://github.com/ellemouton.gpg
187F6ADD93AE3B0CF335AA6AB984570980684DCC ViktorTigerstrom https://github.com/ViktorTigerstrom.gpg
01EA5486DE18A882D4C2684590C8019E36C2E964 laanwj https://raw.githubusercontent.com/bitcoin-core/guix.sigs/main/builder-keys/laanwj.gpg
E777299FC265DD04793070EB944D35F9AC3DB76A fanquake https://raw.githubusercontent.com/bitcoin-core/guix.sigs/main/builder-keys/fanquake.gpg
"

RELEASES=0
REFRESH=0
for ARG in "$@"; do
    case "$ARG" in
        --releases) RELEASES=1 ;;
        --refresh) REFRESH=1 ;;
        *) echo "Usage: $0 [--releases] [--refresh]" >&2; exit 2 ;;
    esac
done

if [ ! -f "$VERSIONS_FILE" ]; then
    echo "ERROR: run from the repository root" >&2
    exit 2
fi
command -v gpg > /dev/null || { echo "ERROR: gpg is not installed" >&2; exit 2; }

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
# Never touch the user's own keyring
export GNUPGHOME="$TMP_DIR/gnupg"
mkdir -m 700 "$GNUPGHOME"

PROBLEMS=0
problem () { echo "$1"; PROBLEMS=$((PROBLEMS + 1)); }

format_date () {
    date -u -d "@$1" +%Y-%m-%d 2> /dev/null || date -u -r "$1" +%Y-%m-%d
}

# All fingerprints in <APP>_SIGNER_FINGERPRINTS, and the apps that use each one
all_fingerprints () {
    grep -hE '^[A-Z0-9_]+_SIGNER_FINGERPRINTS="' "$VERSIONS_FILE" | cut -d'"' -f2 | tr ' ' '\n' | grep . | sort -u
}
apps_using () {
    grep -E "^[A-Z0-9_]+_SIGNER_FINGERPRINTS=\".*$1" "$VERSIONS_FILE" | sed 's/_SIGNER_FINGERPRINTS=.*//' | tr '\n' ' ' | sed 's/ $//'
}
name_of () {
    local name
    name=$(echo "$KEY_SOURCES" | awk -v f="$1" '$1 == f {print $2}')
    echo "${name:-unknown}"
}

# Key listing of a file without importing it: gpg --with-colons lines
show_key () {
    gpg --batch --with-colons --import-options show-only --import "$1" 2> /dev/null
}

# One line per key or subkey: <pub|sub> <keyid> <validity> <expiry> <capabilities>, plus uids.
# Used to tell if a refreshed key changed.
key_summary () {
    show_key "$1" | awk -F: '$1 == "pub" || $1 == "sub" {print $1, $5, $2, $7, $12} $1 == "uid" {print "uid", $10}' | sort
}

# Check one shipped key file. Prints a status line.
check_key_file () {
    local fpr=$1
    local file="$KEYS_DIR/$fpr.asc"
    local label
    label="$(printf '%-17s %s' "$(name_of "$fpr")" "$fpr") ($(apps_using "$fpr"))"

    if [ ! -f "$file" ]; then
        problem "MISSING   $label: no $file (run --refresh)"
        return
    fi
    local primaries
    primaries=$(show_key "$file" | awk -F: '$1 == "pub" {getline; if ($1 == "fpr") print $10}')
    if [ "$primaries" != "$fpr" ]; then
        problem "WRONG     $label: file holds $(echo $primaries) instead of exactly this key"
        return
    fi

    # Validity "r" = revoked. A key can sign if it, or a subkey, has "s" and is not revoked.
    local now soon listing
    now=$(date +%s)
    soon=$((now + WARN_DAYS * 86400))
    listing=$(show_key "$file")
    if echo "$listing" | awk -F: '$1 == "pub" && $2 == "r" {found = 1} END {exit !found}'; then
        problem "REVOKED   $label: remove it from the signer list"
        return
    fi
    # Latest expiry of any signing-capable, non-revoked key (0 = never expires)
    local signing_expiry
    signing_expiry=$(echo "$listing" | awk -F: '
        ($1 == "pub" || $1 == "sub") && $2 != "r" && $12 ~ /s/ {
            if ($7 == "") never = 1; else if ($7 > max) max = $7
        }
        END { if (never) print 0; else if (max) print max; else print -1 }')
    if [ "$signing_expiry" = "-1" ]; then
        problem "WRONG     $label: no key that can sign"
    elif [ "$signing_expiry" = "0" ]; then
        echo "OK        $label: does not expire"
    elif [ "$signing_expiry" -lt "$now" ]; then
        echo "EXPIRED   $label: signing key expired $(format_date "$signing_expiry") (still accepted by gpg; check --refresh or if this signer still signs)"
    elif [ "$signing_expiry" -lt "$soon" ]; then
        echo "EXPIRING  $label: signing key expires $(format_date "$signing_expiry") (run --refresh closer to the date)"
    else
        echo "OK        $label: signing key expires $(format_date "$signing_expiry")"
    fi
}

# Fetch a key from all its sources, merge with the shipped copy and rewrite the file if it changed
refresh_key () {
    local fpr=$1
    local file="$KEYS_DIR/$fpr.asc"
    local name
    name=$(name_of "$fpr")
    local urls
    urls=$(echo "$KEY_SOURCES" | awk -v f="$fpr" '$1 == f {for (i = 3; i <= NF; i++) print $i}')
    urls="https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x$fpr
https://keys.openpgp.org/vks/v1/by-fingerprint/$fpr
$urls"

    # Separate keyring per key, so a source file holding other keys cannot affect the result
    local home="$TMP_DIR/refresh-$fpr"
    mkdir -m 700 "$home"
    if [ -f "$file" ]; then
        GNUPGHOME="$home" gpg --batch --quiet --import "$file" 2> /dev/null || true
    fi
    local url fetched=""
    for url in $urls; do
        if curl -fsSL --max-time 30 "$url" -o "$home/download" 2> /dev/null && \
           GNUPGHOME="$home" gpg --batch --quiet --import "$home/download" 2> /dev/null; then
            fetched="$fetched ${url%%\?*}"
        fi
    done

    if ! GNUPGHOME="$home" gpg --batch --list-keys "$fpr" > /dev/null 2>&1; then
        problem "FAILED    $name $fpr: not found in any source"
        return
    fi
    # Only this key. Not export-minimal or export-clean: they drop expired subkeys, which are
    # still needed to verify releases signed with them.
    GNUPGHOME="$home" gpg --batch --armor --export "$fpr" > "$home/new.asc"

    if [ -f "$file" ] && [ "$(key_summary "$file")" = "$(key_summary "$home/new.asc")" ]; then
        echo "unchanged $name $fpr"
        return
    fi
    if [ -f "$file" ]; then
        echo "UPDATED   $name $fpr (from:$fetched)"
        diff <(key_summary "$file") <(key_summary "$home/new.asc") | grep '^[<>]' | sed 's/^/          /' || true
    else
        echo "ADDED     $name $fpr (from:$fetched)"
        echo "          check this fingerprint against a source you trust before committing"
    fi
    cp "$home/new.asc" "$file"
}

# Replace $VAR and ${VAR} in a URL template: <APP>_VERSION with the given version, other
# variables with their literal value in the versions or upgrade file
resolve_url () {
    local url=$1 app=$2 version=$3
    url=${url//\$\{${app}_VERSION\}/$version}
    url=${url//\$${app}_VERSION/$version}
    local var value
    while [[ "$url" =~ \$\{?([A-Za-z_][A-Za-z0-9_]*)\}? ]]; do
        var=${BASH_REMATCH[1]}
        value=$(grep -hE "^[[:space:]]*${var}=" "$VERSIONS_FILE" "$UPGRADE_FILE" | head -1 | cut -d= -f2- | tr -d '"')
        if [[ "$value" == *'$'* ]]; then
            return 1
        fi
        url=${url//\$\{$var\}/$value}
        url=${url//\$$var/$value}
    done
    echo "$url"
}

# URL template of a variable defined in the versions or upgrade file
url_template () {
    grep -hE "^[[:space:]]*$1=" "$VERSIONS_FILE" "$UPGRADE_FILE" | head -1 | sed 's/^[[:space:]]*//' | cut -d= -f2- | tr -d '"'
}

# Download and verify each pinned version of each app with signers, using only the shipped keys
check_releases () {
    local verify_home="$TMP_DIR/verify"
    mkdir -m 700 "$verify_home"
    GNUPGHOME="$verify_home" gpg --batch --quiet --import "$KEYS_DIR"/*.asc 2> /dev/null || true

    local app
    for app in $(grep -oE '^[A-Z0-9_]+_SIGNER_FINGERPRINTS=' "$VERSIONS_FILE" | sed 's/_SIGNER_FINGERPRINTS=//'); do
        local signers
        signers=$(grep -E "^${app}_SIGNER_FINGERPRINTS=" "$VERSIONS_FILE" | cut -d'"' -f2)

        # The signed file: a manifest, a checksums file, or the download itself
        local data_var data_template=""
        for data_var in ${app}_UPGRADE_MANIFEST_URL ${app}_UPGRADE_SHA256SUM_URL ${app}_UPGRADE_URL; do
            data_template=$(url_template "$data_var")
            [ -n "$data_template" ] && break
        done
        local sig_vars
        sig_vars=$(grep -hoE "^[[:space:]]*${app}_UPGRADE_([A-Z0-9_]+_)?(SIG|ASC)_URL=" "$VERSIONS_FILE" "$UPGRADE_FILE" | tr -d ' =' | sort -u)
        if [ -z "$data_template" ] || [ -z "$sig_vars" ]; then
            problem "ERROR     $app: could not find the signed file and signature URLs"
            continue
        fi

        # Every literal version, including overrides for older systems
        local version
        for version in $(grep -E "^[[:space:]]*${app}_VERSION=\"[^\$\"]+\"" "$VERSIONS_FILE" | cut -d'"' -f2); do
            local dir="$TMP_DIR/release-$app-$version"
            mkdir -p "$dir"
            local data_url
            if ! data_url=$(resolve_url "$data_template" "$app" "$version") || \
               ! curl -fsSL "$data_url" -o "$dir/data"; then
                problem "ERROR     $app $version: could not download ${data_url:-$data_template}"
                continue
            fi

            local verified="" details="" sig_var
            for sig_var in $sig_vars; do
                local sig_url sig_name
                sig_url=$(resolve_url "$(url_template "$sig_var")" "$app" "$version") || continue
                sig_name=${sig_url##*/}
                if ! curl -fsSL "$sig_url" -o "$dir/sig" 2> /dev/null; then
                    details="$details\n          $sig_name: not published"
                    continue
                fi
                # Primary key fingerprints of good signatures, as check_gpg_signer() reads them
                local valid fpr found=""
                valid=$(GNUPGHOME="$verify_home" gpg --batch --status-fd 1 --verify "$dir/sig" "$dir/data" 2> /dev/null | awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" {print $NF}')
                for fpr in $signers; do
                    if echo "$valid" | grep -qxF "$fpr"; then
                        found="$found $(name_of "$fpr")"
                    fi
                done
                if [ -n "$found" ]; then
                    verified="$verified$found"
                    continue
                fi
                # Not verified: say who signed it
                local issuer issuers
                issuers=$(gpg --batch --list-packets "$dir/sig" 2> /dev/null | sed -n 's/.*issuer fpr v[0-9] \([0-9A-F]*\).*/\1/p; s/.*:signature packet: .*keyid \([0-9A-F]*\).*/\1/p' | sort -u)
                for issuer in $issuers; do
                    if echo "$signers" | grep -qiF "${issuer: -16}"; then
                        details="$details\n          $sig_name: signed by allowlisted key $issuer, but it does not verify with the shipped keys (run --refresh)"
                    elif echo "$valid" | grep -q .; then
                        details="$details\n          $sig_name: signed by $issuer, which is not in ${app}_SIGNER_FINGERPRINTS"
                    else
                        details="$details\n          $sig_name: signed by unknown key $issuer (not in ${app}_SIGNER_FINGERPRINTS, see https://keyserver.ubuntu.com/pks/lookup?op=index&search=0x$issuer)"
                    fi
                done
            done

            if [ -n "$verified" ]; then
                echo "OK        $app $version: verified by $(echo $verified | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//')"
            else
                problem "FAILED    $app $version: no valid signature from a key in ${app}_SIGNER_FINGERPRINTS$(echo -e "$details")"
            fi
        done
    done
}

mkdir -p "$KEYS_DIR"

if [ $REFRESH = 1 ]; then
    echo "== Refreshing keys"
    for FPR in $(all_fingerprints); do
        refresh_key "$FPR"
    done
    echo
fi

echo "== Shipped keys"
for FPR in $(all_fingerprints); do
    check_key_file "$FPR"
done
for FILE in "$KEYS_DIR"/*.asc; do
    [ -e "$FILE" ] || continue
    FPR=$(basename "$FILE" .asc)
    if ! all_fingerprints | grep -qxF "$FPR"; then
        echo "UNUSED    $FPR: not in any <APP>_SIGNER_FINGERPRINTS, delete $FILE"
    fi
done
for FPR in $(all_fingerprints); do
    if [ "$(name_of "$FPR")" = "unknown" ]; then
        echo "NOTE      $FPR has no entry in KEY_SOURCES (only keyservers are used by --refresh)"
    fi
done

if [ $RELEASES = 1 ]; then
    echo
    echo "== Pinned releases"
    check_releases
fi

if [ $PROBLEMS -gt 0 ]; then
    echo
    echo "$PROBLEMS problem(s) found"
    exit 1
fi
