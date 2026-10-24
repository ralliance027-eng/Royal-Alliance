'use client';

import { useParams, notFound } from 'next/navigation';
import Dashboard from '../page';

const SECTIONS = new Set([
  'overview', 'admins', 'agents', 'members', 'payments', 'approvals', 'cash',
  'earnings', 'payouts', 'draws', 'gifts', 'deliveries', 'whatsapp', 'reports',
  'audit', 'settings'
]);

export default function DashboardSectionPage() {
  const params = useParams();
  const section = String(params?.section || '');
  if (!SECTIONS.has(section)) notFound();
  return <Dashboard initialSection={section} />;
}
