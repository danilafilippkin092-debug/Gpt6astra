#!/data/data/com.termux/files/usr/bin/bash
# DBY-W09 remaining diagnostics. Read-only tablet queries; local report writes only.
# No boot flashing, sysctl changes, module loading, rebooting, or network uploads.
set -euo pipefail
umask 077

for tool in su tar gzip sha256sum timeout head wc find sort xargs; do
    command -v "$tool" >/dev/null || { echo "Missing: $tool" >&2; exit 1; }
done
[[ $(su -c 'getprop ro.product.model') == DBY-W09 ]] || {
    echo 'Stopped: this collector is for DBY-W09 only.' >&2; exit 1;
}
[[ $(su -c 'id -u') == 0 ]] || { echo 'Root access is required.' >&2; exit 1; }

[[ $# -le 1 ]] || { echo 'Usage: bash collect-full-termux.sh [EXISTING_OUTPUT_PARENT]' >&2; exit 1; }
base=${1:-"$HOME/storage/downloads"}
[[ -d "$base" && -w "$base" ]] || {
    echo 'Run termux-setup-storage first and allow storage access.' >&2; exit 1;
}
name="dby-full-check-$(date +%Y%m%d-%H%M%S)-$$"
out="$base/$name"
mkdir "$out"
mkdir "$out/reports" "$out/optional"
printf 'Item\tResult\n' > "$out/COLLECTION-STATUS.tsv"
trap 'echo "Interrupted: partial report is in $out" >&2; exit 130' INT TERM

record() { printf '%s\t%s\n' "$1" "$2" >> "$out/COLLECTION-STATUS.tsv"; }

collect() {
    local label=$1 command=$2 rc
    echo "Checking: $label"
    # Bound optional text output. SIGPIPE at the cap is recorded as incomplete.
    if timeout 45 su -c "$command" 2>"$out/reports/$label.errors.txt" |
        head -c 1048577 > "$out/reports/$label.txt"; then
        if [[ $(wc -c < "$out/reports/$label.txt") -gt 1048576 ]]; then
            record "$label" 'OUTPUT_LIMIT_REACHED'
        else
            record "$label" 'READ_OK'
        fi
    else
        rc=$?
        record "$label" "UNAVAILABLE_OR_INCOMPLETE_EXIT_$rc"
    fi
}

copied_bytes=0
copy_optional() {
    local source=$1 target=$2 count rc
    # Only the explicit headers/symvers/config paths below are inputs.
    if ! timeout 15 su -c "test -r '$source'"; then
        record "$target" 'NOT_AVAILABLE'; return;
    fi
    echo "Copying optional build input: $target"
    if timeout 60 su -c "head -c 8388609 '$source'" \
        > "$out/optional/$target.partial" 2>"$out/optional/$target.errors.txt"; then
        count=$(wc -c < "$out/optional/$target.partial")
        if [[ "$count" -gt 8388608 || $((copied_bytes + count)) -gt 16777216 ]]; then
            rm "$out/optional/$target.partial"
            record "$target" 'TOO_LARGE_NOT_INCLUDED'; return;
        fi
        mv "$out/optional/$target.partial" "$out/optional/$target"
        copied_bytes=$((copied_bytes + count))
        record "$target" 'COPIED_UNVERIFIED_BUILD_INPUT'
    else
        rc=$?
        rm -f "$out/optional/$target.partial"
        record "$target" "COPY_FAILED_EXIT_$rc"
    fi
}

collect 01-kernel 'uname -srv; cat /proc/version'
collect 02-build 'for k in ro.product.model ro.product.device ro.product.board ro.board.platform ro.hardware ro.build.display.id ro.build.fingerprint ro.build.version.release ro.build.version.sdk ro.build.version.security_patch ro.boot.flash.locked ro.boot.vbmeta.device_state ro.boot.verifiedbootstate ro.boot.slot_suffix; do printf "%s=" "$k"; getprop "$k"; done'
collect 03-kexec-state 'for p in /sys/kernel/kexec_loaded /sys/kernel/kexec_crash_loaded /proc/sys/kernel/kexec_load_disabled /proc/sys/kernel/modules_disabled /proc/sys/kernel/kptr_restrict; do echo "--- $p"; if [ -r "$p" ]; then cat "$p"; else echo unavailable; fi; done; getenforce'
collect 04-symbols 'grep -E " (__arm64_sys_kexec_load|sys_kexec_load|compat_sys_kexec_load|kexec_load|kernel_kexec|machine_kexec|machine_crash_shutdown|cpu_soft_restart|__cpu_soft_restart|stop_machine|smp_send_stop|kernel_restart|machine_restart|kimage_alloc_init|kallsyms_lookup_name)$" /proc/kallsyms'
collect 05-modules 'cat /proc/modules'
collect 06-module-paths 'for p in /system/lib/modules /vendor/lib/modules /odm/lib/modules /vendor_dlkm/lib/modules /system_dlkm/lib/modules /lib/modules; do echo "--- $p"; if [ -d "$p" ]; then ls -ld "$p"; find "$p" -maxdepth 3 -type f -name "*.ko" -print; else echo unavailable; fi; done'
collect 07-build-input-paths 'r=$(uname -r); for p in /sys/kernel/kheaders.tar.xz /proc/config.gz /lib/modules/"$r"/build /lib/modules/"$r"/source /lib/modules/"$r"/build/Module.symvers /vendor/lib/modules/Module.symvers /odm/lib/modules/Module.symvers /vendor_dlkm/lib/modules/Module.symvers; do echo "--- $p"; ls -ld "$p" 2>&1 || true; done'
collect 08-memory 'cat /proc/meminfo; echo "=== IOMEM ==="; cat /proc/iomem'
collect 09-partition-layout 'ls -l /dev/block/by-name /dev/block/bootdevice/by-name'
collect 10-current-partition-hashes 'for n in boot dtbo vbmeta ramdisk xbl xbl_config abl; do p=/dev/block/by-name/$n; echo "--- $n"; if [ -b "$p" ]; then blockdev --getsize64 "$p"; sha256sum "$p"; else echo unavailable; fi; done'
collect 11-framebuffer 'for p in /sys/class/graphics/fb0/name /sys/class/graphics/fb0/virtual_size /sys/class/graphics/fb0/bits_per_pixel /sys/class/graphics/fb0/stride /sys/class/graphics/fb0/modes /sys/class/graphics/fb0/state; do echo "--- $p"; if [ -r "$p" ]; then cat "$p"; else echo unavailable; fi; done'
collect 12-drm 'for p in /sys/class/drm/card*-*/status /sys/class/drm/card*-*/enabled /sys/class/drm/card*-*/modes; do if [ -r "$p" ]; then echo "--- $p"; head -c 4096 "$p"; fi; done; true'
collect 13-pstore 'for p in /sys/fs/pstore /sys/module/ramoops /sys/module/kexec_core; do ls -ld "$p" 2>&1 || true; done'

copy_optional /proc/config.gz config.gz
copy_optional /sys/kernel/kheaders.tar.xz kheaders.tar.xz
copy_optional /vendor/lib/modules/Module.symvers vendor-Module.symvers
copy_optional /odm/lib/modules/Module.symvers odm-Module.symvers
copy_optional /vendor_dlkm/lib/modules/Module.symvers vendor-dlkm-Module.symvers
release=''
if ! release=$(timeout 15 su -c 'uname -r'); then
    record kernel-release 'UNAVAILABLE'; release=''
fi
if [[ "$release" =~ ^[A-Za-z0-9._+-]+$ ]]; then
    copy_optional "/lib/modules/$release/build/Module.symvers" build-Module.symvers
    copy_optional "/lib/modules/$release/build/include/generated/autoconf.h" autoconf.h
    copy_optional "/lib/modules/$release/build/include/generated/utsrelease.h" utsrelease.h
    copy_optional "/lib/modules/$release/build/.config" build.config
fi
if [[ -f "$out/optional/config.gz" ]]; then
    if gzip -t "$out/optional/config.gz"; then
        gzip -dc "$out/optional/config.gz" > "$out/reports/running.config"
        record config.gz 'GZIP_VALID_CONFIG_EXTRACTED'
    else
        record config.gz 'INVALID_GZIP'
    fi
fi

printf '%s\n' \
    'REPORT_COLLECTION_FINISHED. Check COLLECTION-STATUS.tsv for missing or failed items.' \
    'This is NOT a source tree, NOT a full recovery backup, and NOT proof that kexec can be built or run.' \
    'Prior boot/DTB/partition dumps are intentionally not duplicated.' \
    'No flashing, module loading, rebooting, sysctl changes or network uploads were performed.' \
    > "$out/README.txt"
(
    cd "$out"
    find . -type f ! -name SHA256SUMS.txt -print0 |
        sort -z | xargs -0 sha256sum > SHA256SUMS.txt
)
archive="$base/$name.tar.gz"
tar -czf "$archive" -C "$base" "$name"
gzip -t "$archive"
echo "READY: $archive"
echo 'Send this ONE .tar.gz file privately in the chat. Do not publish device reports on GitHub.'
