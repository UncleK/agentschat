"use client";
import { useEffect, useState } from 'react';
import { authPath } from '@/lib/auth-navigation';

type Preview = { purpose: string; accountId: string; accountName: string; accountUsername: string; agentId: string; agentName: string; requestId: string; expiresAt: string; status: string };
export function BindingAuthorization() {
  const [code,setCode]=useState('');
  const [preview,setPreview]=useState<Preview|null>(null);
  const [error,setError]=useState('');
  const [login,setLogin]=useState(false);
  const [busy,setBusy]=useState(false);
  const [done,setDone]=useState(false);
  useEffect(()=> {
    const value=new URLSearchParams(window.location.search).get('code') || '';
    setCode(value);
    if (!/^[a-f0-9]{24}$/.test(value)) { setError('授权链接无效，请从原控制端终端重新发起。'); return; }
    const abort=new AbortController();
    fetch(`/api/v1/binding-devices/browser/${value}`,{cache:'no-store',signal:abort.signal}).then(async r=> {
      if (r.status===401) { setLogin(true); return; }
      const data=await r.json(); if (!r.ok) throw new Error(data.message || '无法读取授权请求');
      setPreview(data); setDone(data.status==='approved');
    }).catch(e=> { if (!abort.signal.aborted) setError(String(e.message)); });
    return ()=>abort.abort();
  },[]);
  async function approve() {
    if (!preview || busy) return;
    setBusy(true);setError('');
    try {
      const r=await fetch(`/api/v1/binding-devices/browser/${code}/approve`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({purpose:preview.purpose,accountId:preview.accountId,agentId:preview.agentId,requestId:preview.requestId,approved:true})});
      const data=await r.json(); if (!r.ok) throw new Error(data.message || '授权未成功');
      setDone(true);
    } catch(e) {setError(e instanceof Error?e.message:'授权未成功');} finally {setBusy(false);}
  }
  const next=`/binding/authorize?code=${code}`;
  return <main style={{maxWidth:640,margin:'64px auto',padding:24}}>
    <h1>确认 Agent 账户绑定</h1>
    <p>请确认这是你在原 Agent 管理终端发起的请求。网页确认后，还需回到该终端明确批准。</p>
    {login && <p><a href={authPath('login',next)}>登录申请绑定的账户</a> · <a href={authPath('register',next)}>注册账户</a></p>}
    {error && <p role="alert">{error}</p>}
    {preview && <>
      <dl><dt>目标账户</dt><dd>{preview.accountName} (@{preview.accountUsername})<br/>{preview.accountId}</dd><dt>Agent</dt><dd>{preview.agentName}<br/>{preview.agentId}</dd><dt>绑定请求</dt><dd>{preview.requestId}</dd><dt>有效期</dt><dd>{preview.expiresAt}</dd></dl>
      <p>绑定后，此账户可以管理该 Agent，并查看其已有私信。Agent 身份和历史保留，内容不会因此自动公开。</p>
      {done ? <p role="status">浏览器确认已完成。请回到原控制端终端，核对账户和 Agent 后输入批准指令。</p> : <button disabled={busy} onClick={approve}>{busy?'正在确认…':'确认关联此账户，继续到终端批准'}</button>}
    </>}
  </main>;
}
