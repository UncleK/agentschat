async (page) => {
  const fixture='http://127.0.0.1:18081';
  let state;
  for(let i=0;i<300;i++) {
    state=await (await page.request.get(fixture+'/status')).json();
    if(state.device)break;
    await page.waitForTimeout(100);
  }
  if(!state.device)throw new Error('No real CLI device request');
  await page.goto(state.base+'/binding/authorize?code='+state.device.user_code);
  await page.getByRole('link',{name:'登录申请绑定的账户'}).click();
  await page.getByRole('textbox',{name:'邮箱',exact:true}).fill(state.email);
  await page.getByRole('textbox',{name:'密码',exact:true}).fill(state.password);
  // Capture the real BFF body before its successful login navigates away.
  // Forward unchanged; no fixture token or mocked login response is injected.
  let login;
  await page.route('**/api/session',async route=> {
    const response=await route.fetch();
    if(route.request().method()==='POST')login=await response.json();
    await route.fulfill({response});
  });
  await page.getByRole('button',{name:'登录',exact:true}).click();
  await page.getByRole('button',{name:'确认关联此账户，继续到终端批准'}).waitFor();
  if(!login || login.accessToken || login.session?.accessToken)throw new Error('Human bearer leaked to browser response');
  const cookies=await page.context().cookies();
  if(!cookies.some(c=>c.name==='agentschat_session'&&c.httpOnly))throw new Error('Missing HttpOnly session');
  if(await page.evaluate(()=>document.cookie.includes('agentschat_session')))throw new Error('Session readable by JS');
  const before=await (await page.request.get(fixture+'/status')).json();
  if(before.agent.owner_type!=='self')throw new Error('Bound without controller approval');
  await page.getByRole('button',{name:'确认关联此账户，继续到终端批准'}).click();
  await page.getByRole('status').filter({hasText:'浏览器确认已完成'}).waitFor();
  let after;
  for(let i=0;i<300;i++) {
    after=await (await page.request.get(fixture+'/status')).json();
    if(after.device.status==='consumed')break;
    await page.waitForTimeout(100);
  }
  if(after.device.status!=='consumed'||after.agent.id!==state.agentId||after.agent.owner_user_id!==state.accountId||after.historyCount!==1)throw new Error('Identity/history/one-use binding failed');
  return {caseIds:['RR3-01','RR4-01','RR4-02'],browser:'Chromium',actualPythonPty:true,httpOnlySession:true,humanBearerCopied:false,sameAgentId:true,historyPreserved:true,result:'passed'};
}
