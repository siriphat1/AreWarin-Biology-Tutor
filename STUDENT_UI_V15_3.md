# AreWarin Student Portal V15.3

UI redesign aligned with the main AreWarin Biology enrollment website.

## What changed
- Prompt typography and the same Sky / Indigo / Purple visual language as the main enrollment flow.
- Main-site patterned pastel background and glass-card treatment.
- Rebuilt login / signup / quick-hours visual experience.
- New dark navy unified sidebar and compact mobile bottom navigation.
- New dashboard metrics, digital student card, course cards, progress, attendance, payment, profile, modal, and installment-payment styling.
- Responsive redesign for desktop, tablet, and mobile.
- Existing IDs, data attributes, RPC calls, Supabase Auth, Group Locker, Hour Ledger, Realtime, course enrollment, payments, and student-auth behavior are preserved.

## Deploy
Replace `/student/index.html` and add `/student/theme-v15.3.css`.

No SQL migration or Edge Function redeploy is required for this UI-only update. Keep the currently working `student-auth` Edge Function.
