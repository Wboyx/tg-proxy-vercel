# TG Proxy — Fox Auto host

رله Bot API تلگرام روی Vercel.

## استقرار یک‌کلیکی

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https://github.com/Wboyx/tg-proxy-vercel)

## چرا این پروژه ساخته شد

دامنه زیر در ایران روی SNI بسته شد:

```text
*.workers.dev
```

تست از روی سرور ایران نشان داد این دامنه هنوز باز است:

```text
vercel.app
```

## تست سلامت

```bash
curl -s https://NAME.vercel.app/health
```

خروجی درست:

```text
{"ok":true,"service":"tg-proxy","platform":"vercel","maxPollTimeout":15}
```

## اتصال به ربات

در فایل محیط ربات فقط این خط عوض می‌شود:

```text
TG_API_BASE=https://NAME.vercel.app
```

سپس:

```bash
systemctl restart foxteam-bot
```

## نکته درباره long polling

Vercel درخواست طولانی را قطع می‌کند. این پروکسی پارامتر timeout را روی 15 ثانیه سقف‌گذاری می‌کند و اگر Upstream قطع شد، پاسخ خالی معتبر برمی‌گرداند تا ربات کرش نکند.

مقدار پیشنهادی در فایل محیط ربات:

```text
POLL_TIMEOUT_SECONDS=15
```

## امنیت

- فقط مسیرهای /bot عبور می‌کنند.
- هیچ Tokenی در کد ذخیره نمی‌شود.
- Log Drain عمومی فعال نکن.

---

## نسخه ۲ — درس حادثه 2026-08-19

آدرس زیر روی SNI سوخت و از سرور ایران TLS نمی‌داد:

```text
tg-proxy-vercel-one.vercel.app
```

اما تست نشان داد کل دامنه سالم است و فقط همان Hostname بسته شده بود:

```text
fox-brain.vercel.app -> code 307 OPEN
```

درس: وقتی یک نام سوخت، لازم نیست پلتفرم عوض شود. کافی است همین مخزن با نام تازه و خنثی دوباره Deploy شود.

نام خوب انتخاب نکن مثل این‌ها:

```text
tg-proxy
telegram-relay
vpn-bridge
```

نام خنثی انتخاب کن مثل این:

```text
mehti-gw-4821
```

## مسیر تشخیص جدید

```bash
curl -s https://NAME.vercel.app/diag
```

خروجی، تأخیر واقعی رله تا تلگرام را نشان می‌دهد:

```text
{"ok":true,"upstream":"ok","relayToTelegramMs":120,"totalMs":130}
```

## برچسب خرابی

اگر مسیر رله به تلگرام قطع شود، پاسخ getUpdates این شکل می‌شود:

```text
{"ok":true,"result":[],"_relay":"upstream-failed"}
```

ربات کرش نمی‌کند، ولی خرابی دیگر پنهان نمی‌ماند.
