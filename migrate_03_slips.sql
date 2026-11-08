-- ============================================================================
--  Cashflow — ส่วนเพิ่ม: แนบสลิป / ใบเสร็จ (รันครั้งเดียวในโปรเจกต์ Fillbook)
--  รูปเก็บใน Supabase Storage bucket "cf-slips" แบบ private (ไม่ใช่ในฐานข้อมูล)
--  path = <user id>/<รหัสรายการ>/<ชื่อไฟล์>.jpg · เห็น/ลบได้เฉพาะเจ้าของโฟลเดอร์ (auth.uid())
--  แอปย่อรูปก่อนอัปโหลด (~100–200 KB/รูป) · จำกัดไฟล์ละ 5 MB เผื่อไว้
-- ============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('cf-slips', 'cf-slips', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

drop policy if exists cf_slips_select on storage.objects;
create policy cf_slips_select on storage.objects for select to authenticated
  using (bucket_id = 'cf-slips' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists cf_slips_insert on storage.objects;
create policy cf_slips_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'cf-slips' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists cf_slips_delete on storage.objects;
create policy cf_slips_delete on storage.objects for delete to authenticated
  using (bucket_id = 'cf-slips' and (storage.foldername(name))[1] = auth.uid()::text);

-- รายชื่อไฟล์ที่แนบกับรายการ (array ของ path ใน bucket)
alter table cf_txns add column if not exists attachments jsonb not null default '[]'::jsonb;

-- ตรวจ: select id, public from storage.buckets where id = 'cf-slips';
