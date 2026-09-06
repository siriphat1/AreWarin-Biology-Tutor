# AreWarin Enrollment Rescue V15.2.3

ใช้เมื่อหน้า Public Enrollment เรียก `create-enrollment` ได้แล้ว แต่ได้รับ HTTP 400 และ UI แสดง `[object Object]`.

## ทำตอนนี้
1. Supabase > Edge Functions > create-enrollment > Code
2. เปิด `index.ts` แล้วแทนที่ทั้งหมดด้วย `supabase/functions/create-enrollment/index.ts` ชุดนี้
3. Deploy function และตรวจ Settings > Verify JWT with legacy secret = OFF
4. เปิด endpoint ด้วย GET ต้องเห็น `version: v15.2.3-rescue`
5. อัป `js/supabase-bridge.js` ชุดนี้ทับ GitHub เพื่อให้ error ในอนาคตแสดงรายละเอียดจริง
6. Ctrl+Shift+R แล้วส่งใบสมัครใหม่

Rescue mode เขียน Enrollment ก่อนเป็นอันดับแรก และทำ Receipt/Slip/Payment เป็น best-effort เพื่อไม่ให้การรับสมัครล้มเพราะโมดูลเสริมชั่วคราวไม่พร้อม. รายการที่ fallback จะถูกเก็บใน `raw_payload.rescueWarnings` เพื่อให้ Manager ตรวจสอบภายหลัง.
