# Admission Subweb

โครงสร้าง URL เมื่อ deploy บน GitHub Pages:

- `/` เว็บไซต์หลัก
- `/admission/` ระบบรับสมัครนักเรียน
- `/admission/manager/` ระบบหลังบ้านรับสมัคร
- `/manager/` Website Manager ของเว็บไซต์หลัก

## สิ่งที่ระบบรับสมัครดึงจากเว็บหลัก

ระบบอ่าน `public.site_settings` แถว `id = 1` จาก Supabase เดียวกับเว็บไซต์หลัก จึงใช้ข้อมูลชุดเดียวกัน ได้แก่:

- ชื่อโรงเรียน
- โลโก้
- ภาพ Welcome สำหรับ Hero
- ที่อยู่
- เบอร์โทร
- Facebook

เมื่อ Website Manager แก้ข้อมูลเหล่านี้ หน้า Admission จะเปลี่ยนตามโดยไม่ต้องแก้ HTML ของระบบสมัคร

## ฐานข้อมูล

ให้รันไฟล์ `../supabase/admission-system.sql` ใน Supabase SQL Editor 1 ครั้ง

ไฟล์นี้จะสร้าง:

- `public.admission_applications`
- RPC `create_admission_application()`
- RPC `finalize_admission_application()`
- RPC `check_admission_status()`
- Private Storage bucket `admission-files`
- RLS สำหรับผู้สมัครและเจ้าหน้าที่
- เปลี่ยน quick link “รับสมัครนักเรียน” ของเว็บหลักให้ไป `./admission/`

## Admin

Admin ใช้บัญชีจาก Supabase Authentication เดียวกับ Website Manager

แนะนำให้ปิด public sign-up ใน Supabase Authentication เพราะ authenticated users มีสิทธิ์อ่านและจัดการใบสมัคร

หน้า `/admission/manager/` ทำได้:

- ดูรายการผู้สมัครทั้งหมด
- ค้นหาและกรองตามสถานะ/ระดับชั้น
- ดูข้อมูลผู้สมัครและข้อมูลครอบครัว
- Preview รูปและเปิดเอกสารแนบจาก private storage ผ่าน signed URL
- เปลี่ยนสถานะ รอตรวจ / กำลังตรวจ / สำรอง / อนุมัติ / ไม่อนุมัติ
- บันทึกข้อความภายใน
- บันทึกข้อความที่ผู้สมัครเห็นตอนตรวจสถานะ
- Print ใบสมัคร
- Export CSV

## Storage

`admission-files` เป็น private bucket ขนาดสูงสุด 10 MB ต่อไฟล์ รองรับ JPEG, PNG, WEBP, HEIC/HEIF และ PDF
