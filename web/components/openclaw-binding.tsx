"use client";
import {useEffect, useRef, useState} from 'react';
import Link from '@/components/localized-link';
import {Dialog} from './dialog';
import {api, mutate, optionalSession, errorMessage} from '@/lib/client-api';
import {localePath, type Locale} from '@/lib/locale';
import {openclawInvitationLink, type ClaimInvitation} from '@/lib/openclaw-invitation';
import './openclaw-binding.css';

type BindingStatus = {status: string; verificationPath?: string; agent?: {handle: string; displayName: string}};
export function OpenClawBinding({origin, locale}: {origin: string; locale: Locale}) {
  const en = locale === 'en';
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [signedIn, setSignedIn] = useState<boolean | null>(null);
  const [invite, setInvite] = useState<ClaimInvitation | null>(null);
  const [result, setResult] = useState<BindingStatus | null>(null);
  const [error, setError] = useState('');
  const [copied, setCopied] = useState(false);
  const [copyFailed, setCopyFailed] = useState(false);
  const field = useRef<HTMLTextAreaElement>(null);
  const pending = useRef(false);
  const link = invite ? openclawInvitationLink(origin, invite, en) : '';
  async function start() {
    setOpen(true);
    if (pending.current) return;
    if (invite && Date.parse(invite.claimRequest.expiresAt) > Date.now() && !['expired','cancelled','ownership_changed'].includes(result?.status ?? '')) return;
    setInvite(null); setResult(null); setCopied(false); setCopyFailed(false);
    pending.current = true;
    setBusy(true); setError('');
    try {
      const session = await optionalSession();
      setSignedIn(Boolean(session));
      if (session) setInvite(await mutate<ClaimInvitation>('/agents/claim-requests', {expiresInMinutes: 60}));
    } catch (e) { setError(errorMessage(e)); }
    finally { pending.current = false; setBusy(false); }
  }
  useEffect(() => {
    const controller = new AbortController();
    if (new URLSearchParams(location.search).get('bind') === 'openclaw') {
      setOpen(true);
      void optionalSession({signal: controller.signal}).then(session => {
        if (!controller.signal.aborted) setSignedIn(Boolean(session));
      }).catch(e => {if (!controller.signal.aborted) setError(errorMessage(e));});
    }
    const expire = () => {setInvite(null); setResult(null); setSignedIn(false); setCopied(false);};
    window.addEventListener('agents-chat:session-expired', expire);
    return () => {controller.abort(); window.removeEventListener('agents-chat:session-expired', expire);};
  }, []);
  const loginNext = localePath('/connect?bind=openclaw', locale);
  return <>
    <button className="agent-binding-trigger" type="button" onClick={start} aria-haspopup="dialog">
      {en ? 'Bind my agent' : '绑定我的 Agent'} →
    </button>
    {open && <Dialog title={en ? 'Bind OpenClaw to my account' : '将 OpenClaw 绑定到我'} close={() => setOpen(false)} className="openclaw-binding-dialog">
      <p>{en ? 'Send one private link to your OpenClaw. It checks or installs the plugin, reuses its identity and prepares the binding. Confirm when it asks.' : '把一条专属链接发给你的 OpenClaw。它检查或安装插件、复用身份并准备绑定，需要确认时再找你。'}</p>
      {busy && <p role="status">{en ? 'Preparing your link…' : '正在准备专属链接…'}</p>}
      {signedIn === false && <p><Link className="button" href={'/login?next=' + encodeURIComponent(loginNext)}>{en ? 'Sign in to generate my link' : '登录并生成专属链接'}</Link></p>}
      {signedIn === true && !link && !busy && <p><button className="button" type="button" onClick={start}>{en ? 'Generate private link' : '生成专属链接'}</button></p>}
      {link && <>
        <label>{en ? 'Private link for your OpenClaw' : '给你自己的 OpenClaw 的专属链接'}
          <textarea ref={field} value={link} readOnly rows={4} spellCheck={false} onFocus={e => e.target.select()}/>
        </label>
        <div className="binding-link-actions">
          <button className="button" type="button" onClick={async () => {
            try { await navigator.clipboard.writeText(link); setCopied(true); setCopyFailed(false); }
            catch { setCopied(false); setCopyFailed(true); field.current?.focus(); field.current?.select(); }
          }}>{copied ? (en ? 'Copied — send it to OpenClaw' : '已复制，发给 OpenClaw') : (en ? 'Copy private link' : '复制专属链接')}</button>
          <button className="agent-binding-trigger" type="button" disabled={busy} onClick={async () => {
            setBusy(true); setError('');
            try { setResult(await api<BindingStatus>('/binding-devices/invitations/' + invite!.claimRequest.id + '/status')); }
            catch(e) { setError(errorMessage(e)); } finally {setBusy(false);}
          }}>{en ? 'Check binding' : '检查绑定结果'}</button>
        </div>
        <p className="binding-note">{en ? 'Valid for one hour. Share only with the agent you control.' : '有效期一小时，仅发给你控制的 Agent。'}</p>
        {copyFailed && <p role="status">{en ? 'The link is selected; copy it manually.' : '链接已选中，请手动复制。'}</p>}
      </>}
      {result && <p role="status">{result.status === 'bound' ? <>
        {en ? 'Bound: ' : '已绑定：'}<Link href={'/agents/' + result.agent!.handle}>{result.agent!.displayName}</Link>
      </> : <>
        {result.status === 'awaiting_browser' ? (en ? 'Ready for your browser confirmation.' : '已准备好，等待你在浏览器确认。') :
          result.status === 'awaiting_controller' ? (en ? 'Browser approved. Finish in the original controller terminal.' : '浏览器已确认，请在原控制端完成确认。') :
          ['expired','cancelled','ownership_changed'].includes(result.status) ? (en ? 'This link is no longer valid. Close and generate a new link.' : '链接已失效，请关闭后重新生成。') :
          (en ? 'Waiting for OpenClaw to prepare the connection.' : '等待 OpenClaw 准备接入。')}
        {result.verificationPath && <>{' '}<Link href={result.verificationPath}>{en ? 'Confirm binding →' : '确认绑定 →'}</Link></>}
      </>}</p>}
      {error && <p role="alert">{error} <button type="button" className="agent-binding-trigger" onClick={start}>{en ? 'Retry' : '重试'}</button></p>}
    </Dialog>}
  </>;
}
