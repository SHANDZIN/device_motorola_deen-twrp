#!/system/bin/sh
# touchdump_deen.sh v2 - coleta logs de touch/USB sem precisar de touch nem USB
# Roda sozinho no boot do TWRP via init.recovery.qcom.rc -> copia tudo pro microSD
# Como usar:
#  1. Coloque um microSD FAT32 no aparelho
#  2. De boot no TWRP, mexa no touch e desplugue/replugue o USB se quiser testar
#  3. Aguarde ~2min (dump1=boot, dump2=+70s). Sem vibrador com qti-haptics
#     (driver FF sem sysfs): confira fim via adb, com o cabo plugado:
#     adb shell cat /tmp/touch-deen/dump2/done.txt
#  4. Force reboot (Power 10s), leia o SD no PC: pasta /touch-deen/

LOGDIR=/tmp/touch-deen
SDDIR=/external_sd/touch-deen
DATADIR=/data/media/0/touch-deen

mkdir -p "$LOGDIR"

dodump() {
  P="$LOGDIR/$1"
  mkdir -p "$P"
  dmesg > "$P/dmesg.txt" 2>&1
  cat /proc/version > "$P/version.txt" 2>&1
  cat /proc/cmdline > "$P/cmdline.txt" 2>&1
  cat /proc/interrupts > "$P/interrupts.txt" 2>&1
  ls -l /sys/bus/i2c/devices/ > "$P/i2c-devices.txt" 2>&1
  ls -l /dev/input/ > "$P/input-dev.txt" 2>&1

  # filtra touch/usb pra achar rapido no PC
  dmesg | grep -i -E "NVT|novatek|focal|ft5x06|ft8006|touch|i2c_3|3-0062|3-0038|gpio.*6[45]|irq.*6[45]|chip is not|CTP_I2C|trim|product_id|buf\[1\]|ESD|esd|FW|firmware|recovery" > "$P/dmesg-touch.txt" 2>&1
  dmesg | grep -i -E "dwc3|UDC|usb_gadget|android_work|USB_STATE|functionfs|read descriptor|fusb|FUSB|typec|dual_role|usbc|smbcharger|power_supply|CONNECTED|DISCONNECTED|enumerat" > "$P/dmesg-usb.txt" 2>&1
  cat /proc/interrupts | grep -i -E "touch|NVT|ft|arch|65|msm|dwc3|hs_phy|pwr_event" > "$P/interrupts-touch.txt" 2>&1

  # i2c bus 3: 3-0062=NVT HW, 3-0038=FT
  for f in /sys/bus/i2c/devices/3-*/name; do
    echo "== $f" >> "$P/i2c-names.txt" 2>&1
    cat "$f" >> "$P/i2c-names.txt" 2>&1
  done
  ls -l /sys/bus/i2c/devices/3-* >> "$P/i2c-names.txt" 2>&1
  # i2c bus 1: 1-0022=FUSB302
  for f in /sys/bus/i2c/devices/1-*/name; do
    echo "== $f" >> "$P/i2c-names.txt" 2>&1
    cat "$f" >> "$P/i2c-names.txt" 2>&1
  done

  getevent -lp > "$P/getevent.txt" 2>&1

  # estado USB: UDC, dual-role, psy usbc, FUSB
  ls -l /sys/class/udc/ > "$P/udc.txt" 2>&1
  for s in /sys/class/udc/*/state; do
    echo "== $s: $(cat $s 2>/dev/null)" >> "$P/udc.txt" 2>&1
  done
  ls -lR /config/usb_gadget/g1/ > "$P/gadget.txt" 2>&1
  ls -l /dev/usb-ffs/ /dev/usb-ffs/adb/ /dev/usb-ffs/mtp/ > "$P/ffs.txt" 2>&1
  ls -l /sys/class/leds/ /sys/class/timed_output/ > "$P/leds.txt" 2>&1
  ls -l /proc/asound/ > "$P/snd.txt" 2>&1
  cat /proc/asound/cards >> "$P/snd.txt" 2>&1
  ls -l /sys/class/dual_role_usb/ > "$P/dual-role.txt" 2>&1
  for d in /sys/class/dual_role_usb/*/; do
    echo "== $d" >> "$P/dual-role.txt" 2>&1
    for p in "$d"*; do
      echo "-- $p: $(cat $p 2>/dev/null)" >> "$P/dual-role.txt" 2>&1
    done
  done
  ls -l /sys/class/power_supply/ > "$P/psy.txt" 2>&1
  for p in /sys/class/power_supply/usbc/*; do
    echo "-- $p: $(cat $p 2>/dev/null)" >> "$P/psy.txt" 2>&1
  done

  # gpio 64=touch reset 65=touch irq
  for g in 64 65; do
    echo "== gpio$g" >> "$P/gpio.txt" 2>&1
    cat /sys/class/gpio/gpio$g/value >> "$P/gpio.txt" 2>&1 || echo "no sysfs gpio$g" >> "$P/gpio.txt" 2>&1
  done
  cat /sys/kernel/debug/gpio > "$P/gpio-debug.txt" 2>&1

  # inputs + proc do NVT/FT
  ls -l /proc/NVT* /proc/ft* /sys/class/input/input*/name > "$P/proc-touch.txt" 2>&1
  for n in /sys/class/input/input*/name; do
    echo "== $n: $(cat $n 2>/dev/null)" >> "$P/proc-touch.txt" 2>&1
  done

  # log do proprio TWRP
  cp /tmp/recovery.log "$P/recovery.log" 2>/dev/null
  getprop > "$P/getprop.txt" 2>&1
  echo "dump=$1 date=$(date 2>/dev/null)" > "$P/done.txt" 2>&1
}

docopy() {
  mkdir -p /external_sd /data
  mount -t f2fs -o rw /dev/block/bootdevice/by-name/userdata /data 2>/dev/null
  mount -t ext4 -o rw /dev/block/bootdevice/by-name/userdata /data 2>/dev/null
  mount -o rw /dev/block/bootdevice/by-name/userdata /data 2>/dev/null
  for i in 1 2 3; do
    mount -t vfat -o rw /dev/block/mmcblk1p1 /external_sd 2>/dev/null
    mount -t exfat -o rw /dev/block/mmcblk1p1 /external_sd 2>/dev/null
    mount -o rw /dev/block/mmcblk1p1 /external_sd 2>/dev/null
    mount -o rw /dev/block/mmcblk1 /external_sd 2>/dev/null
    ls /external_sd >/dev/null 2>&1 && break
    sleep 5
  done
  for DEST in "$SDDIR" "$DATADIR" /persist/touch-deen; do
    mkdir -p "$DEST" 2>/dev/null
    cp -rf "$LOGDIR"/* "$DEST"/ 2>/dev/null
  done
  sync
}

# dump1: 20s apos boot (probe + 1a conexao USB)
sleep 20
dodump dump1
docopy

# dump2: +70s (pega replug USB, loops ESD, lentidao do touch)
sleep 70
dodump dump2
docopy

# fim: tenta vibrar 3x (so funciona com driver LED/timed_output, ex. qpnp;
# com qti-haptics FF nao ha sysfs -> silencioso, ver done.txt via adb)
for i in 1 2 3; do
  for V in /sys/class/timed_output/vibrator/enable /sys/class/leds/vibrator/brightness; do
    echo 200 > "$V" 2>/dev/null
  done
  sleep 1
done
