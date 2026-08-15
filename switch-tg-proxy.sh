#!/usr/bin/env bash
# =====================================================================
# Fox Auto host — تعویض امن آدرس پروکسی تلگرام برای foxteam-bot
#
# این اسکریپت:
#   1. آدرس جدید را از داخل همین سرور تست می‌کند
#   2. از فایل محیط بکاپ Timestampدار می‌گیرد
#   3. فقط TG_API_BASE و POLL_TIMEOUT_SECONDS را عوض می‌کند
#   4. سرویس را ری‌استارت کنترل‌شده می‌کند
#   5. لاگ همان بازه را بررسی می‌کند
#   6. اگر موفق نبود، خودکار به حالت قبل برمی‌گردد
#
# استفاده:
#   bash switch-tg-proxy.sh https://NAME.vercel.app
# =====================================================================

set -u

NEW_BASE="${1:-}"
APP_DIR="/root/foxteam-bot"
ENV_FILE="$APP_DIR/.env"
SERVICE="foxteam-bot"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/root/tg-proxy-switch-backups/$STAMP"

red()  { printf "\033[31m%s\033[0m\n" "$1"; }
grn()  { printf "\033[32m%s\033[0m\n" "$1"; }
ylw()  { printf "\033[33m%s\033[0m\n" "$1"; }

if [ -z "$NEW_BASE" ]; then
  red "آدرس جدید داده نشده است."
  echo "نمونه:"
  echo "  bash switch-tg-proxy.sh https://NAME.vercel.app"
  exit 1
fi

NEW_BASE="${NEW_BASE%/}"

echo "======================================================"
echo " مرحله ۱ — بررسی اولیه (Preflight)"
echo "======================================================"

if [ ! -f "$ENV_FILE" ]; then
  red "فایل محیط پیدا نشد: $ENV_FILE"
  exit 1
fi
grn "فایل محیط پیدا شد."

if ! systemctl list-unit-files | grep -q "^${SERVICE}.service"; then
  red "سرویس پیدا نشد: $SERVICE"
  exit 1
fi
grn "سرویس پیدا شد."

OLD_BASE="$(grep -E '^TG_API_BASE=' "$ENV_FILE" | head -1 | cut -d= -f2-)"
echo "آدرس فعلی:"
echo "  ${OLD_BASE:-<تنظیم‌نشده>}"
echo "آدرس جدید:"
echo "  $NEW_BASE"

echo
echo "======================================================"
echo " مرحله ۲ — تست آدرس جدید از داخل همین سرور"
echo "======================================================"

HEALTH_CODE="$(timeout 15 curl -s -o /tmp/tgproxy_health.json -w '%{http_code}' "$NEW_BASE/health" || echo 000)"
echo "کد پاسخ سلامت: $HEALTH_CODE"

if [ "$HEALTH_CODE" != "200" ]; then
  red "آدرس جدید از این سرور در دسترس نیست. هیچ تغییری انجام نشد."
  exit 1
fi
grn "پروکسی جدید پاسخ داد."
cat /tmp/tgproxy_health.json 2>/dev/null; echo

echo
echo "======================================================"
echo " مرحله ۳ — بکاپ Timestampدار"
echo "======================================================"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
cp -a "$ENV_FILE" "$BACKUP_DIR/.env.bak"
chmod 600 "$BACKUP_DIR/.env.bak"
sha256sum "$BACKUP_DIR/.env.bak" > "$BACKUP_DIR/env.sha256"
systemctl status "$SERVICE" --no-pager -l > "$BACKUP_DIR/service-status-before.txt" 2>&1

grn "بکاپ گرفته شد:"
echo "  $BACKUP_DIR/.env.bak"

if ! sha256sum -c "$BACKUP_DIR/env.sha256" >/dev/null 2>&1; then
  red "بررسی صحت بکاپ ناموفق بود. عملیات متوقف شد."
  exit 1
fi
grn "صحت بکاپ تأیید شد."

echo
echo "======================================================"
echo " مرحله ۴ — تغییر فایل محیط"
echo "======================================================"

TMP_ENV="$(mktemp)"
cp -a "$ENV_FILE" "$TMP_ENV"

if grep -qE '^TG_API_BASE=' "$TMP_ENV"; then
  sed -i "s|^TG_API_BASE=.*|TG_API_BASE=$NEW_BASE|" "$TMP_ENV"
else
  printf '\nTG_API_BASE=%s\n' "$NEW_BASE" >> "$TMP_ENV"
fi

if grep -qE '^POLL_TIMEOUT_SECONDS=' "$TMP_ENV"; then
  sed -i "s|^POLL_TIMEOUT_SECONDS=.*|POLL_TIMEOUT_SECONDS=15|" "$TMP_ENV"
else
  printf 'POLL_TIMEOUT_SECONDS=15\n' >> "$TMP_ENV"
fi

chmod 600 "$TMP_ENV"
mv -f "$TMP_ENV" "$ENV_FILE"
chmod 600 "$ENV_FILE"

grn "فایل محیط به‌روزرسانی شد (جابه‌جایی اتمی)."
echo "مقدار جدید:"
grep -E '^(TG_API_BASE|POLL_TIMEOUT_SECONDS)=' "$ENV_FILE" | sed 's/^/  /'

echo
echo "======================================================"
echo " مرحله ۵ — ری‌استارت کنترل‌شده"
echo "======================================================"

RESTART_TS="$(date '+%Y-%m-%d %H:%M:%S')"
systemctl restart "$SERVICE"
sleep 12

if ! systemctl is-active --quiet "$SERVICE"; then
  red "سرویس بالا نیامد. در حال بازگشت..."
  cp -a "$BACKUP_DIR/.env.bak" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  systemctl restart "$SERVICE"
  sleep 5
  systemctl is-active --quiet "$SERVICE" && ylw "بازگشت انجام شد و سرویس فعال است." || red "بازگشت انجام شد اما سرویس فعال نیست."
  exit 1
fi
grn "سرویس فعال است."

echo
echo "======================================================"
echo " مرحله ۶ — بررسی سلامت از روی لاگ"
echo "======================================================"

sleep 20
LOG="$(journalctl -u "$SERVICE" --since "$RESTART_TS" --no-pager 2>/dev/null | tail -n 60)"
echo "$LOG" | tail -n 25

FAILS="$(echo "$LOG" | grep -c 'fetch failed' || true)"
echo
echo "تعداد خطای fetch failed بعد از ری‌استارت: $FAILS"

if [ "$FAILS" -ge 3 ]; then
  red "خطاها ادامه دارند. در حال بازگشت خودکار..."
  cp -a "$BACKUP_DIR/.env.bak" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  systemctl restart "$SERVICE"
  sleep 5
  ylw "به حالت قبل برگشتیم. مسیر بکاپ:"
  echo "  $BACKUP_DIR/.env.bak"
  exit 1
fi

echo
echo "======================================================"
grn " نتیجه: تعویض پروکسی موفق بود"
echo "======================================================"
echo "آدرس جدید:"
echo "  $NEW_BASE"
echo "مسیر بکاپ:"
echo "  $BACKUP_DIR/.env.bak"
echo
echo "دستور بازگشت دستی در صورت نیاز:"
echo "  cp $BACKUP_DIR/.env.bak $ENV_FILE && systemctl restart $SERVICE"
echo
echo "حالا در تلگرام به ربات دستور /start بده و تست کن."
