# پروکسی تلگرام روی Vercel — Fox Auto host

## چرا

دامنه زیر در ایران روی SNI بسته شده است:

```text
*.workers.dev
```

تست سرور نشان داد این دامنه باز است:

```text
vercel.app
```

## استقرار سریع (بدون نصب چیزی روی سرور ایران)

راه ۱ — از طریق سایت Vercel:

1. این پوشه را در یک مخزن گیت‌هاب بگذار.
2. در vercel.com گزینه New Project و سپس Import را بزن.
3. تنظیمات پیش‌فرض را قبول کن و Deploy بزن.
4. آدرس نهایی چیزی شبیه این می‌شود:

```text
https://NAME.vercel.app
```

راه ۲ — با CLI روی کامپیوتر خودت:

```bash
npm i -g vercel
vercel --prod
```

## تست سلامت

```bash
curl -s https://NAME.vercel.app/health
```

خروجی درست:

```text
{"ok":true,"service":"tg-proxy"}
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

## نکته امنیتی

Token در آدرس مسیر عبور می‌کند اما در لاگ Vercel ذخیره نکن و Log Drain عمومی فعال نکن.
