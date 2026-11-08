# Cashflow

แอปติดตามกระแสเงินสดบริษัท (ใช้คนเดียว) — แนวคิดแบบ Money Lover: ทุกรายการผูกกับบัญชี (wallet)
ส่งออกเป็นตาราง Cashflow (.xlsx) หน้าตาเดียวกับไฟล์ Excel เดิมได้เสมอ

- เว็บ: https://niimph-max.github.io/CashflowStt/
- โค้ด: `index.html` ไฟล์เดียว (HTML + JS ล้วน ไม่มี build step)
- ข้อมูล: Supabase โปรเจกต์ **Fillbook** (ตารางขึ้นต้น `cf_`) · โครงสร้างใน `schema.sql`
- ทดลองโดยไม่ต่อฐานข้อมูล: เปิด `index.html?demo`

## ตั้งค่าครั้งแรก
1. Supabase (Fillbook) → SQL Editor → รัน `schema.sql` ทั้งไฟล์
2. Authentication → Add user (อีเมล + รหัสผ่านของเจ้าของ) · ปิด sign-up สาธารณะ
3. ใส่ Project URL + anon key ที่ `CF_SUPABASE_URL` / `CF_SUPABASE_ANON` ใน `index.html`
   (anon key เปิดเผยได้โดยออกแบบ — ตัวป้องกันคือ RLS `owner = auth.uid()` · **ห้ามใส่ service_role key**)
4. GitHub → Settings → Pages → Branch `main` / root

## ประเภทรายการ (`cf_txns.kind`)
| kind | ความหมาย | ในตาราง Cashflow |
|---|---|---|
| flow | เงินเข้า / ค่าใช้จ่าย ตามหมวด | แถวตามหมวด |
| loan | กู้ยืม / ชำระหนี้ / ให้ยืม / รับชำระคืน กับ `cf_parties` | เงินยืม/รับชำระคืน · ชำระหนี้ตามเจ้าหนี้ |
| transfer | โอนระหว่างบัญชี | โอน/ปรับยอด |
| adjust | ปรับยอดให้ตรง statement | โอน/ปรับยอด |

ยอดบัญชี = ยอดตั้งต้น + รายการที่ยืนยันแล้ว · ยอดคาดการณ์/ตาราง = นับรายการประมาณการด้วย (เหมือน Excel เดิม)
