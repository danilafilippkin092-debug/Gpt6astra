#!/data/data/com.termux/files/usr/bin/bash
# Read selected DBY-W09 partitions. Never writes to block devices or reboots.
set -euo pipefail
umask 077

for tool in su gzip sha256sum cut wc df awk; do
    command -v "$tool" >/dev/null || { echo "Missing command: $tool" >&2; exit 1; }
done
model=$(su -c 'getprop ro.product.model')
[[ "$model" == DBY-W09 ]] || { echo 'Stopped: model is not DBY-W09.' >&2; exit 1; }
[[ $(su -c 'id -u') == 0 ]] || { echo 'Stopped: root is unavailable.' >&2; exit 1; }

# Optional destination must be a NEW directory; existing backups are untouched.
output=${1:-"$HOME/storage/downloads/dby-backup-$(date +%Y%m%d-%H%M%S)-$$"}
[[ $# -le 1 ]] || { echo 'Usage: bash capture-termux.sh [NEW_OUTPUT_DIRECTORY]' >&2; exit 1; }
mkdir "$output"
trap 'echo "Stopped/incomplete. Keep files in: $output; .partial files are not verified backups." >&2' ERR
trap 'echo "Interrupted. Keep files in: $output" >&2; exit 130' INT TERM
free_kib=$(df -Pk "$output" | awk 'END {print $4}')
[[ "$free_kib" =~ ^[0-9]+$ && "$free_kib" -ge 307200 ]] || {
    echo 'At least 300 MiB free storage is required.' >&2; exit 1;
}
declare -A sizes
total=0
for name in boot dtbo vbmeta ramdisk xbl xbl_config abl; do
    bytes=$(su -c "blockdev --getsize64 /dev/block/by-name/$name")
    [[ "$bytes" =~ ^[0-9]+$ && "$bytes" -gt 0 && "$bytes" -le 134217728 ]] || {
        echo "Unexpected size for $name; stopped." >&2; exit 1;
    }
    sizes[$name]=$bytes
    total=$((total + bytes))
done
[[ "$total" -le 167772160 ]] || { echo 'Selected partitions exceed 160 MiB cap.' >&2; exit 1; }
printf 'Selected partition capture only; NOT a full recovery backup.\n' > "$output/STATUS.txt"
: > "$output/SHA256SUMS.txt"
: > "$output/partition-sizes.txt"

for name in boot dtbo vbmeta ramdisk xbl xbl_config abl; do
    source=/dev/block/by-name/$name
    bytes=$(su -c "blockdev --getsize64 $source")
    [[ "$bytes" == "${sizes[$name]}" ]] || { echo "Partition size changed: $name" >&2; exit 1; }
    before=$(su -c "sha256sum $source" | cut -d ' ' -f 1)
    [[ "$before" =~ ^[0-9a-f]{64}$ ]] || { echo "Invalid source hash: $name" >&2; exit 1; }
    partial="$output/$name.img.gz.partial"
    [[ ! -e "$partial" ]] || { echo 'Destination already exists.' >&2; exit 1; }
    echo "Reading $name ($bytes bytes) ..."
    # Compression writes only into Termux-accessible storage, never into /dev.
    (set -o noclobber; su -c "cat $source" | gzip -1 > "$partial")
    after=$(su -c "sha256sum $source" | cut -d ' ' -f 1)
    local_hash=$(gzip -dc "$partial" | sha256sum | cut -d ' ' -f 1)
    local_bytes=$(gzip -dc "$partial" | wc -c)
    [[ "$before" == "$after" && "$before" == "$local_hash" && "$local_bytes" -eq "$bytes" ]] || {
        echo "Size/SHA-256 mismatch: $name; .partial retained." >&2; exit 1;
    }
    # The whole destination directory is new; noclobber prevents replacement.
    final="$output/$name.img.gz"
    (set -o noclobber; cat "$partial" > "$final")
    cmp_hash=$(sha256sum "$partial" | cut -d ' ' -f 1)
    final_hash=$(sha256sum "$final" | cut -d ' ' -f 1)
    [[ "$cmp_hash" == "$final_hash" ]] || { echo 'Local publication failed.' >&2; exit 1; }
    rm "$partial"
    printf '%s %s\n' "$name" "$bytes" >> "$output/partition-sizes.txt"
    printf '%s  %s.img\n' "$before" "$name" >> "$output/SOURCE-AND-PLAIN-SHA256.txt"
    printf '%s  %s.img.gz\n' "$final_hash" "$name" >> "$output/SHA256SUMS.txt"
done
printf 'COMPLETE: all seven selected partitions verified by byte count and source/local SHA-256.\nNOT a full recovery backup; no partition writes performed.\n' >> "$output/STATUS.txt"
echo "Complete: $output"
