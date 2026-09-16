'use client';
import { useEffect, useState } from 'react';
import { LoaderCircle } from 'lucide-react';
import { GithubIcon } from './github-icon';
import { api, request, errorMessage } from '@/lib/client-api';
import { useI18n } from './locale-provider';
import { localePath } from '@/lib/locale';
export function OAuthButtons({ link = false }: { link?: boolean }) {
  const { t: tx, locale } = useI18n();
  const [providers, setProviders] = useState<{ id: string; enabled: boolean }[] | null>(null);
  const [linked, setLinked] = useState<string[]>([]);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState('');
  const [reload, setReload] = useState(0);
  useEffect(() => {
    const controller = new AbortController();
    const queryError = new URLSearchParams(window.location.search).get('oauthError');
    if (queryError) { setError(queryError); const url = new URL(window.location.href); url.searchParams.delete('oauthError'); window.history.replaceState(null, '', url); }
    void Promise.all([api<{ providers: { id: string; enabled: boolean }[] }>('/auth/oauth/providers', { signal: controller.signal }),
      link ? api<{ identities: { provider: string }[] }>('/auth/oauth/identities', { signal: controller.signal }) : Promise.resolve({ identities: [] })]).then(([p, result]) => {
      if (!controller.signal.aborted) { setProviders(p.providers); setLinked(result.identities.map(i => i.provider)); }
    }).catch(e => { if (!controller.signal.aborted) setError(errorMessage(e)); });
    return () => controller.abort();
  }, [link, reload]);
  async function start(provider: string) {
    setBusy(provider); setError('');
    try {
      const result = await request<{ authorizationUrl: string }>('/api/oauth/start', { method: 'POST', body: JSON.stringify({ provider, link,
        next: link ? window.location.pathname : new URLSearchParams(window.location.search).get('next') || localePath('/hub', locale) }) });
      window.location.assign(result.authorizationUrl);
    } catch (e) { setError(errorMessage(e)); setBusy(''); }
  }
  return <section className={`oauth-options ${link ? 'oauth-options-link' : 'oauth-options-signin'}`} aria-label={tx(link ? '登录方式' : '第三方登录')}>
    <p className="ws-muted">{tx(link ? '登录方式' : '使用已有账号继续')}</p>
    <div className="ws-inline-actions">{['google','github'].map(id => {
      const connected = linked.includes(id), enabled = providers?.find(p => p.id === id)?.enabled;
      const status = !link ? '' : connected ? tx('已绑定') : !providers ? tx('加载中…') : tx(enabled ? '绑定' : '暂未配置');
      return <button key={id} type="button" className={`ws-secondary oauth-provider oauth-provider-${id}`} aria-busy={Boolean(busy) || !providers} disabled={Boolean(busy) || !enabled || connected} onClick={() => void start(id)}>
        {busy === id ? <LoaderCircle size={link ? 17 : 22} className="ws-spin" /> : id === 'github' ? <GithubIcon size={link ? 17 : 22} /> : <svg width={link ? 17 : 22} height={link ? 17 : 22} viewBox="0 0 24 24" aria-hidden="true">
          <path fill="#4285F4" d="M21.6 12.23c0-.71-.06-1.39-.18-2.05H12v3.88h5.38a4.6 4.6 0 0 1-1.99 3.02v2.51h3.23c1.89-1.74 2.98-4.3 2.98-7.36Z" />
          <path fill="#34A853" d="M12 22c2.7 0 4.96-.9 6.62-2.41l-3.23-2.51c-.9.6-2.05.96-3.39.96-2.6 0-4.8-1.76-5.58-4.12H3.08v2.59A10 10 0 0 0 12 22Z" />
          <path fill="#FBBC05" d="M6.42 13.92A6 6 0 0 1 6.11 12c0-.67.11-1.32.31-1.92V7.49H3.08A10 10 0 0 0 2 12c0 1.61.38 3.14 1.08 4.51l3.34-2.59Z" />
          <path fill="#EA4335" d="M12 5.96c1.47 0 2.79.51 3.83 1.51l2.87-2.87A9.6 9.6 0 0 0 12 2a10 10 0 0 0-8.92 5.49l3.34 2.59C7.2 7.72 9.4 5.96 12 5.96Z" />
        </svg>}
        <span className="oauth-provider-label">{link ? id === 'google' ? 'Google' : 'GitHub' : tx(id === 'google' ? '使用 Google 继续' : '使用 GitHub 继续')}</span>
        {status && <span className="oauth-provider-status">{link ? ' · ' : ''}{status}</span>}
      </button>;
    })}</div>
    {error && <p role="alert" className="ws-error">{tx(error)}{!providers && <button type="button" className="ws-text-link" onClick={() => { setError(''); setReload(n => n + 1); }}>{tx('重试')}</button>}</p>}
  </section>;
}
