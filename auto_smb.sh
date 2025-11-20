#!/bin/bash

# =====================================================================
#  SMB Share Enumerator + smbmap Integration + Interactive Login Loop
# =====================================================================

echo "=== SMB SHARE ENUM + LOGIN SELECTOR (v12 with smbmap) ==="
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
        echo "[+] Using anonymous authentication."
        AUTH="anon"
        SMB_USER=""
        SMB_PASS=""
        ;;
    2)
        read -p "[+] Username: " USER
        echo "[+] Using blank password for '$USER'"
        AUTH="blank"
        SMB_USER="$USER"
        SMB_PASS=""
        ;;
    3)
        read -p "[+] Username: " USER
        read -s -p "[+] Password: " PASS
        echo
        AUTH="full"
        SMB_USER="$USER"
        SMB_PASS="$PASS"
        ;;
    *)
        echo "[!] Invalid selection."
        exit 1
        ;;
esac


# ------------------------------------------------------------
# ENUMERATE SHARES (smbclient)
# ------------------------------------------------------------
echo "[+] Enumerating SMB shares using smbclient..."
SHARES_FILE="shares_$TARGET.txt"

case "$AUTH" in
    anon)  smbclient -L "//$TARGET" -N | tee "$SHARES_FILE" ;;
    blank) smbclient -L "//$TARGET" -U "$USER%" | tee "$SHARES_FILE" ;;
    full)  smbclient -L "//$TARGET" -U "$USER%$PASS" | tee "$SHARES_FILE" ;;
esac

SHARES=( $(grep "Disk" "$SHARES_FILE" | awk '{print $1}') )


# ------------------------------------------------------------
# RUN SMBMAP and store results
# ------------------------------------------------------------
echo
echo "[+] Running smbmap for permission analysis..."
SMBMAP_FILE="smbmap_$TARGET.txt"

if [[ "$AUTH" == "anon" ]]; then
    smbmap -H "$TARGET" -u "" -p "" | tee "$SMBMAP_FILE"
elif [[ "$AUTH" == "blank" ]]; then
    smbmap -H "$TARGET" -u "$USER" -p "" | tee "$SMBMAP_FILE"
else
    smbmap -H "$TARGET" -u "$USER" -p "$PASS" | tee "$SMBMAP_FILE"
fi


# ------------------------------------------------------------
# FUNCTION: Print share list + smbmap permissions
# ------------------------------------------------------------
print_share_list() {
    echo
    echo "========== AVAILABLE SMB SHARES + PERMISSIONS =========="

    local i=1
    for share in "${SHARES[@]}"; do
        PERM=$(grep -E "^$share[[:space:]]" "$SMBMAP_FILE" | awk '{print $2}')
        if [[ -z "$PERM" ]]; then
            PERM="UNKNOWN"
        fi
        echo "  $i) $share    [Access: $PERM]"
        ((i++))
    done

    echo "========================================================"
    echo
}


# ------------------------------------------------------------
# MAIN LOOP — ALWAYS SHOW SHARE LIST
# ------------------------------------------------------------
while true; do
    print_share_list

    read -p "[+] Choose share number to login (or 'exit'): " selection

    if [[ "$selection" == "exit" ]]; then
        echo "[+] Exiting."
        break
    fi

    # Validate
    if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
        echo "[!] Invalid input."
        continue
    fi

    index=$((selection - 1))
    if [[ $index -lt 0 || $index -ge ${#SHARES[@]} ]]; then
        echo "[!] Invalid share number."
        continue
    fi

    SHARE="${SHARES[$index]}"
    echo "--------------------------------------------------"
    echo "[+] Testing access: $SHARE"

    # Build commands
    if [[ "$AUTH" == "anon" ]]; then
        TEST_CMD="smbclient //$TARGET/$SHARE -N -c exit"
        LOGIN_CMD="smbclient //$TARGET/$SHARE -N"
        DL_CMD="smbclient //$TARGET/$SHARE -N -c \"recurse ON; prompt OFF; mget *\""
    elif [[ "$AUTH" == "blank" ]]; then
        TEST_CMD="smbclient //$TARGET/$SHARE -U $USER% -c exit"
        LOGIN_CMD="smbclient //$TARGET/$SHARE -U $USER%"
        DL_CMD="smbclient //$TARGET/$SHARE -U $USER% -c \"recurse ON; prompt OFF; mget *\""
    else
        TEST_CMD="smbclient //$TARGET/$SHARE -U $USER%$PASS -c exit"
        LOGIN_CMD="smbclient //$TARGET/$SHARE -U $USER%$PASS"
        DL_CMD="smbclient //$TARGET/$SHARE -U $USER%$PASS -c \"recurse ON; prompt OFF; mget *\""
    fi

    # Test login
    if eval $TEST_CMD >/dev/null 2>&1; then
        echo "[+] ACCESS GRANTED → $SHARE"

        echo
        echo "=================================================="
        echo " READY-TO-USE RECURSIVE DOWNLOAD COMMAND "
        echo "=================================================="
        echo "$DL_CMD"
        echo "=================================================="
        echo

        echo "[+] Opening interactive SMB session."
        echo "[+] Type 'exit' to logout and return to the menu."
        echo "--------------------------------------------------"

        # Run smbclient
        eval "$LOGIN_CMD"

        echo "--------------------------------------------------"
        echo "[+] Logged out of $SHARE — returning to menu."

    else
        echo "[-] ACCESS DENIED → $SHARE"
        echo "[!] Try another share."
    fi
done

echo
echo "=================================================="
echo "[+] Finished. Goodbye!"
echo "=================================================="
