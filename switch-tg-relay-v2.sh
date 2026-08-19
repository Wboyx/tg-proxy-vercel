#!/usr/bin/env bash
# =====================================================================
# Fox Auto host — تعویض امن مسیر Bot API برای foxteam-bot
# نسخه ۲ — 2026-08-19
#
# تفاوت با نسخه ۱:
#   1. تست سلامت با مسیر واقعی getMe انجام می‌شود، نه مسیر ساختگی /health
#      دلیل: هر رله‌ای مسیر /health ندارد و نسخه ۱ روی 404 متوقف می‌شد
#   2. تست سه بار تکرار می‌شود تا یک لرزش موقت باعث تصمیم اشتباه نشود
#   3. بعد از سوییچ هم دوباره از بیرون تست می‌شود
#   4. برچسب _relay در لاگ بررسی می‌شود
#   5. Token هیچ‌جا چاپ نمی‌شود و در خروجی Redact می‌شود
#
# استفاده:
#   bash switch-tg-relay-v2.sh https://NEW-BASE
#
# این اسکریپت فقط دو خط از فایل محیط را عوض می‌کند:
#   TG_API_BASE
#   POLL_TIMEOUT_SECONDS
# =====================================================================

set -u

NEW_BASE="${1:-}"
APP_DIR="/root/foxteam-bot"
ENV_FILE="$APP_DIR/.env"
SERVICE="foxteam-bot"
POLL_VALUE="${POLL_VALUE:-12}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/root/tg-proxy-switch-backups/$STAMP"

red() { printf "\033[31m%s\033[0m\n" "$1"; }
grn() { printf "\033[32m%s\033[0m\n" "$1"; }
ylw() { printf "\033[33m%s\033[0m\n" "$1"; }
hr()  { echo "======================================================"; }

if [ -z "$NEW_BASE" ]; then
  red "آدرس جدید داده نشده است."
  echo "نمونه:"
  echo "  bash switch-tg-relay-v2.sh https://mehti-gw-4821.vercel.app"
  exit 1
fi
NEW_BASE="${NEW_BASE%/}"

hr; echo " مرحله ۱ — بررسی اولیه"; hr

[ -f "$ENV_FILE" ] || { red "فایل محیط پیدا نشد: $ENV_FILE"; exit 1; }
grn "فایل محیط پیدا شد."

systemctl list-unit-files | grep -q "^${SERVICE}.service" || { red "سرویس پیدا نشد: $SERVICE"; exit 1; }
grn "سرویس پیدا شد."

TOKEN="$(grep -E '^BOT_TOKEN=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"'"'"' ')"
[ -n "$TOKEN" ] || { red "BOT_TOKEN در فایل محیط پیدا نشد."; exit 1; }
grn "Token خوانده شد. طول: ${#TOKEN}  (چاپ نمی‌شود)"

OLD_BASE="$(grep -E '^TG_API_BASE=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"'"'"' ')"
echo "آدرس فعلی:"; echo "  ${OLD_BASE:-<تنظیم‌نشده>}"
echo "آدرس جدید:"; echo "  $NEW_BASE"

echo
hr; echo " مرحله ۲ — تست واقعی آدرس جدید از داخل همین سرور"; hr

