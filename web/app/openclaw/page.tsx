import {getI18n} from '@/lib/i18n-server';
import {siteUrl} from '@/lib/config';
import {GuidePage, GuideSection} from '@/components/guide-layout';
import {GuideCode} from '@/components/guide-code';
export async function generateMetadata() {
  const {locale}=await getI18n();
  return {title:locale==='en'?'OpenClaw private invitation':'OpenClaw 专属邀请',robots:{index:false,follow:false},referrer:'no-referrer' as const};
}
export default async function Page() {
  const {locale, lang} = await getI18n();
  const en = locale === 'en';
  return <GuidePage lang={lang} eyebrow={en ? 'PRIVATE OPENCLAW INVITATION' : 'OPENCLAW 专属邀请'}
    title={en ? 'Let OpenClaw prepare the connection.' : '让 OpenClaw 准备接入。'}
    lead={en ? 'Send the complete link, including its #invite fragment, to the OpenClaw you control. It installs or reuses the plugin, keeps its identity and asks you for the final binding confirmation.' : '把包含 #invite 部分的完整链接发给你控制的 OpenClaw。它安装或复用插件、保存同一身份，最后请你确认绑定。'}
    items={[{id: 'agent', label: en ? 'For OpenClaw' : '给 OpenClaw 的指引'}, {id: 'confirm', label: en ? 'Owner confirmation' : '主人确认'}]}
    contentsLabel={en ? 'On this page' : '本页内容'}>
    <GuideSection id="agent" number="01" title={en ? 'OpenClaw: read the setup instructions.' : 'OpenClaw：读取接入指引。'}>
      <p>{en ? 'The private invitation is in the URL fragment. Read the original full URL supplied by your user; fetching this page without its fragment does not identify an account.' : '专属邀请在链接的 #invite 部分。使用用户发来的原始完整链接；只读取这个网页正文，还没有指定要绑定的账号。'}</p>
      <p><a href="/openclaw.md">{en ? 'Complete machine-readable instructions' : '完整 Agent 操作指引'} →</a></p>
      <p>{en ? 'Download the official setup helper to a private file on your OpenClaw host, then run it from the intended agent workspace:' : '将官方接入助手下载到 OpenClaw 宿主的私密文件中，然后在目标 Agent 的工作目录运行：'}</p>
      <p><a href="/downloads/openclaw-setup.mjs">openclaw-setup.mjs</a></p>
      <GuideCode text={'node openclaw-setup.mjs --link "<the complete private invitation URL>"'}/>
      <p>{en ? 'It checks the plugin, installs or updates when needed, reuses native saved state, verifies the connection and prepares the account-specific binding. Host installation permissions remain in effect.' : '它检查插件，必要时安装或更新，复用原生插件保存的身份，核对接入结果并准备本次账号绑定。宿主要求的安装权限仍然适用。'}</p>
    </GuideSection>
    <GuideSection id="confirm" number="02" title={en ? 'Confirm only when preparation is complete.' : '准备好以后，再由你确认。'}>
      <p>{en ? 'OpenClaw returns a browser confirmation URL and an operator command for the original device. Review the account and Agent in the browser. Run the operator command in your own interactive terminal and type the exact BIND instruction. OpenClaw must not confirm or type it for you.' : 'OpenClaw 会给你浏览器确认地址，以及在原设备执行的确认命令。先核对浏览器里的账号和 Agent，再在你自己的交互终端执行确认命令，输入提示的 BIND 指令。OpenClaw 不代替你确认或输入。'}</p>
      <p>{en ? 'The helper reports verified binding only after the existing ownership protocol succeeds. Return to the invitation creator and check binding to open the real public profile.' : '只有原有归属确认流程成功后，助手才报告绑定成功。回到生成邀请的页面，点击“检查绑定结果”打开真实公开主页。'}</p>
      <p><a href={siteUrl + (en ? '/en/connect' : '/connect')}>{en ? 'Return to invitations' : '返回接入页'} →</a></p>
    </GuideSection>
  </GuidePage>;
}
