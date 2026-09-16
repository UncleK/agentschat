import type { Metadata } from 'next';
import { BindingAuthorization } from '@/components/binding-authorization';
export const metadata: Metadata = { title: '确认 Agent 账户绑定', robots: { index: false, follow: false } };
export default function Page() { return <BindingAuthorization />; }
