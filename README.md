# โรงเรียนวัดหนองแวงวิทยา — GitHub Pages + Supabase CMS

## เวอร์ชัน No-Code Manager

เวอร์ชันนี้ออกแบบให้ผู้ดูแลเว็บไซต์ใช้งานผ่าน **แบบฟอร์มทั้งหมด** โดยไม่ต้องแก้ HTML, JavaScript หรือ JSON ในหน้า Manager

### เมนูใน Website Manager
- **ข้อมูลโรงเรียน** — โลโก้ ชื่อโรงเรียน ข้อมูลติดต่อ จำนวนสามเณร/บุคลากร ผู้อำนวยการ และประวัติโรงเรียน
- **หน้าแรก / แบนเนอร์** — Intro/หน้ารำลึก ประกาศด่วน ภาพ Welcome และแบนเนอร์
- **บุคลากร** — เพิ่ม/แก้ไข/ลบ ผู้บริหาร ครู บุคลากร และครูพิเศษ พร้อมอัปโหลดรูป
- **ข่าว / กิจกรรม** — เพิ่ม/แก้ไข/ลบ/ซ่อนข่าวประชาสัมพันธ์และปฏิทินกิจกรรมจากฟอร์ม
- **วิชาการ** — วันสอบบาลี บาลีวันละคำ พุทธสุภาษิต สถิติสอบ กิจวัตรประจำวัน และแผนการเรียน
- **บริการ / ลิงก์** — บัญชีบริจาค Social/Maps/Video, Smart Environment, E-Services และเอกสารดาวน์โหลด
- **ผลงาน** — CRUD ผลงานแห่งความภาคภูมิใจ พร้อม Publish/Hide และรูปภาพ
- **บัญชี Admin** — แสดงบัญชีผู้ดูแลปัจจุบันและลิงก์ไป Supabase Authentication Users

รายการแบบหลายรายการ เช่น ข่าว กิจกรรม เอกสาร และกิจวัตร มีปุ่ม **เพิ่ม / แก้ไข / ลบ / เลื่อนขึ้น / เลื่อนลง / เปิด-ปิดการแสดงผล**

## Admin mode: Supabase Authentication = Website Manager

บัญชีแบบ non-anonymous ที่สร้างใน **Supabase Dashboard → Authentication → Users** สามารถล็อกอินที่ `/manager/` ได้

### ถ้าเคยติดตั้งเวอร์ชันก่อนหน้าแล้ว
1. รัน `supabase/authentication-admin-mode.sql` ถ้ายังไม่เคยรัน
2. รัน `supabase/no-code-manager-upgrade.sql` หนึ่งครั้ง เพื่อให้อัปโหลด PDF/DOCX/XLSX/PPTX ผ่าน Manager ได้
3. สร้าง/เชิญบัญชีผู้ดูแลใน **Authentication → Users**
4. ล็อกอินที่ `/manager/`

### ความปลอดภัย
ใน **Authentication → General Configuration** แนะนำให้ปิด:
- Allow new users to sign up
- Allow anonymous sign-ins

## Supabase ที่ตั้งค่าไว้

`assets/app-config.js` ตั้งค่า Project นี้ไว้แล้ว:
- Project URL: `https://pcapjltgscofrgfcvdkm.supabase.co`
- ใช้ publishable key ฝั่ง frontend
- Storage bucket: `site-media`

> ห้ามใส่ `service_role` key ใน GitHub Pages

## Deploy บน GitHub Pages

อัปโหลดไฟล์ทั้งหมดในโฟลเดอร์นี้ไปที่ root ของ repository แล้วเปิด **Settings → Pages**

- เว็บไซต์หลัก: `/`
- Website Manager: `/manager/`
- ผลงานทั้งหมด: `/achievements/`

Relative links รองรับ GitHub Project Pages ที่มี `/REPOSITORY/` ใน URL

## Intro Cover

Intro/หน้ารำลึกจะแสดงตั้งแต่ first paint ไม่รอ Supabase จึงไม่เห็นหน้าเว็บหลักแวบขึ้นมาก่อน และข้อความ Intro รองรับการขึ้นบรรทัดใหม่ด้วยการกด Enter โดยไม่ต้องพิมพ์ `<br>`

## ผลงานแห่งความภาคภูมิใจ

หน้าเว็บหลักดึงผลงานที่ `published = true` จากตาราง `achievements` เรียงใหม่สุดก่อน และแสดง 3 รายการล่าสุด ส่วนปุ่มดูเพิ่มเติมเปิด `/achievements/`

## Image Preview in Website Manager

เวอร์ชันนี้แสดงตัวอย่างภาพทันทีเมื่อเลือกไฟล์อัปโหลด และแสดงภาพเดิมเมื่อเปิดมาแก้ไข รองรับโลโก้, ภาพผู้อำนวยการ, ภาพประวัติโรงเรียน, Intro, Welcome, QR บริจาค, Banner, บุคลากร และผลงานแห่งความภาคภูมิใจ โดย Preview จากเครื่องจะแสดงก่อนอัปโหลดเสร็จ พร้อมชื่อไฟล์ ขนาดไฟล์ และความละเอียดภาพเมื่ออ่านได้



## ข่าวสาร (อัปเดต)
หน้าเว็บหลักมีเซคชัน “ข่าวสาร” แยกจากกิจกรรม/ปฏิทิน แสดงข่าวล่าสุดสูงสุด 6 รายการ พร้อมภาพปก หมวด วันที่ คำโปรย และลิงก์อ่านเพิ่มเติม ใน Manager มีเมนู “ข่าวสาร” แยกจาก “กิจกรรม / ปฏิทิน” และรองรับอัปโหลดภาพพร้อม Preview ก่อนบันทึก


