// =====================================================================
// TG Proxy for Vercel — Fox Auto host
// رله امن درخواست‌های Bot API تلگرام
//
// چرا لازم شد:
//   دامنه workers.dev در ایران روی SNI بسته شد و سرور نتوانست TLS بدهد.
//   دامنه vercel.app در تست همان سرور باز بود.
//
// نکته مهم درباره long polling:
//   Vercel روی پلن رایگان درخواست طولانی را قطع می‌کند.
//   بنابراین پارامتر timeout در getUpdates در همین‌جا سقف‌گذاری می‌شود
//   تا اتصال قبل از قطع‌شدن توسط Vercel بسته شود و ربات خطا نگیرد.
// =====================================================================

export const config = { runtime: "edge" };

const TG = "https://api.telegram.org";

// سقف امن برای long polling روی Vercel
const MAX_POLL_TIMEOUT = 15;

// سقف کلی هر درخواست
const HARD_TIMEOUT_MS = 20000;

export default async function handler(req) {
  const url = new URL(req.url);

  // مسیر سلامت — بدون تماس با تلگرام
  if (url.pathname === "/" || url.pathname === "/health") {
    return json({
      ok: true,
      service: "tg-proxy",
      platform: "vercel",
      maxPollTimeout: MAX_POLL_TIMEOUT
    });
  }

  // فقط مسیرهای Bot API اجازه عبور دارند
  if (!url.pathname.startsWith("/bot")) {
    return json({ ok: false, error: "path not allowed" }, 403);
  }

  const params = new URLSearchParams(url.search);

  // مهار تایم‌اوت long polling
  if (params.has("timeout")) {
    const t = parseInt(params.get("timeout") || "0", 10);
    if (!Number.isFinite(t) || t > MAX_POLL_TIMEOUT) {
      params.set("timeout", String(MAX_POLL_TIMEOUT));
    }
  }

  const qs = params.toString();
  const target = TG + url.pathname + (qs ? "?" + qs : "");

  const headers = new Headers();
  const ct = req.headers.get("content-type");
  if (ct) headers.set("content-type", ct);
  headers.set("accept", "application/json");

  const init = { method: req.method, headers };

  if (req.method !== "GET" && req.method !== "HEAD") {
    let body = await req.arrayBuffer();

    // اگر بدنه JSON بود و timeout داشت، آن را هم سقف‌گذاری کن
    if (ct && ct.includes("application/json") && body.byteLength > 0) {
      try {
        const obj = JSON.parse(new TextDecoder().decode(body));
        if (typeof obj.timeout === "number" && obj.timeout > MAX_POLL_TIMEOUT) {
          obj.timeout = MAX_POLL_TIMEOUT;
          body = new TextEncoder().encode(JSON.stringify(obj)).buffer;
        }
      } catch {
        // بدنه JSON معتبر نبود — دست‌نخورده رد می‌شود
      }
    }
    init.body = body;
  }

  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), HARD_TIMEOUT_MS);
  init.signal = ctrl.signal;

  try {
    const res = await fetch(target, init);
    clearTimeout(timer);

    const out = new Headers();
    out.set("content-type", res.headers.get("content-type") || "application/json");
    out.set("cache-control", "no-store");

    return new Response(res.body, { status: res.status, headers: out });
  } catch (e) {
    clearTimeout(timer);

    // شبیه‌سازی پاسخ خالی تلگرام تا ربات کرش نکند و فقط دور بعد را بزند
    if (url.pathname.includes("/getUpdates")) {
      return json({ ok: true, result: [] });
    }
    return json({ ok: false, error: "upstream unreachable" }, 502);
  }
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" }
  });
}
