import { NextRequest, NextResponse } from 'next/server';
import { backend, noStore, origin } from '@/lib/oauth-server';
export async function GET(request: NextRequest, context: { params: Promise<{ provider: string }> }) {
  const { provider } = await context.params;
  try {
    if (!['google','github'].includes(provider)) throw new Error('Unknown provider.');
    const params = new URLSearchParams();
    for (const name of ['state', 'code', 'error']) {
      const value = request.nextUrl.searchParams.get(name);
      if (value) params.set(name, value);
    }
    const result = await backend(`${provider}/callback?${params}`);
    const url = new URL(result.client === 'mobile' ? 'agentschat://oauth' : '/api/oauth/complete', origin(request));
    url.searchParams.set('flow', result.flowId);
    url.searchParams.set('code', result.completionCode);
    return noStore(NextResponse.redirect(url, 303));
  } catch {
    return noStore(NextResponse.json({ message: '登录链接已过期或已使用。请返回登录页或 App，重新选择 Google / GitHub。 Sign-in link expired or was already used. Please return and try again.' }, { status: 400 }));
  }
}
