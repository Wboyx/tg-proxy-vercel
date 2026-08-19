// =====================================================================
// TG Relay v2 — Fox Auto host
// رله امن درخواست‌های Bot API تلگرام
//
// تغییرهای نسخه ۲ نسبت به نسخه ۱:
//   1. پاسخ خالی ساختگی دیگر بی‌صدا نیست و برچسب _relay دارد،
//      پس خرابی مسیر در لاگ ربات دیده می‌شود و پنهان نمی‌ماند.
//   2. یک بار Retry داخلی روی خطای شبکه انجام می‌شود.
//   3. منطقه اجرا به fra1 نزدیک سرورهای تلگرام Pin شده است.
//   4. مسیر /diag تأخیر واقعی رله تا تلگرام را اندازه می‌گیرد.
//   5. سقف long polling از 15 به 12 آمد تا حاشیه امن بیشتری بماند.
//
// این فایل هیچ Tokenی ذخیره نمی‌کند و هیچ لاگی از Token نمی‌سازد.
// =====================================================================

export const config = {
  runtime: "edge",
  regions: ["fra1"]
};

const TG = "https://api.telegram.org";

// سقف امن برای long polling
const MAX_POLL_TIMEOUT = 12;

// سقف کلی هر درخواست
const HARD_TIMEOUT_MS = 20000;

// سقف زمان برای درخواست‌های کوتاه غیر polling
const SHORT_TIMEOUT_MS = 9000;

export default async function handler(req) {
  const url = new URL(req.url);
  const started = Date.now();

  // ---------- مسیر سلامت ----------
  if (url.pathname === "/" || url.pathname === "/health") {
    return json({
      ok: true,
      service: "tg-relay",
      version: 2,
      platform: "vercel",
      maxPollTimeout: MAX_POLL_TIMEOUT
    });
  }

  // ---------- مسیر تشخیص: تأخیر رله تا تلگرام ----------
  if (url.pathname === "/diag") {
    const t0 = Date.now();
    let upstream = "fail";
    let status = 0;
    try {
      const r = await fetchWithTimeout(TG + "/", { method: "GET" }, 6000);
      status = r.status;
      upstream = "ok";
    } catch (e) {
      upstream = String(e && e.name ? e.name : "error");
    }
    return json({
      ok: true,
      upstream,
      upstreamStatus: status,
      relayToTelegramMs: Date.now() - t0,
      totalMs: Date.now() - started
    });
  }

  // ---------- فقط مسیرهای Bot API ----------
  if (!url.pathname.startsWith("/bot")) {
    return json({ ok: false, error: "path not allowed" }, 403);
  }

  const isPoll = url.pathname.includes("/getUpdates");
  const params = new URLSearchParams(url.search);

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

  let body;
  if (req.method !== "GET" && req.method !== "HEAD") {
    body = await req.arrayBuffer();

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
  }

  const budget = isPoll ? HARD_TIMEOUT_MS : SHORT_TIMEOUT_MS;

  // تلاش اول، و در صورت خطای شبکه یک تلاش دوم فقط برای درخواست‌های کوتاه.
  // برای getUpdates تلاش دوم انجام نمی‌شود چون خود ربات دور بعدی را می‌زند
  // و تکرار باعث دریافت دوباره آپدیت‌ها می‌شود.
  const attempts = isPoll ? 1 : 2;
  let lastError = "unknown";

  for (let i = 0; i < attempts; i++) {
    try {
      const init = { method: req.method, headers };
      if (body !== undefined) init.body = body;

      const res = await fetchWithTimeout(target, init, budget);

      // بدنه به‌صورت کامل خوانده می‌شود تا پاسخ نیمه‌کاره به ربات نرسد
      const buf = await res.arrayBuffer();

      const out = new Headers();
      out.set("content-type", res.headers.get("content-type") || "application/json");
      out.set("cache-control", "no-store");
      out.set("x-relay-ms", String(Date.now() - started));
      out.set("x-relay-try", String(i + 1));

      return new Response(buf, { status: res.status, headers: out });
    } catch (e) {
      lastError = String(e && e.name ? e.name : "error");
      if (i < attempts - 1) await sleep(300);
    }
  }

  // مسیر شکست
  if (isPoll) {
    // پاسخ معتبر ولی برچسب‌دار، تا ربات کرش نکند و خرابی هم پنهان نماند
    return json({
      ok: true,
      result: [],
      _relay: "upstream-failed",
      _error: lastError,
      _ms: Date.now() - started
    });
  }

  return json(
    { ok: false, error: "upstream unreachable", _relay: "upstream-failed", _error: lastError },
    502
  );
}

async function fetchWithTimeout(target, init, ms) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), ms);
  try {
    return await fetch(target, { ...init, signal: ctrl.signal });
  } finally {
    clearTimeout(timer);
  }
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" }
  });
}
