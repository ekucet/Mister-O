#!/usr/bin/env bash
# Mister-O senaryolarını bir iOS simülatöründe, staging uygulamasının içinde koşturur.
#
# GitHub Actions'ta `uses: ekucet/Mister-O/ci@<sürüm>` bu betiği çağırır; yerelde de çalışır:
#
#   INPUT_APP=build/Build/Products/Debug-iphonesimulator/MyApp.app INPUT_SCENARIOS="#smoke" ci/run.sh
#
# Girdiler (ortam değişkeni):
#   INPUT_APP           Simülatör için derlenmiş .app (zorunlu)
#   INPUT_SCENARIOS     "#smoke", "all", "login-success,#auth" (varsayılan: all)
#   INPUT_BUNDLE_ID     Boşsa .app'in Info.plist'inden okunur
#   INPUT_DEVICE        Simülatör UDID'si ya da adı; boşsa en yeni iOS'taki ilk iPhone
#   INPUT_TIMEOUT       Saniye (varsayılan: 900)
#   INPUT_RESULTS       Sonuç klasörü (varsayılan: mistero-results)
#   INPUT_OPEN_TICKETS  "false" ise düşen senaryolar için kayıt açılmaz
#   INPUT_ENV           Uygulamaya verilecek ek ortam değişkenleri, satır başına KEY=VALUE
#
# Çıkış kodu: düşen senaryo varsa ya da sonuç yazılmadıysa 1.
set -euo pipefail

app="${INPUT_APP:?INPUT_APP: simülatör için derlenmiş .app yolu gerekli}"
scenarios="${INPUT_SCENARIOS:-all}"
timeout="${INPUT_TIMEOUT:-900}"
results="${INPUT_RESULTS:-mistero-results}"
bundle="${INPUT_BUNDLE_ID:-}"
device="${INPUT_DEVICE:-}"

[ -d "$app" ] || { echo "::error::$app bulunamadı."; exit 1; }
if [ -z "$bundle" ]; then
  bundle=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Info.plist")
fi

if [ -z "$device" ]; then
  # Liste runtime'a göre artan sırada; son iOS bölümündeki ilk iPhone en yeni sistemdir.
  device=$(xcrun simctl list devices available | awk '
    /^-- iOS / { section = 1; first = ""; next }
    /^-- /     { section = 0; next }
    section && first == "" && /iPhone/ { if (match($0, /[0-9A-F-]{36}/)) first = substr($0, RSTART, RLENGTH); found = first }
    END { print found }')
fi
[ -n "$device" ] || { echo "::error::Kullanılabilir iPhone simülatörü yok."; exit 1; }

echo "Mister-O · $bundle · $scenarios · simulator $device"
xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" -b >/dev/null
xcrun simctl install "$device" "$app"

container=$(xcrun simctl get_app_container "$device" "$bundle" data)
rm -rf "$container/Documents/MisterO/results"
mkdir -p "$results"
log="$results/console.log"

export SIMCTL_CHILD_MISTERO_AUTORUN="$scenarios"
export SIMCTL_CHILD_MISTERO_EXIT=1
if [ "${INPUT_OPEN_TICKETS:-true}" = "false" ]; then
  export SIMCTL_CHILD_MISTERO_TICKETS=0
fi
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  [ -n "$line" ] && export "SIMCTL_CHILD_${line}"
done <<< "${INPUT_ENV:-}"

# Uygulama koşu bitince kendini kapatır; takılırsa süre dolunca kapatılır.
xcrun simctl launch --console-pty --terminate-running-process "$device" "$bundle" > "$log" 2>&1 &
launch=$!
(
  for ((second = 0; second < timeout; second++)); do
    kill -0 "$launch" 2>/dev/null || exit 0
    sleep 1
  done
  echo "Mister-O: $timeout s doldu, uygulama kapatılıyor." >> "$log"
  xcrun simctl terminate "$device" "$bundle" 2>/dev/null || true
) &
watchdog=$!
wait "$launch" || true
wait "$watchdog" || true

sed -n '/MISTERO-RESULT-BEGIN/,/MISTERO-RESULT-END/p' "$log" | sed '/MISTERO-RESULT-/d'
cp "$container"/Documents/MisterO/results/* "$results"/ 2>/dev/null || true

if [ ! -f "$results/report.json" ]; then
  echo "::error::Mister-O sonuç yazmadı. Konsol: $log"
  tail -40 "$log"
  exit 1
fi

total=$(plutil -extract total raw -o - "$results/report.json")
passed=$(plutil -extract passed raw -o - "$results/report.json")
failed=$(plutil -extract failed raw -o - "$results/report.json")
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "$results/summary.md" >> "$GITHUB_STEP_SUMMARY"
fi
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  { echo "total=$total"; echo "passed=$passed"; echo "failed=$failed"; echo "results=$results"; } >> "$GITHUB_OUTPUT"
fi

if [ "$failed" -gt 0 ]; then
  echo "::error::Mister-O: $total senaryodan $failed tanesi düştü."
  exit 1
fi
echo "Mister-O: $passed/$total senaryo geçti."
