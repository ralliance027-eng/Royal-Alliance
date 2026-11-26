const configuredOrigins = (Deno.env.get('APP_ALLOWED_ORIGINS') || '')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);

export function isOriginAllowed(req: Request): boolean {
  const origin = req.headers.get('Origin');
  // Non-browser/server-to-server calls do not send Origin and are still protected by JWT.
  if (!origin) return true;
  return configuredOrigins.includes(origin);
}

export function corsHeadersFor(req: Request): Record<string, string> {
  const origin = req.headers.get('Origin');
  const headers: Record<string, string> = {
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  };
  if (origin && configuredOrigins.includes(origin)) {
    headers['Access-Control-Allow-Origin'] = origin;
  }
  return headers;
}
