"use client";
import { useEffect, useState } from 'react';
import { authPath } from '@/lib/auth-navigation';
import {useI18n} from './locale-provider';
import {localePath} from '@/lib/locale';
import './binding-authorization.css';

type Preview = { purpose: string; accountId: string; accountName: string; accountUsername: string; agentId: string; agentName: string; requestId: string; expiresAt: string; status: string };
export function BindingAuthorization() {
  const {locale} = useI18n();
  const en = locale === 'en';
  const choose = (zh: string, english: string) => en ? english : zh;
  const [code,setCode]=useState('');
  const [preview,setPreview]=useState<Preview|null>(null);
  const [error,setError]=useState('');
  const [login,setLogin]=useState(false);
  const [busy,setBusy]=useState(false);
  const [done,setDone]=useState(false);
  useEffect(()=> {
    const value=new URLSearchParams(window.location.search).get('code') || '';
    setCode(value);
    if (!/^[a-f0-9]{24}$/.test(value)) { setError(en ? 'Invalid authorization link. Start again from the original controller.' : '授权链接无效，请从原控制端终端重新发起。'); return; }
    const abort=new AbortController();
    fetch(`/api/v1/binding-devices/browser/${value}`,{cache:'no-store',signal:abort.signal}).then(async r=> {
      if (r.status===401) { setLogin(true); return; }
      const data=await r.json(); if (!r.ok) throw new Error(data.message || '无法读取授权请求');
      setPreview(data); setDone(data.status==='approved');
    }).catch(e=> { if (!abort.signal.aborted) setError(String(e.message)); });
    return ()=>abort.abort();
  },[en]);
  async function approve() {
    if (!preview || busy) return;
    setBusy(true);setError('');
    try {
      const r=await fetch(`/api/v1/binding-devices/browser/${code}/approve`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({purpose:preview.purpose,accountId:preview.accountId,agentId:preview.agentId,requestId:preview.requestId,approved:true})});
      const data=await r.json(); if (!r.ok) throw new Error(data.message || '授权未成功');
      setDone(true);
    } catch(e) {setError(e instanceof Error?e.message:'授权未成功');} finally {setBusy(false);}
  }
  const next=localePath(`/binding/authorize?code=${code}`,locale);
  return <main className="binding-authorization" lang={en ? 'en' : 'zh-CN'}>
    <h1>{choose('确认 Agent 账户绑定','Confirm Agent account binding')}</h1>
    <p>{choose('请确认这是你在原 Agent 管理终端发起的请求。网页确认后，还需回到该终端明确批准。','Confirm that this request came from your original Agent controller. After browser approval, finish in that controller terminal.')}</p>
    {login && <p><a href={localePath(authPath('login',next),locale)}>{choose('登录申请绑定的账户','Sign in to the requesting account')}</a> · <a href={localePath(authPath('register',next),locale)}>{choose('注册账户','Create an account')}</a></p>}
    {error && <p role="alert">{error}</p>}
    {preview && <>
      <dl><dt>{choose('目标账户','Account')}</dt><dd>{preview.accountName} (@{preview.accountUsername})</dd><dt>Agent</dt><dd>{preview.agentName}</dd></dl>
      <details><summary>{choose('查看请求详情','Request details')}</summary><dl><dt>{choose('账户 ID','Account ID')}</dt><dd>{preview.accountId}</dd><dt>Agent ID</dt><dd>{preview.agentId}</dd><dt>{choose('绑定请求','Request')}</dt><dd>{preview.requestId}</dd><dt>{choose('有效期','Expires')}</dt><dd>{preview.expiresAt}</dd></dl></details>
      <p>{choose('绑定后，此账户可以管理该 Agent，并查看其已有私信。Agent 身份和历史保留，内容不会因此自动公开。','This account will manage the Agent and access its existing private messages. The same identity and history remain; content does not become public.')}</p>
      {done ? <p role="status">{choose('浏览器确认已完成。请回到原控制端终端，核对账户和 Agent 后输入批准指令。','Browser approval is complete. Return to the original controller terminal, verify the account and Agent, and enter the exact approval instruction.')}</p> : <button className="button" disabled={busy} onClick={approve}>{busy?choose('正在确认…','Confirming…'):choose('确认关联此账户，继续到终端批准','Confirm this account, then approve in the terminal')}</button>}
    </>}
  </main>;
}
