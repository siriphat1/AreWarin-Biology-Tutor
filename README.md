# AreWarin Ready Replace v6 — Package Hide Fix

เวอร์ชันนี้แก้ปัญหา:

> ปิด 20 ชั่วโมง / 10 ชั่วโมง / รายปีใน Manager แล้ว
> แต่หน้า "เลือกแพ็กเกจ" ยังแสดงอยู่

## สาเหตุ

หน้าเดิมมี CSS:

```css
.pkgv6-label { display: block; }
```

ในขณะที่ระบบใช้ class `hidden` เพื่อซ่อนแพ็กเกจ

จึงเกิดกรณี CSS ของ card ชนะ `hidden` และ card ยังแสดงอยู่ แม้ค่าจากฐานข้อมูลจะเป็นปิดแล้ว

## สิ่งที่ v6 แก้

1. บังคับ `.pkgv6-label.hidden { display:none !important; }`
2. ตอนปิด package ใช้ inline `display:none !important` เพิ่มอีกชั้น
3. ทุกครั้งที่เข้าหน้า "รูปแบบ & เวลาเรียน" จะโหลด `course_package_rules` ใหม่
4. ป้องกันข้อมูล package cache เก่า
5. ราคาเฉพาะคอร์สยังทำงานต่อจาก v5

## ใช้งาน

วางทับ:

```text
YOUR-REPO/
├─ index.html          <- ใช้ index.html จาก v6
└─ manager/
   └─ index.html       <- ใช้ manager/index.html จาก v6
```

ถ้าเคยรัน `AREWARIN_V5_RECOVERY.sql` สำเร็จแล้ว ไม่ต้องรัน SQL ซ้ำ

ถ้ายังไม่เคยรัน ให้รัน:

```text
supabase/AREWARIN_V5_RECOVERY.sql
```

## หลัง Push GitHub

1. รอ GitHub Pages deploy
2. เปิดเว็บใหม่
3. Ctrl + Shift + R หรือ Ctrl + F5
4. เลือกคอร์สใหม่อีกครั้ง
5. เข้าหน้า "รูปแบบ & เวลาเรียน"

ตัวอย่าง Biochemistry ถ้า Manager เปิดเฉพาะ:
- 30 ชั่วโมง
- รายชั่วโมง

หน้าเว็บต้องเห็นแค่ 2 card นี้เท่านั้น
