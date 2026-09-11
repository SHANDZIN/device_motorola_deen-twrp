#!/bin/bash

set -e

TOP="${ANDROID_BUILD_TOP:-$(pwd)}"
MAKEFILE="${TOP}/build/make/core/Makefile"

MARKER="# deen: generate recovery installer cpio"

if [ ! -f "$MAKEFILE" ]; then
    echo "deen: build/make/core/Makefile not found"
    exit 1
fi

if grep -qF "$MARKER" "$MAKEFILE"; then
    echo "deen: recovery installer cpio patch already applied"
    exit 0
fi

export TOP
export MAKEFILE
export MARKER

python3 <<'EOF'
import os

path = os.environ["MAKEFILE"]
marker = os.environ["MARKER"]

with open(path, "r") as f:
    data = f.read()

target = (
    "\t\t$(hide) $(MKBOOTFS) -d $(TARGET_OUT) "
    "$(TARGET_RECOVERY_ROOT_OUT) | "
    "$(RECOVERY_RAMDISK_COMPRESSOR) > $(recovery_ramdisk)"
)

if target not in data:
    raise SystemExit(
        "deen: recovery ramdisk generation line was not found in "
        "build/make/core/Makefile"
    )

replacement = (
    f"\t\t{marker}\n"
    "\t\t$(hide) $(MKBOOTFS) "
    "$(TARGET_RECOVERY_ROOT_OUT) > "
    "$(recovery_uncompressed_ramdisk)\n"
    f"{target}"
)

data = data.replace(target, replacement, 1)

with open(path, "w") as f:
    f.write(data)

print("deen: recovery installer cpio patch applied")
EOF

echo
echo "deen: patched section:"
grep -n -C 4 \
    -e "$MARKER" \
    -e 'recovery_uncompressed_ramdisk' \
    "$MAKEFILE" || true
