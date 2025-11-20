#!/bin/bash

# ================================================================
#  SMB Auto Enumerator + Recursive Downloader (Safe for HTB/Labs)
#  English version with interactive username/password selection
# ================================================================

echo "=== SMB AUTO ENUM & DOWNLOAD TOOL ==="
read -p "[+] Enter target IP: " TARGET

echo
echo "[?] Choose authentication method:"
echo "    1) Anonymous (no username, no password)"
echo "    2) Username ONLY (blank password)"
echo "    3) Username + Password"
read -p "[+] Your choice (1/2/3): " AUTH_CHOICE
echo

USER=""
PASS=""
USECREDS="n"

case "$AUTH_CHOICE" in
    1)
        echo "[+] Using anonymous mode."
        USECREDS="anon"
        ;;
    2)
        read -p "[+] Enter username: " USER
        echo "[+] Using blank password for user '$USER'."
        USECREDS="blank"
        ;;
    3)
        read -p "[+] Enter username: " USER
        read -s -p "[+] Enter password: " PASS
        echo
        USECREDS="full"
        ;;
    *)
        echo "[!] Invalid choice. Exiting."
        exit 1
        ;;
esac

OUTPUT_DIR="smb_loot_$TARGET"
mkdir -p "$OUTPUT_DIR"

echo
echo "[+] Target: $TARGET"
echo "[+] Output directory: $OUTPUT_DIR"
echo

# -----------------------------------------------------------
# 1. ENUMERATE SHARES
# -----------------------------------------------------------

echo "[+] Enumerating SMB shares..."

if [[ "$USECREDS" == "anon" ]]; then
    smbclient -L "//$TARGET" -N | tee "$OUTPUT_DIR/shares.txt"

elif [[ "$USECREDS" == "blank" ]]; then
    smbclient -L "//$TARGET" -U "$USER%" | tee "$OUTPUT_DIR/shares.txt"

else
    smbclient -L "//$TARGET" -U "$USER%$PASS" | tee "$OUTPUT_DIR/shares.txt"
fi

echo "[+] Share enumeration completed."
echo

# Extract share names
SHARES=$(grep "Disk" "$OUTPUT_DIR/shares.txt" | awk '{print $1}')

echo "[+] Shares found:"
echo "$SHARES"
echo

# -----------------------------------------------------------
# 2. TRY ACCESS EACH SHARE + DOWNLOAD FILES
# -----------------------------------------------------------

for share in $SHARES; do
    echo "======================================================="
    echo "[+] Testing share: $share"

    LOOT_PATH="$OUTPUT_DIR/$share"
    mkdir -p "$LOOT_PATH"

    # Build access & download commands based on auth type
    if [[ "$USECREDS" == "anon" ]]; then
        ACCESS_CMD="smbclient //$TARGET/$share -N"
        DL_CMD="smbclient //$TARGET/$share -N -c \"recurse ON; prompt OFF; mget *\""

    elif [[ "$USECREDS" == "blank" ]]; then
        ACCESS_CMD="smbclient //$TARGET/$share -U $USER%"
        DL_CMD="smbclient //$TARGET/$share -U $USER% -c \"recurse ON; prompt OFF; mget *\""

    else
        ACCESS_CMD="smbclient //$TARGET/$share -U $USER%$PASS"
        DL_CMD="smbclient //$TARGET/$share -U $USER%$PASS -c \"recurse ON; prompt OFF; mget *\""
    fi

    echo "[+] Checking access..."
    eval "$ACCESS_CMD -c exit" >/dev/null 2>&1

    if [[ $? -eq 0 ]]; then
        echo "[+] Access granted for: $share"
        echo "[+] Downloading files..."
        pushd "$LOOT_PATH" >/dev/null
        eval "$DL_CMD"
        popd >/dev/null
        echo "[+] Download finished → $LOOT_PATH"
    else
        echo "[-] Access denied for: $share"
    fi

done

echo "======================================================="
echo "[+] All accessible shares have been downloaded."
echo "[+] Loot saved inside: $OUTPUT_DIR"
echo "======================================================="
