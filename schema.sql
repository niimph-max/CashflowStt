-- ============================================================================
--  Cashflow — โครงสร้างฐานข้อมูล (ตารางขึ้นต้น cf_ · อยู่ในโปรเจกต์ Supabase "Fillbook")
--  แนวคิดแบบ Money Lover: ทุกรายการผูกกับบัญชี (wallet) · ยอดแต่ละบัญชีคำนวณจากยอดเปิด + รายการ
--  รันครั้งเดียว: SQL Editor → วางทั้งไฟล์ → Run
--  ทุกตารางมี owner = ผู้ใช้ที่ login · RLS ให้เห็น/แก้ได้เฉพาะของตัวเอง
-- ============================================================================

-- ตั้งค่าส่วนตัว: เกณฑ์เตือนเงินต่ำ
create table if not exists cf_settings (
  owner       uuid primary key default auth.uid() references auth.users on delete cascade,
  warn_below  numeric(16,2) not null default 0,
  updated_at  timestamptz not null default now()
);

-- บัญชี / กระเป๋าเงิน
create table if not exists cf_accounts (
  id               bigint generated always as identity primary key,
  owner            uuid not null default auth.uid() references auth.users on delete cascade,
  name             text not null,
  opening_balance  numeric(16,2) not null default 0,
  opening_date     date not null default current_date,
  in_total         boolean not null default true,   -- รวมใน Total หรือไม่
  sort             int not null default 0,
  active           boolean not null default true,
  unique (owner, name)
);

-- หมวด: in = เงินสดเข้า · debt = ชำระหนี้ · exp = ค่าใช้จ่าย
create table if not exists cf_categories (
  id      bigint generated always as identity primary key,
  owner   uuid not null default auth.uid() references auth.users on delete cascade,
  grp     text not null check (grp in ('in','debt','exp')),
  name    text not null,
  sort    int  not null default 0,
  active  boolean not null default true,
  unique (owner, grp, name)
);

-- รายการ
--   kind = flow     : เงินเข้า/ออกตามหมวด · amount บวก · เครื่องหมายมาจากหมวด (in = +, debt/exp = −)
--   kind = transfer : โอนจาก account_id ไป to_account_id · amount บวก · ไม่นับเป็นรายรับ/รายจ่าย
--   kind = adjust   : ปรับยอดให้ตรง statement · amount มีเครื่องหมาย (+ เพิ่ม / − ลด)
--   planned = ประมาณการ (ยังไม่จ่าย/ยังไม่ได้รับจริง)
create table if not exists cf_txns (
  id             bigint generated always as identity primary key,
  owner          uuid not null default auth.uid() references auth.users on delete cascade,
  kind           text not null default 'flow' check (kind in ('flow','transfer','adjust')),
  d              date not null,
  account_id     bigint not null references cf_accounts(id) on delete restrict,
  to_account_id  bigint references cf_accounts(id) on delete restrict,
  category_id    bigint references cf_categories(id) on delete restrict,
  amount         numeric(16,2) not null,
  note           text not null default '',
  planned        boolean not null default false,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check ((kind = 'flow' and category_id is not null and to_account_id is null)
      or (kind = 'transfer' and to_account_id is not null and to_account_id <> account_id and category_id is null)
      or (kind = 'adjust' and category_id is null and to_account_id is null))
);
create index if not exists idx_cf_txns_owner_d on cf_txns(owner, d);

-- ===== RLS: เจ้าของเท่านั้น ==================================================
alter table cf_settings   enable row level security;
alter table cf_accounts   enable row level security;
alter table cf_categories enable row level security;
alter table cf_txns       enable row level security;

drop policy if exists own_all on cf_settings;
create policy own_all on cf_settings   for all to authenticated using (owner = auth.uid()) with check (owner = auth.uid());
drop policy if exists own_all on cf_accounts;
create policy own_all on cf_accounts   for all to authenticated using (owner = auth.uid()) with check (owner = auth.uid());
drop policy if exists own_all on cf_categories;
create policy own_all on cf_categories for all to authenticated using (owner = auth.uid()) with check (owner = auth.uid());
drop policy if exists own_all on cf_txns;
create policy own_all on cf_txns       for all to authenticated using (owner = auth.uid()) with check (owner = auth.uid());

-- anon (ยังไม่ login) แตะอะไรไม่ได้เลย
revoke all on cf_settings, cf_accounts, cf_categories, cf_txns from anon;

-- ตรวจ: select tablename, rowsecurity from pg_tables where tablename like 'cf_%';
