# AreWarin V15.2.1 — Enrollment / Policy CMS hotfix

## แก้ไขแล้ว

1. `escapeHTML is not defined` ใน Policy CMS
2. `create-enrollment` เปลี่ยน public browser call เป็น CORS-simple POST (`text/plain`) เพื่อไม่บังคับ preflight จาก `functions.invoke()`
3. Edge Function รองรับ `OPTIONS` 204, `GET` health check และ POST ทั้ง `application/json`/`text/plain`
4. `supabase/config.toml` ยืนยัน `verify_jwt = false` สำหรับ `create-enrollment`

## ต้องทำหลังอัปไฟล์ GitHub

```bash
supabase login
supabase link --project-ref ihmiqtwclnqrezsnswfz
supabase functions deploy create-enrollment --no-verify-jwt
```

จากนั้นเปิด:

`https://ihmiqtwclnqrezsnswfz.supabase.co/functions/v1/create-enrollment`

ควรได้ JSON ที่มี `version: v15.2.1-cors`

แล้วอัป GitHub อย่างน้อย 3 ไฟล์:

- `/index.html`
- `/js/supabase-bridge.js`
- `/supabase/functions/create-enrollment/index.ts` (ใช้สำหรับ deploy ไม่ได้ถูกเรียกจาก GitHub Pages โดยตรง)

กด `Ctrl + Shift + R` หลัง GitHub Pages deploy เสร็จ

## Tailwind warning

`cdn.tailwindcss.com should not be used in production` เป็น warning ของ Tailwind CDN และไม่ใช่สาเหตุที่ submit ล้มเหลว ใน hotfix นี้ยังไม่ถอด CDN เพื่อไม่ให้ layout หลักเสียระหว่างแก้ระบบสมัครเรียนแบบเร่งด่วน
