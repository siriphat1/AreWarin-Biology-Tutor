# AreWarin Student Experience V15.4

## What changed
- Full visual refresh based on the main enrollment theme: Prompt, sky/indigo, slate, glass surfaces, compact typography.
- Removed the Library entry and every floating purple launcher.
- Installment/payment plan is now opened from the main Payment Center, not a floating button.
- New dashboard experience with greeting, live status metrics, quick actions, renewal alerts, and current course continuation.
- New Course Center combines **ต่อคอร์สเดิม** and **สมัครคอร์สเพิ่ม** in one page.
- Existing course cards now include a direct **ต่อคอร์ส** action.
- Renewal/new enrollment requests continue using `student_v8_request_enrollment` and then hand off to the main enrollment flow with the existing student context.
- Existing auth, quick-hour check, group locker, attendance, learning, payments, notifications, profile, realtime and Supabase contracts are preserved.

## Deploy
Upload these two files to GitHub Pages:
- `/student/index.html`
- `/student/theme-v15.4.css`

No SQL migration is required for this UI release. Existing `student-auth` must remain deployed with Verify JWT OFF.
