#!/bin/bash

# =====================================================================
#  SMB Multi-Session Auditor (Safe for HTB/Labs)
#  - Enumerate all SMB shares
#  - Test login for each share
#  - If login works -> open a NEW terminal window with smbclient shell
# =====================================================================

echo "=== SMB MULTI-SESSION AUDITOR ==="
read -p "[+] Enter target IP: " TARGET

echo
echo "[?] Choose authentication mode:"
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
        read -p "[+] Enter username: " USER
        echo "[+] Using blank password for '$USER'."
        AUTH="blank"
        ;;
    3)
        read -p "[+] Enter username: " USER
        read -s -p "[+] Enter password: " PASS
        echo
        AUTH="full"
        ;;
    *)
        echo "[!] Invalid option."
        exit 1
        ;;
esac

# -----------------------------
# Enumerate shares
# -----------------------------
echo "[+] Enumerating shares on //$TARGET ..."
SHARES_FILE="shares_$TARGET.txt"

if [[ "$AUTH" == "anon" ]]; then
    smbclient -L "//$TARGET" -N | tee "$SHARES_FILE"
elif [[ "$AUTH" == "blank" ]]; then
    smbclient -L "//$TARGET" -U "$USER%" | tee "$SHARES_FILE"
else
    smbclient -L "//$TARGET" -U "$USER%$PASS" | tee "$SHARES_FILE"
fi

# Extract share names
SHARES=$(grep "Disk" "$SHARES_FILE" | awk '{print $1}')

echo
echo "[+] Shares detected:"
echo "$SHARES"
echo

# -----------------------------
# Test access & open terminal
# -----------------------------

for share in $SHARES; do
    echo "----------------------------------------------------"
    echo "[+] Testing access to share: $share"

    if [[ "$AUTH" == "anon" ]]; then
        TEST_CMD="smbclient //$TARGET/$share -N -c exit"
        LOGIN_CMD="smbclient //$TARGET/$share -N"
    elif [[ "$AUTH" == "blank" ]]; then
        TEST_CMD="smbclient //$TARGET/$share -U $USER% -c exit"
        LOGIN_CMD="smbclient //$TARGET/$share -U $USER%"
    else
        TEST_CMD="smbclient //$TARGET/$share -U $USER%$PASS -c exit"
        LOGIN_CMD="smbclient //$TARGET/$share -U $USER%$PASS"
    fi

    eval $TEST_CMD >/dev/null 2>&1

    if [[ $? -eq 0 ]]; then
        echo "[+] ACCESS GRANTED: $share"
        echo "[+] Opening new terminal window for this share..."

        # Open a new terminal session
        if command -v gnome-terminal >/dev/null; then
            gnome-terminal -- bash -c "$LOGIN_CMD; exec bash"
        elif command -v xfce4-terminal >/dev/null; then
            xfce4-terminal --hold -e "$LOGIN_CMD"
        else
            echo "[!] No supported terminal found (gnome-terminal or xfce4-terminal)"
        fi
    else
        echo "[-] ACCESS DENIED: $share"
    fi
done

echo
echo "====================================================="
echo "[+] All accessible shares have been opened in new shells."
echo "====================================================="
