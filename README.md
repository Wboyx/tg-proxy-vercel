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