OK_COUNT=0
BOT_NAME=""
for i in 1 2 3; do
  RESP="$(timeout 20 curl -s --max-time 18 -w '\n%{http_code} %{time_total}' "$NEW_BASE/bot$TOKEN/getMe" 2>/dev/null)"
  CODE="$(echo "$RESP" | tail -1 | awk '{print $1}')"
  TIME="$(echo "$RESP" | tail -1 | awk '{print $2}')"
  BODY="$(echo "$RESP" | head -n -1)"
  if echo "$BODY" | grep -q '"ok":true'; then
    OK_COUNT=$((OK_COUNT+1))
    [ -z "$BOT_NAME" ] && BOT_NAME="$(echo "$BODY" | grep -oE '"username":"[^"]+"' | head -1 | cut -d'"' -f4)"
    grn "  تست $i: موفق   کد=$CODE   زمان=${TIME}s"
  else
    red "  تست $i: ناموفق  کد=${CODE:-000}  زمان=${TIME:-0}s"
  fi
  sleep 1
done

echo "نتیجه تست: $OK_COUNT از 3"
[ -n "$BOT_NAME" ] && echo "ربات پاسخ‌دهنده: @$BOT_NAME"

if [ "$OK_COUNT" -lt 2 ]; then
  red "آدرس جدید از این سرور قابل اعتماد نیست. هیچ تغییری انجام نشد."
  exit 1
fi
grn "مسیر جدید سالم است."

echo
hr; echo " مرحله ۳ — بکاپ Timestampدار"; hr

mkdir -p "$BACKUP_DIR"; chmod 700 "$BACKUP_DIR"
cp -a "$ENV_FILE" "$BACKUP_DIR/.env.bak"; chmod 600 "$BACKUP_DIR/.env.bak"
sha256sum "$BACKUP_DIR/.env.bak" > "$BACKUP_DIR/env.sha256"
systemctl status "$SERVICE" --no-pager -l > "$BACKUP_DIR/service-status-before.txt" 2>&1
sha256sum -c "$BACKUP_DIR/env.sha256" >/dev/null 2>&1 || { red "صحت بکاپ تأیید نشد. عملیات متوقف شد."; exit 1; }
grn "بکاپ گرفته و تأیید شد:"; echo "  $BACKUP_DIR/.env.bak"

echo
hr; echo " مرحله ۴ — تغییر اتمی فایل محیط"; hr

TMP_ENV="$(mktemp)"; cp -a "$ENV_FILE" "$TMP_ENV"
if grep -qE '^TG_API_BASE=' "$TMP_ENV"; then
  sed -i "s|^TG_API_BASE=.*|TG_API_BASE=$NEW_BASE|" "$TMP_ENV"
else
  printf '\nTG_API_BASE=%s\n' "$NEW_BASE" >> "$TMP_ENV"
fi
if grep -qE '^POLL_TIMEOUT_SECONDS=' "$TMP_ENV"; then
  sed -i "s|^POLL_TIMEOUT_SECONDS=.*|POLL_TIMEOUT_SECONDS=$POLL_VALUE|" "$TMP_ENV"
else
  printf 'POLL_TIMEOUT_SECONDS=%s\n' "$POLL_VALUE" >> "$TMP_ENV"
fi
chmod 600 "$TMP_ENV"; mv -f "$TMP_ENV" "$ENV_FILE"; chmod 600 "$ENV_FILE"
grn "فایل محیط به‌روزرسانی شد."
grep -E '^(TG_API_BASE|POLL_TIMEOUT_SECONDS)=' "$ENV_FILE" | sed 's/^/  /'

rollback() {
  red "$1"
  cp -a "$BACKUP_DIR/.env.bak" "$ENV_FILE"; chmod 600 "$ENV_FILE"
  systemctl restart "$SERVICE"; sleep 6
  if systemctl is-active --quiet "$SERVICE"; then
    ylw "بازگشت انجام شد و سرویس فعال است."
  else
    red "بازگشت انجام شد اما سرویس فعال نیست. لاگ را بررسی کن."
  fi
  echo "مسیر بکاپ:"; echo "  $BACKUP_DIR/.env.bak"
  exit 1
}

echo
hr; echo " مرحله ۵ — ری‌استارت کنترل‌شده"; hr

RESTART_TS="$(date '+%Y-%m-%d %H:%M:%S')"
systemctl restart "$SERVICE"
sleep 12
systemctl is-active --quiet "$SERVICE" || rollback "سرویس بالا نیامد. در حال بازگشت..."
grn "سرویس فعال است."

echo
hr; echo " مرحله ۶ — بررسی سلامت بعد از تغییر"; hr

sleep 25
LOG="$(journalctl -u "$SERVICE" --since "$RESTART_TS" --no-pager 2>/dev/null | tail -n 80)"
echo "$LOG" | tail -n 15 | sed -E 's/[0-9]{8,12}:[A-Za-z0-9_-]{30,}/BOT_TOKEN_REDACTED/g' | sed 's/^/  /'

FAILS="$(echo "$LOG" | grep -c 'fetch failed' || true)"
RELAYFAIL="$(echo "$LOG" | grep -c '_relay' || true)"
echo
echo "خطای fetch failed بعد از ری‌استارت : $FAILS"
echo "برچسب خرابی رله در لاگ            : $RELAYFAIL"

[ "$FAILS" -ge 3 ] && rollback "خطاها ادامه دارند. در حال بازگشت خودکار..."

echo
echo "تست نهایی مسیر از بیرون سرویس:"
FINAL="$(timeout 20 curl -s --max-time 18 "$NEW_BASE/bot$TOKEN/getMe" 2>/dev/null | grep -o '"ok":true')"
if [ -n "$FINAL" ]; then grn "  مسیر جدید پاسخ می‌دهد."; else ylw "  تست نهایی پاسخ نداد، لاگ را چند دقیقه زیر نظر بگیر."; fi

echo
hr; grn " نتیجه: تعویض مسیر انجام شد"; hr
echo "آدرس جدید:"; echo "  $NEW_BASE"
echo "مسیر بکاپ:"; echo "  $BACKUP_DIR/.env.bak"
echo
echo "دستور بازگشت دستی:"
echo "  cp $BACKUP_DIR/.env.bak $ENV_FILE && systemctl restart $SERVICE"
echo
echo "حالا در تلگرام /start را بزن و چند دکمه را تست کن."
