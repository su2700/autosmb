#!/bin/bash

# =====================================================================
#  SMB Enumeration Toolkit:
#   - smbclient
#   - smbmap
#   - NetExec (nxc smb)
#   + Interactive login loop
# =====================================================================

echo "=== SMB ENUM + nxc + LOGIN SELECTOR (v13) ==="
read -p "[+] Enter target IP: " TARGET

echo
echo "[?] Authentication mode:"
echo "    1) Anonymous"
echo "    2) Username only (blank password)"
echo "    3) Username + password"
read -p "[+] Your choice (1/2/3): " MODE
echo

USER=""
PASS=""
AUTH=""

case "$MODE" in
    1)
        echo "[+] Using anonymous login."
        AUTH="anon"
        SMB_U=""
        SMB_P=""
        ;;
    2)
        read -p "[+] Username: " USER
        AUTH="blank"
        SMB_U="$USER"
        SMB_P=""
        ;;
    3)
        read -p "[+] Username: " USER
        read -s -p "[+] Password: " PASS
        echo
        AUTH="full"
        SMB_U="$USER"
        SMB_P="$PASS"
        ;;
    *)
        echo "[!] Invalid selection."
        exit 1
        ;;
esac


# =====================================================================
# STEP 1 — smbclient ENUMERATION
# =====================================================================
echo "[+] Enumerating SMB shares with smbclient..."
SMBCLIENT_FILE="smbclient_$TARGET.txt"

case "$AUTH" in
    anon)  smbclient -L "//$TARGET" -N | tee "$SMBCLIENT_FILE" ;;
    blank) smbclient -L "//$TARGET" -U "$USER%" | tee "$SMBCLIENT_FILE" ;;
    full)  smbclient -L "//$TARGET" -U "$USER%$PASS" | tee "$SMBCLIENT_FILE" ;;
esac

SHARES=( $(grep "Disk" "$SMBCLIENT_FILE" | awk '{print $1}') )


# =====================================================================
# STEP 2 — smbmap (permissions, RW, NO ACCESS)
# =====================================================================
echo
echo "[+] Running smbmap..."
SMBMAP_FILE="smbmap_$TARGET.txt"

if [[ "$AUTH" == "anon" ]]; then
    smbmap -H "$TARGET" -u "" -p "" | tee "$SMBMAP_FILE"
elif [[ "$AUTH" == "blank" ]]; then
    smbmap -H "$TARGET" -u "$USER" -p "" | tee "$SMBMAP_FILE"
else
    smbmap -H "$TARGET" -u "$USER" -p "$PASS" | tee "$SMBMAP_FILE"
fi


# =====================================================================
# STEP 3 — NetExec SMB Deep Info
# =====================================================================
echo
echo "[+] Running NetExec (nxc) for extended SMB intelligence..."

mkdir -p nxc_results
NX_BASE="nxc_results/nxc_$TARGET"

if [[ "$AUTH" == "anon" ]]; then
    NX_AUTH="-u '' -p ''"
elif [[ "$AUTH" == "blank" ]]; then
    NX_AUTH="-u '$USER' -p ''"
else
    NX_AUTH="-u '$USER' -p '$PASS'"
fi

#--------------- RUN ALL NX COMMANDS --------------------

echo "[+] nxc smb general info..."
eval nxc smb $TARGET $NX_AUTH | tee "${NX_BASE}_general.txt"

echo "[+] nxc smb shares..."
eval nxc smb $TARGET $NX_AUTH --shares | tee "${NX_BASE}_shares.txt"

echo "[+] nxc smb groups..."
eval nxc smb $TARGET $NX_AUTH --groups | tee "${NX_BASE}_groups.txt"

echo "[+] nxc smb users..."
eval nxc smb $TARGET $NX_AUTH --users | tee "${NX_BASE}_users.txt"

echo "[+] nxc smb sessions..."
eval nxc smb $TARGET $NX_AUTH --sessions | tee "${NX_BASE}_sessions.txt"


# =====================================================================
# FUNCTION: Print share list + smbmap permissions
# =====================================================================
print_share_list() {
    echo
    echo "========== SMB SHARES + PERMISSIONS =========="

    local i=1
    for share in "${SHARES[@]}"; do
        PERM=$(grep -E "^$share[[:space:]]" "$SMBMAP_FILE" | awk '{print $2}')
        if [[ -z "$PERM" ]]; then
            PERM="UNKNOWN"
        fi
        echo "  $i) $share     [Access: $PERM]"
        ((i++))
    done

    echo "================================================"
    echo
}


# =====================================================================
# MAIN INTERACTIVE LOOP
# =====================================================================
while true; do
    print_share_list

    read -p "[+] Choose share # to login (or 'exit'): " choice

    if [[ "$choice" == "exit" ]]; then
        echo "[+] Exiting script."
        break
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        echo "[!] Invalid input."
        continue
    fi

    index=$((choice - 1))

    if [[ $index -lt 0 || $index -ge ${#SHARES[@]} ]]; then
        echo "[!] Out-of-range number."
        continue
    fi

    SHARE="${SHARES[$index]}"
    echo "--------------------------------------------------"
    echo "[+] Testing access: $SHARE"


    # Build test + login commands
    if [[ "$AUTH" == "anon" ]]; then
        TEST="smbclient //$TARGET/$SHARE -N -c exit"
        LOGIN="smbclient //$TARGET/$SHARE -N"
        DL="smbclient //$TARGET/$SHARE -N -c \"recurse ON; prompt OFF; mget *\""
    elif [[ "$AUTH" == "blank" ]]; then
        TEST="smbclient //$TARGET/$SHARE -U $USER% -c exit"
        LOGIN="smbclient //$TARGET/$SHARE -U $USER%"
        DL="smbclient //$TARGET/$SHARE -U $USER% -c \"recurse ON; prompt OFF; mget *\""
    else
        TEST="smbclient //$TARGET/$SHARE -U $USER%$PASS -c exit"
        LOGIN="smbclient //$TARGET/$SHARE -U $USER%$PASS"
        DL="smbclient //$TARGET/$SHARE -U $USER%$PASS -c \"recurse ON; prompt OFF; mget *\""
    fi

    # Test login
    if eval $TEST >/dev/null 2>&1; then
        echo "[+] ACCESS GRANTED → $SHARE"
        echo
        echo "=================================================="
        echo " RECURSIVE DOWNLOAD COMMAND (copy/paste):"
        echo "=================================================="
        echo "$DL"
        echo "=================================================="
        echo

        echo "[+] Starting SMB interactive session..."
        echo "[+] Type 'exit' to logout and return to menu."
        echo "--------------------------------------------------"
        eval "$LOGIN"
        echo "--------------------------------------------------"
        echo "[+] Logged out — returning to menu."

    else
        echo "[-] ACCESS DENIED → $SHARE"
    fi
done

echo
echo "=================================================="
echo "[+] Finished. nxc results saved in /nxc_results/"
echo "=================================================="
