#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_dir="$repo_root/release-artifacts"
mkdir -p "$release_dir"

sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$sdk_root" || ! -d "$sdk_root" ]]; then
  for candidate in "$HOME/android-sdk" "$HOME/Android/Sdk"; do
    if [[ -d "$candidate" ]]; then
      sdk_root="$candidate"
      break
    fi
    done
fi

if [[ -z "$sdk_root" || ! -d "$sdk_root" ]]; then
  printf 'ERROR: Android SDK tidak ditemukan.\n' >&2
  exit 1
fi
export ANDROID_HOME="$sdk_root"
export ANDROID_SDK_ROOT="$sdk_root"

last_number=0
shopt -s nullglob
for artifact in "$release_dir"/ffm-release-*-arm64.apk; do
  name="$(basename "$artifact")"
  number="${name#ffm-release-}"
  number="${number%-arm64.apk}"
  if [[ "$number" =~ ^[0-9]+$ ]] && ((10#$number > last_number)); then
    last_number=$((10#$number))
  fi
done
next_number=$((last_number + 1))
artifact_name="ffm-release-$(printf '%02d' "$next_number")-arm64.apk"

export ANDROID_ABI="arm64-v8a"
cd "$repo_root"
flutter build apk --target-platform android-arm64 --release
source_apk="$repo_root/build/app/outputs/flutter-apk/app-release.apk"
cp "$source_apk" "$release_dir/$artifact_name"
apk_path="$release_dir/$artifact_name"
sha256="$(sha256sum "$apk_path" | awk '{print $1}')"
printf '%s  %s\n' "$sha256" "$artifact_name" | tee "$apk_path.sha256"

mapfile -t abis < <(
  zipinfo -1 "$apk_path" \
    | awk -F/ '$1 == "lib" && NF >= 3 {print $2}' \
    | sort -u
)
if (( ${#abis[@]} != 1 )) || [[ "${abis[0]:-}" != "arm64-v8a" ]]; then
  printf 'ERROR: APK ABI harus hanya arm64-v8a; ditemukan: %s\n' "${abis[*]:-tidak ada}" >&2
  exit 1
fi

apksigner_path="$(command -v apksigner || true)"
if [[ -z "$apksigner_path" && -d "$sdk_root/build-tools" ]]; then
  apksigner_path="$(find "$sdk_root/build-tools" -type f -name apksigner -print | sort -V | tail -n 1)"
fi
if [[ -z "$apksigner_path" ]]; then
  printf 'ERROR: apksigner tidak ditemukan; signature tidak dapat diverifikasi.\n' >&2
  exit 1
fi
verify_output="$(mktemp)"
trap 'rm -f "$verify_output"' EXIT
"$apksigner_path" verify --verbose "$apk_path" >"$verify_output" 2>&1
grep -qE 'Verified using v2 scheme .*: true' "$verify_output"
grep -q 'Number of signers: 1' "$verify_output"

manifest="$apk_path.manifest.txt"
{
  printf 'artifact=%s\n' "$artifact_name"
  printf 'sha256=%s\n' "$sha256"
  printf 'abi=%s\n' "${abis[0]}"
  grep -E 'Verified using v[123] scheme|Number of signers' "$verify_output"
} | tee "$manifest"
printf 'APK_RELEASE=%s\n' "$apk_path"
printf 'APK_MANIFEST=%s\n' "$manifest"
