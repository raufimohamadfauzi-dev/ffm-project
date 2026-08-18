#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$PROJECT_DIR/android"
SIGNING_DIR="${HOME}/ffm-signing"
KEYSTORE_PATH="$SIGNING_DIR/ffm-release.jks"
CREDENTIALS_PATH="$SIGNING_DIR/ffm-release-credentials.txt"
KEY_PROPERTIES_PATH="$ANDROID_DIR/key.properties"

mkdir -p "$SIGNING_DIR"
chmod 700 "$SIGNING_DIR"

if [[ -e "$KEYSTORE_PATH" || -e "$CREDENTIALS_PATH" || -e "$KEY_PROPERTIES_PATH" ]]; then
  echo "Release signing sudah pernah dibuat. Tidak menimpa file yang ada." >&2
  echo "Keystore: $KEYSTORE_PATH" >&2
  echo "Kredensial: $CREDENTIALS_PATH" >&2
  echo "Gradle properties: $KEY_PROPERTIES_PATH" >&2
  exit 2
fi

# Jika pipe tr/head menerima SIGPIPE, jangan membuat proses gagal sebelum file selesai.
set +o pipefail
STORE_PASSWORD="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
KEY_PASSWORD="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
set -o pipefail

keytool -genkeypair \
  -v \
  -keystore "$KEYSTORE_PATH" \
  -storetype JKS \
  -storepass "$STORE_PASSWORD" \
  -keypass "$KEY_PASSWORD" \
  -alias ffm_release \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000 \
  -dname "CN=FFM Release, OU=Family Finance Manager, O=Family Finance Manager, L=Local, ST=Local, C=ID" \
  -noprompt

cat > "$CREDENTIALS_PATH" <<EOF
# FFM release signing credentials - KEEP PRIVATE
storeFile=$KEYSTORE_PATH
storePassword=$STORE_PASSWORD
keyAlias=ffm_release
keyPassword=$KEY_PASSWORD
EOF

cat > "$KEY_PROPERTIES_PATH" <<EOF
storeFile=$KEYSTORE_PATH
storePassword=$STORE_PASSWORD
keyAlias=ffm_release
keyPassword=$KEY_PASSWORD
EOF

chmod 600 "$KEYSTORE_PATH" "$CREDENTIALS_PATH" "$KEY_PROPERTIES_PATH"

printf 'Release keystore berhasil dibuat.\n'
printf 'Keystore: %s\n' "$KEYSTORE_PATH"
printf 'Kredensial: %s\n' "$CREDENTIALS_PATH"
printf 'Gradle properties: %s\n' "$KEY_PROPERTIES_PATH"
printf 'Alias: ffm_release\n'
printf 'Package ID target: com.ffm_manager\n'
printf 'Nama launcher target: FFM\n'

printf '\nFingerprint SHA-256:\n'
keytool -list -v -keystore "$KEYSTORE_PATH" -storepass "$STORE_PASSWORD" -alias ffm_release \
  | awk -F': ' '/^Certificate fingerprints:/{found=1; next} found && /SHA256:/{print $2; exit}'