## Supabase update: ข่าวสารแบบตารางแยก

เวอร์ชันนี้ย้าย **ข่าวสาร** ออกจาก JSON ใน `site_settings` มาใช้ตาราง `public.news` โดยตรง

1. ไปที่ **Supabase → SQL Editor → New query**
2. รันไฟล์ `supabase/news-section-upgrade.sql`
3. อัปโหลดเว็บเวอร์ชันนี้ขึ้น GitHub Pages
4. เข้า `/manager/` → **ข่าวสาร**

ข่าวเดิมใน `site_settings.data.news` จะถูกคัดลอกเข้าตาราง `news` อัตโนมัติเมื่อ table ยังว่าง และการรัน SQL ซ้ำจะไม่เพิ่มข่าวซ้ำ

หลังอัปเกรด การเพิ่ม/แก้ไข/ลบ/จัดลำดับข่าวใน Manager จะเขียนลง Supabase ทันที โดยไม่ต้องกดปุ่ม **บันทึกเว็บไซต์** สำหรับข่าว ส่วนปุ่มบันทึกเว็บไซต์ยังใช้กับข้อมูลทั่วไปที่เก็บใน `site_settings` อยู่

---

## Admission Subweb

เพิ่มระบบรับสมัครเป็น subweb แล้ว:

- `./admission/` ระบบรับสมัคร
- `./admission/manager/` ระบบเจ้าหน้าที่รับสมัคร

ก่อนใช้งานให้รัน `supabase/admission-system.sql` ใน Supabase SQL Editor ดูรายละเอียดเพิ่มเติมที่ `admission/README.md`

## Update: Personnel profile + News images

- Personnel Manager fields now include education history, phone, email, alumni checkbox, and alumni batch/generation.
- Alumni batch is required only when the alumni checkbox is enabled.
- Public personnel cards show an alumni badge and open a detail modal with education/contact information.
- News Manager supports cover-image upload with live preview; the image is stored in Supabase Storage and its public URL is saved in `news.image_url`.
- No additional SQL migration is required for these personnel fields because personnel remain stored inside `site_settings.data`. The existing dedicated `news` table already contains `image_url`.

---

## Alumni Directory Subweb

เพิ่มระบบสมุดทำเนียบศิษย์เก่าเป็น subweb แยก:

- `./alumni/` — สมุดทำเนียบศิษย์เก่า ค้นหาและกรองตามรุ่นได้ พร้อมเปิดโปรไฟล์รายบุคคลและพิมพ์ทำเนียบรุ่น
- `./alumni/manager/` — Alumni Manager สำหรับเพิ่ม/แก้ไข/ลบ/ซ่อน-แสดงข้อมูลศิษย์เก่า อัปโหลดรูป และ Export CSV

ก่อนใช้งาน ให้รัน `supabase/alumni-directory.sql` ใน Supabase SQL Editor หนึ่งครั้ง

ข้อมูลโลโก้และชื่อโรงเรียนดึงจาก `site_settings` ของเว็บหลักอัตโนมัติ ส่วนบุคลากรที่ถูกติ๊ก `isAlumni` ใน Website Manager จะถูกนำมาแสดงในทำเนียบศิษย์เก่าอัตโนมัติ โดยไม่ต้องเพิ่มซ้ำในตาราง `alumni`

---

## Supabase update: บุคลากรแบบตารางแยก (`public.personnel`)

เวอร์ชันนี้ย้ายข้อมูล **ผู้บริหาร / ครูและบุคลากร / ครูพิเศษ** ออกจาก JSON ใน `site_settings` มาเก็บในตาราง `public.personnel` โดยตรง เพื่อให้ค้นหา ตรวจสอบ และแก้ไขจาก Supabase Table Editor ได้ง่าย

1. ไปที่ **Supabase → SQL Editor → New query**
2. รัน `supabase/personnel-system.sql`
3. SQL จะคัดลอกข้อมูลเดิมจาก `site_settings.data.executives`, `teachers`, `specialTeachers` เข้า `personnel` อัตโนมัติเมื่อ table ยังว่าง
4. อัปโหลดเว็บเวอร์ชันนี้ขึ้น GitHub Pages
5. เข้า `/manager/` → **บุคลากร** จะเห็นสถานะสีเขียว “เชื่อมต่อ Supabase personnel แล้ว”

ฟิลด์ในตารางประกอบด้วย ชื่อ, ประเภทบุคลากร, ตำแหน่ง, กลุ่มสาระ/หน้าที่, รูป, ประวัติการศึกษา, โทรศัพท์, Email, สถานะศิษย์เก่า, รุ่นศิษย์เก่า, สถานะเผยแพร่ และลำดับการแสดงผล

หลังอัปเกรด การเพิ่ม/แก้ไข/ลบบุคลากรใน Website Manager จะบันทึกลง `public.personnel` ทันที ไม่ต้องกด “บันทึกเว็บไซต์” ซ้ำสำหรับบุคลากร และหน้าเว็บหลัก/ทำเนียบศิษย์เก่าจะอ่านข้อมูลจากตารางนี้โดยตรง


## University Admission PR Subweb

- Public: `/university-admission/`
- Manager: `/university-admission/manager/`
- Database: `public.university_admissions`
- Run `supabase/university-admissions.sql` once in Supabase SQL Editor.
- Supports university logo URL or image upload, poster URL/upload, application link, announcement link, university website link, dates, status, filters, featured items, publish/hide, and CSV export.
