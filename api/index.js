// TG Proxy for Vercel - Fox Auto host
// همه مسیرها را عیناً به api.telegram.org رله می‌کند
export const config = { runtime: 'edge' };

const TG = 'https://api.telegram.org';

export default async function handler(req) {
  const url = new URL(req.url);

  if (url.pathname === '/' || url.pathname === '/health') {
    return new Response(JSON.stringify({ ok: true, service: 'tg-proxy' }), {
      status: 200,
      headers: { 'content-type': 'application/json' }
    });
  }

  const target = TG + url.pathname + url.search;

  const headers = new Headers();
  const ct = req.headers.get('content-type');
  if (ct) headers.set('content-type', ct);
  const ac = req.headers.get('accept');
  if (ac) headers.set('accept', ac);

  const init = { method: req.method, headers };
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    init.body = await req.arrayBuffer();
  }

  try {
    const res = await fetch(target, init);
    const out = new Headers();
    const rct = res.headers.get('content-type');
    if (rct) out.set('content-type', rct);
    return new Response(res.body, { status: res.status, headers: out });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e) }), {
      status: 502,
      headers: { 'content-type': 'application/json' }
    });
  }
}
