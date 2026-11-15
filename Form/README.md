# BioAre — ติดตั้งเป็นโฟลเดอร์ย่อยของเว็บไซต์หลัก

BioAre (แบบประเมินวิทยากรพี่อาร์ + Manager เฉพาะระบบ) แยกจากเว็บไซต์หลักอย่างสมบูรณ์ในด้านเส้นทางหน้าเว็บ ไม่ทับ `index.html` หรือ `manager.html` ที่ root ของเว็บไซต์หลัก

## โครงสร้างไฟล์ที่จะเพิ่มใน GitHub

```text
เว็บไซต์หลัก/                  ← ไฟล์เดิมทั้งหมดอยู่เหมือนเดิม
├── index.html                 ← เว็บหลัก (ไม่ต้องแทนที่)
├── manager.html               ← Manager เว็บหลัก (ไม่ต้องแทนที่)
└── bioare/                    ← ยกโฟลเดอร์นี้ไปวาง
    ├── index.html             ← หน้าต้อนรับ + PDPA + แบบประเมิน
    ├── manager.html           ← BioAre Manager แยกจาก Manager เว็บหลัก
    ├── database/
    │   ├── setup_all.sql      ← สร้าง/ตั้งค่าสิทธิ์ใน Supabase
    │   └── grant_manager.sql  ← ให้สิทธิ์บัญชีผู้ดูแล
    └── README.md
```

**URL หลังเผยแพร่ (สมมุติ repo อยู่ที่ `https://username.github.io/repo/`):**
- เว็บหลัก: `https://username.github.io/repo/`
- BioAre Feedback: `https://username.github.io/repo/bioare/`
- BioAre Manager: `https://username.github.io/repo/bioare/manager.html`
- Manager เดิมของเว็บหลัก: `https://username.github.io/repo/manager.html` (ยังอยู่)

> ต้องวาง *โฟลเดอร์* `bioare` ทั้งโฟลเดอร์ลงใน root ของเว็บหลัก **ไม่ใช่** นำไฟล์ `index.html` กับ `manager.html` ไปทับไฟล์ที่ root

## วิธีติดตั้ง

1. แตก ZIP จะได้โฟลเดอร์ `bioare/` จากนั้นลากทั้งโฟลเดอร์ไปใส่ GitHub repo เว็บไซต์หลัก (ตำแหน่งเดียวกับ `index.html` ของเว็บหลัก) แล้ว commit
2. ใช้ Supabase project `ihmiqtwclnqrezsnswfz` เหมือนเดิม ไปที่ SQL Editor แล้วรัน `bioare/database/setup_all.sql` **ครั้งเดียว**; SQL เป็นแบบไม่ลบคำตอบเก่า
3. ใน Supabase Authentication → Users ตรวจสอบว่ามีบัญชี `arewarin.biology@gmail.com` แล้ว หากยังไม่มี ให้สร้างและตั้งรหัสผ่านผ่านหน้า Dashboard เท่านั้น
4. รัน `bioare/database/grant_manager.sql` ใน SQL Editor เพื่อให้สิทธิ์บัญชีนี้เป็นผู้ดูแลผลประเมิน
5. เปิดหน้า `.../bioare/` ทดสอบส่งคำตอบ และเปิด `.../bioare/manager.html` ลงชื่อเข้าใช้ด้วยอีเมลที่ตั้งไว้
6. หากเว็บหลักมีเมนู Manager อยู่แล้ว เพิ่มเพียงลิงก์ BioAre เข้าไปใน Manager หลัก ตามตัวอย่างด้านล่าง (ไฟล์เว็บไซต์หลักไม่ได้ถูกแก้ไขให้อัตโนมัติ)

## เพิ่มลิงก์ภายในเว็บหลัก (ตัวอย่าง)

วางในหน้าเมนูหรือ Manager หลัก:

```html
<a href="./bioare/">BioAre · แบบประเมินวิทยากร</a>
<a href="./bioare/manager.html">BioAre · จัดการผลประเมิน</a>
```

ถ้าลิงก์ถูกวางไว้ในหน้าเว็บหลักที่ **ไม่ได้อยู่ที่ root** ต้องปรับ URL ตามตำแหน่งหน้าเว็บที่เรียกใช้งาน (เช่น `/ชื่อ-repo/bioare/manager.html`)

## ทำงานแยกจาก Manager เว็บหลักอย่างไร

- `bioare/manager.html` มีระบบล็อกอินและ Dashboard ของตัวเอง
- `manager.html` ที่ root ไม่ถูกเขียนทับและจะทำงานเหมือนเดิม
- Manager ของ BioAre ใช้ Supabase Auth storage key เฉพาะ (`bioare-feedback-manager-auth-v1`) เพื่อลดการชนกับเซสชันล็อกอินของ Manager เดิมที่อาจใช้ Supabase project เดียวกัน
- หน้าแบบประเมินกับ BioAre Manager ลิงก์ไปหากันแบบ relative `./manager.html`, `./index.html` และมีลิงก์ `../` สำหรับกลับเว็บไซต์หลัก
- สิทธิ์ข้อมูลจาก Supabase ตรวจจาก `speaker_feedback_admins` โดย RLS; URL ของ Manager เป็นสาธารณะได้ แต่ผลประเมินต้องผ่านการยืนยันตัวตนและสิทธิ์ในฐานข้อมูล

## ความปลอดภัย/การใช้งานจริง

- รหัสผ่าน **ไม่อยู่** ใน HTML, SQL, GitHub หรือ ZIP
- `sb_publishable_...` ใช้ได้บน frontend เมื่อกำหนด RLS ตาม SQL แล้ว ห้ามนำ `service_role` หรือ `sb_secret_...` ขึ้น GitHub
- ผู้ตอบส่งข้อมูลได้แต่ไม่สามารถอ่านผลประเมินจาก public key; มีเฉพาะบัญชีที่ได้รับสิทธิ์ใน `speaker_feedback_admins` อ่านข้อมูลได้
- ระบบเก็บข้อมูลโรงเรียน/ระดับชั้น และชื่อเล่นหรือชื่อ-นามสกุลเมื่อผู้ตอบเลือกกรอก โปรดตรวจทานประกาศ PDPA ระยะเวลาเก็บรักษา และแนวทางจัดการข้อมูลผู้เยาว์ก่อนเผยแพร่
- **SQL นี้ใช้ตาราง `speaker_feedback` เดิม** จึงสามารถดูผลประเมินเดิมได้ ไม่สร้างตารางใหม่ซ้ำ
- ยังไม่ได้รัน SQL หรือทดสอบเขียนข้อมูลใน Supabase จริง เนื่องจากไม่มีสิทธิ์เข้าโปรเจกต์ของคุณ

## ข้อจำกัดของเว็บที่มี Routing

โครงสร้างนี้เหมาะกับ GitHub Pages หรือ static hosting ที่เปิดไฟล์ใน subfolder ได้ตรง ๆ หากเว็บหลักใช้ React/Vue Router หรือ Vercel rewrites ที่ส่งทุก route ไป root `index.html` ต้องเพิ่มข้อยกเว้นสำหรับ `/bioare/*` เพื่อให้เปิดไฟล์ HTML ในโฟลเดอร์นี้โดยตรง
