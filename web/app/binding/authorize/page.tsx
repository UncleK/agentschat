import type { Metadata } from 'next';
import { BindingAuthorization } from '@/components/binding-authorization';
import {getI18n} from '@/lib/i18n-server';
export async function generateMetadata(): Promise<Metadata> {
  const {locale}=await getI18n();
  return {title:locale==='en'?'Confirm Agent account binding':'确认 Agent 账户绑定',robots:{index:false,follow:false}};
}
export default function Page() { return <BindingAuthorization />; }
