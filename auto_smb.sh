#!/bin/bash

# =====================================================================
#  SMB Share Enumerator + Interactive Login Loop + Reprint List
# =====================================================================

echo "=== SMB SHARE ENUM + LOGIN SELECTOR (v11) ==="
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
        ;;
    2)
        read -p "[+] Username: " USER
        echo "[+] Using blank password for '$USER'"
        AUTH="blank"
        ;;
    3)
        read -p "[+] Username: " USER
        read -s -p "[+] Password: " PASS
        echo
        AUTH="full"
        ;;
    *)
        echo "[!] Invalid selection."
        exit 1
        ;;
esac


# ------------------------------------------------------------
# ENUMERATE SHARES
# ------------------------------------------------------------
echo "[+] Enumerating SMB shares on //$TARGET ..."
SHARES_FILE="shares_$TARGET.txt"

case "$AUTH" in
    anon)  smbclient -L "//$TARGET" -N | tee "$SHARES_FILE" ;;
    blank) smbclient -L "//$TARGET" -U "$USER%" | tee "$SHARES_FILE" ;;
    full)  smbclient -L "//$TARGET" -U "$USER%$PASS" | tee "$SHARES_FILE" ;;
esac

# Extract share names only (Disk type)
SHARES=( $(grep "Disk" "$SHARES_FILE" | awk '{print $1}') )


# ------------------------------------------------------------
# FUNCTION: Print Share List
# ------------------------------------------------------------
print_share_list() {
    echo
    echo "=========== AVAILABLE SMB SHARES ==========="
    local i=1
    for share in "${SHARES[@]}"; do
        echo "  $i) $share"
        ((i++))
    done
    echo "============================================"
    echo
}


# ------------------------------------------------------------
# MAIN SELECTION LOOP — ALWAYS PRINT THE SHARE LIST
# ------------------------------------------------------------
while true; do
    print_share_list

    read -p "[+] Choose share number to login (or type 'exit'): " selection

    if [[ "$selection" == "exit" ]]; then
        echo "[+] Exiting."
        break
    fi

    # Validate input
    if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
        echo "[!] Invalid input: must be a number or 'exit'"
        continue
    fi

    index=$((selection - 1))

    if [[ $index -lt 0 || $index -ge ${#SHARES[@]} ]]; then
        echo "[!] Invalid share number."
        continue
    fi

    SHARE="${SHARES[$index]}"
    echo "--------------------------------------------------"
    echo "[+] Testing share: $SHARE"

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

        # Print helpful download command
        echo
        echo "=================================================="
        echo " READY-TO-USE RECURSIVE DOWNLOAD COMMAND "
        echo "=================================================="
        echo "$DL_CMD"
        echo "=================================================="
        echo

        echo "[+] Opening SMB session for $SHARE"
        echo "[+] Type 'exit' inside the session to logout and return to the menu."
        echo "--------------------------------------------------"

        # SMB interactive session
        eval "$LOGIN_CMD"

        echo "--------------------------------------------------"
        echo "[+] Logged out of $SHARE — returning to main menu."
        echo

    else
        echo "[-] ACCESS DENIED → $SHARE"
        echo "[!] Try another share."
    fi

done

echo
echo "=================================================="
echo "[+] Script complete. Goodbye!"
echo "=================================================="
