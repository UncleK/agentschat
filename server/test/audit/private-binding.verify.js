async (page) => {
  const base = 'http://127.0.0.1:18100';
  const context = await page.context().browser().newContext();
  await context.grantPermissions(['clipboard-read','clipboard-write'],{origin:base});
  const p = await context.newPage();
  const errors = []; p.on('pageerror',e=>errors.push(e.message));
  const post = async(path,data,token)=>{
    const response=await p.request.post(base+'/api/v1'+path,{headers:{Origin:base,...token?{Authorization:'Bearer '+token}:{}},data});
    if(!response.ok()) throw new Error(path+' '+response.status()+': '+await response.text());
    return response.json();
  };
  try {
    for(const path of ['/connect','/en/connect']) {
      await context.clearCookies();await p.goto(base+path,{waitUntil:'networkidle'});
      await p.getByRole('button',{name:path.startsWith('/en')?'Bind my agent →':'绑定我的 Agent →',exact:true}).click();
      await p.getByRole('link',{name:path.startsWith('/en')?'Sign in to generate my link':'登录并生成专属链接'}).waitFor();
      await p.getByRole('button',{name:path.startsWith('/en')?'Close':'关闭',exact:true}).click();
    }
    const suffix=Date.now().toString(36);
    const registration=await p.request.post(base+'/api/session',{headers:{Origin:base},data:{action:'register',email:'binding-'+suffix+'@example.test',password:'password123',username:'binding_'+suffix,displayName:'Binding Owner'}});
    if(!registration.ok())throw new Error(await registration.text());
    const owner=(await registration.json()).user;
    const cookies=await context.cookies();if(!cookies.some(c=>c.name==='agentschat_session'&&c.httpOnly))throw new Error('No protected session');
    for(const path of ['/connect','/en/connect']) {
      await context.clearCookies();await p.goto(base+path,{waitUntil:'networkidle'});
      await p.getByRole('button',{name:path.startsWith('/en')?'Bind my agent →':'绑定我的 Agent →',exact:true}).click();
      await p.getByRole('link',{name:path.startsWith('/en')?'Sign in to generate my link':'登录并生成专属链接'}).click();
      await p.locator('input[name=email]').fill('binding-'+suffix+'@example.test');
      await p.locator('input[name=password]').fill('password123');
      await p.locator('.auth-submit').click();
      await p.waitForURL(base+path+'?bind=openclaw');
      await p.getByRole('button',{name:path.startsWith('/en')?'Generate private link':'生成专属链接',exact:true}).waitFor();
      await p.getByRole('button',{name:path.startsWith('/en')?'Close':'关闭',exact:true}).click();
    }
    await p.setViewportSize({width:390,height:844});await p.goto(base+'/en/connect',{waitUntil:'networkidle'});
    await p.getByRole('button',{name:'Bind my agent →',exact:true}).click();
    const field=p.getByRole('dialog').getByRole('textbox');await field.waitFor();
    const link=await field.inputValue();const invitation=JSON.parse(Buffer.from(new URLSearchParams(new URL(link).hash.slice(1)).get('invite'),'base64url').toString('utf8'));
    if(new URL(link).search||!new URL(link).pathname.endsWith('/openclaw'))throw new Error('Wrong private link');
    await p.getByRole('button',{name:'Copy private link',exact:true}).click();
    if(await p.evaluate(()=>navigator.clipboard.readText())!==link)throw new Error('Clipboard mismatch');
    if(await p.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1))throw new Error('Mobile overflow');
    await field.evaluate(el=>el.value='[private invitation redacted]');
    if(await field.evaluate(el=>el.getBoundingClientRect().height)>130)throw new Error('Private link field is oversized on mobile');
    await p.screenshot({path:'output/reaudit/private-binding-mobile.png'});
    const boot=await post('/agents/bootstrap/public',{handle:'private-'+suffix,displayName:'Private Invitation Agent'});
    const connected=await post('/agents/claim',{claimToken:boot.bootstrap.claimToken,pollingEnabled:true});
    await post('/binding-devices/invitations/'+invitation.requestId+'/preview',{challengeToken:invitation.challengeToken},connected.accessToken);
    const device=await post('/binding-devices',{requestId:invitation.requestId,challengeToken:invitation.challengeToken},connected.accessToken);
    await p.getByRole('button',{name:'Check binding',exact:true}).click();
    await p.getByRole('status').filter({hasText:'Ready for your browser confirmation.'}).waitFor();
    await p.goto(base+'/en'+device.verificationPath,{waitUntil:'networkidle'});
    await p.getByRole('button',{name:'Confirm this account, then approve in the terminal'}).click();
    await p.getByRole('status').filter({hasText:'Browser approval is complete.'}).waitFor();
    const pending=await (await p.request.get(base+'/api/v1/binding-devices/invitations/'+invitation.requestId+'/status')).json();
    if(pending.status!=='awaiting_controller')throw new Error('Browser approval incorrectly became binding success');
    await post('/binding-devices/'+device.id+'/confirm',{deviceSecret:device.deviceSecret,challengeToken:invitation.challengeToken,authorization:{purpose:'bind_account',accountId:owner.id,agentId:connected.agent.id,requestId:invitation.requestId,approved:true}},connected.accessToken);
    const bound=await (await p.request.get(base+'/api/v1/binding-devices/invitations/'+invitation.requestId+'/status')).json();
    if(bound.status!=='bound'||bound.agent.id!==connected.agent.id)throw new Error('Persisted ownership not verified');
    if(!(await p.request.get(base+'/agents/'+bound.agent.handle)).ok())throw new Error('Profile not public');
    await p.goto(base+'/en/connect?bind=openclaw',{waitUntil:'networkidle'});
    await p.getByRole('button',{name:'Generate private link',exact:true}).waitFor();
    if(errors.length)throw new Error(errors.join('\n'));
    return {result:'passed',guestLocales:['zh','en'],loginReturnLocales:['zh','en'],httpOnlySession:true,privateLinkCopied:true,fragmentOnly:true,mobileOverflow:false,browserApprovalAloneBound:false,sameIdentity:true,persistedOwnership:true,pageErrors:0};
  } finally {await context.close();}
}
