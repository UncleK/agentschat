// Isolated browser/CLI acceptance harness, never loaded by the application.
const {randomUUID}=require('node:crypto');
const {mkdirSync,readFileSync,writeFileSync}=require('node:fs');
const {resolve}=require('node:path');
const {Client}=require('pg');
const {DataSource}=require('typeorm');
const {NestFactory}=require('@nestjs/core');
const http=require('node:http');
const root=resolve(__dirname,'../../../output',process.env.REAUDIT_RUN_NAME || 'reaudit');
if(!root.startsWith(resolve(__dirname,'../../../output')+require('node:path').sep))throw new Error('Fixture state must remain under workspace output');
mkdirSync(root,{recursive:true});
const dbName=`agents_chat_reaudit_${randomUUID().replaceAll('-','')}`;
const source=new URL(process.env.DATABASE_URL || 'postgres://agents_chat:agents_chat@127.0.0.1:15432/agents_chat');
if (!['127.0.0.1','localhost'].includes(source.hostname)) throw new Error('Fixture requires an isolated loopback PostgreSQL.');
const adminUrl=new URL(source); adminUrl.pathname='/postgres';
source.pathname='/'+dbName;
Object.assign(process.env,{NODE_ENV:'test',DATABASE_URL:source.toString(),JWT_SECRET:'reaudit-synthetic-secret',OPERATOR_TOKEN:'reaudit-synthetic-operator',AGENT_CANT_SECRET:'reaudit-synthetic-cant',MAIL_DELIVERY_MODE:'log',MAIL_RESEND_API_KEY:'',API_PREFIX:'api/v1',MINIO_ENDPOINT:'127.0.0.1',MINIO_PORT:process.env.MINIO_PORT||'19000',MINIO_ACCESS_KEY:'minioadmin',MINIO_SECRET_KEY:'minioadmin',MINIO_BUCKET:'reaudit-fixture',REDIS_URL:'redis://127.0.0.1:6379'});
const base='http://127.0.0.1:18100';
let app,fixture,admin;
let prepared;
async function json(path,body,token) {
  const r=await fetch('http://127.0.0.1:18080/api/v1'+path,{method:body===undefined?'GET':'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},body:body===undefined?undefined:JSON.stringify(body)});
  const data=await r.json(); if(!r.ok) throw new Error(`${path}: ${r.status} ${JSON.stringify(data)}`); return data;
}
async function prepare() {
  if(prepared) return prepared;
  const state=JSON.parse(readFileSync(resolve(root,'python/state.json'),'utf8'));
  const db=app.get(DataSource);
  const [users]=await db.query('SELECT count(*) AS count FROM users');
  if(Number(users.count)!==0)throw new Error('Public participation must precede human registration');
  const history=await db.query('SELECT id FROM events WHERE actor_agent_id=$1 AND content=$2',[state.agentId,'Synthetic history before human registration']);
  if(history.length!==1)throw new Error('The actual Python process must publish its synthetic history before registration');
  const email=`browser-${randomUUID().slice(0,8)}@example.test`,password='Synthetic-password-123';
  const human=await json('/auth/register/email',{email,password,username:'rr_'+randomUUID().slice(0,8),displayName:'Synthetic Browser Owner'});
  const binding=await json('/agents/claim-requests',{},human.accessToken);
  const query=new URLSearchParams({mode:'claim',serverBaseUrl:base,slot:'rr12',agentId:state.agentId,claimRequestId:binding.claimRequest.id,challengeToken:binding.challengeToken});
  writeFileSync(resolve(root,'launcher.txt'),'agents-chat://launch?'+query,{mode:0o600});
  prepared={base,email,password,agentId:state.agentId,accountId:human.user.id,requestId:binding.claimRequest.id};
  return prepared;
}
(async()=> {
  admin=new Client({connectionString:adminUrl.toString()});await admin.connect();await admin.query(`CREATE DATABASE "${dbName}"`);
  const {buildDataSourceOptions}=require('../../dist/src/database/typeorm.config');
  const migration=new DataSource(buildDataSourceOptions(source.toString(),'test'));await migration.initialize();await migration.runMigrations();await migration.destroy();
  const {AppModule}=require('../../dist/src/app.module');
  app=await NestFactory.create(AppModule,{logger:false});app.setGlobalPrefix('api/v1');await app.listen(18080,'127.0.0.1');
  fixture=http.createServer(async(req,res)=> {
    try {
      let result;
      if(req.url==='/prepare' && req.method==='POST') result=await prepare();
      else if(req.url==='/status') {
        const db=app.get(DataSource);
        const devices=prepared?await db.query('SELECT user_code,status FROM binding_devices WHERE request_id=$1 ORDER BY created_at DESC LIMIT 1',[prepared.requestId]):[];
        const agents=prepared?await db.query('SELECT id,owner_type,owner_user_id FROM agents WHERE id=$1',[prepared.agentId]):[];
        const events=prepared?await db.query('SELECT id FROM events WHERE actor_agent_id=$1 AND content=$2',[prepared.agentId,'Synthetic history before human registration']):[];
        result={...prepared,device:devices[0],agent:agents[0],historyCount:events.length};
      } else if(req.url==='/stop' && req.method==='POST') {res.end('stopping');await app.close();fixture.close();await admin.query(`DROP DATABASE "${dbName}" WITH (FORCE)`);await admin.end();return;}
      else {res.writeHead(404);res.end();return;}
      res.setHeader('Content-Type','application/json');res.end(JSON.stringify(result));
    } catch(e) {console.error('Synthetic fixture request failed',e);res.writeHead(500);res.end('Synthetic fixture request failed');}
  }).listen(18081,'127.0.0.1');
  console.log('REAUDIT_FIXTURE_READY isolated database='+dbName);
})().catch(e=>{console.error(e);process.exit(1);});
