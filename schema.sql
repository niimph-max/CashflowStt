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

-- ผู้ติดต่อ หนี้/เงินยืม (เจ้าหนี้ เช่น Thani / Kbank · หรือคนที่เราให้ยืม)
--   opening_debt = ยอดคงค้างยกมา ณ วันเริ่มใช้: + = เราเป็นหนี้เขา · − = เขาเป็นหนี้เรา
create table if not exists cf_parties (
  id            bigint generated always as identity primary key,
  owner         uuid not null default auth.uid() references auth.users on delete cascade,
  name          text not null,
  opening_debt  numeric(16,2) not null default 0,
  sort          int not null default 0,
  active        boolean not null default true,
  unique (owner, name)
);

-- หมวด: in = เงินสดเข้า · exp = ค่าใช้จ่าย (debt สงวนไว้ ไม่ใช้แล้ว — หนี้ใช้ cf_parties)
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
--   kind = loan     : หนี้/เงินยืม กับ party_id · amount บวก · loan_type:
--                     borrow = กู้ยืม (เงินเข้า) · repay = ชำระหนี้ (เงินออก) · lend = ให้ยืม (เงินออก) · collect = รับชำระคืน (เงินเข้า)
--   planned = ประมาณการ (ยังไม่จ่าย/ยังไม่ได้รับจริง)
create table if not exists cf_txns (
  id             bigint generated always as identity primary key,
  owner          uuid not null default auth.uid() references auth.users on delete cascade,
  kind           text not null default 'flow' check (kind in ('flow','transfer','adjust','loan')),
  d              date not null,
  account_id     bigint not null references cf_accounts(id) on delete restrict,
  to_account_id  bigint references cf_accounts(id) on delete restrict,
  category_id    bigint references cf_categories(id) on delete restrict,
  party_id       bigint references cf_parties(id) on delete restrict,
  loan_type      text check (loan_type in ('borrow','repay','lend','collect')),
  amount         numeric(16,2) not null,
  note           text not null default '',
  planned        boolean not null default false,
  ecacc_done     boolean not null default false,   -- ติ๊กแล้วว่าลงโปรแกรมบัญชี ECACC
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check ((kind = 'flow' and category_id is not null and to_account_id is null and party_id is null)
      or (kind = 'transfer' and to_account_id is not null and to_account_id <> account_id and category_id is null and party_id is null)
      or (kind = 'adjust' and category_id is null and to_account_id is null and party_id is null)
      or (kind = 'loan' and party_id is not null and loan_type is not null and category_id is null and to_account_id is null))
);
create index if not exists idx_cf_txns_owner_d on cf_txns(owner, d);

-- ===== RLS: เจ้าของเท่านั้น ==================================================
alter table cf_settings   enable row level security;
alter table cf_accounts   enable row level security;
alter table cf_parties    enable row level security;
alter table cf_categories enable row level security;
alter table cf_txns       enable row level security;

drop policy if exists own_all on cf_settings;
create policy own_all on cf_settings   for all to authenticated using (owner = auth.uid()) with check (owner = auth.uid());
drop policy if exists own_all on cf_accounts;
create policy own_all on cf_accounts   for all to authenticated using (owner = auth.uid()) with check (owner = auth.uid());
drop policy if exists own_all on cf_parties;
create policy own_all on cf_parties    for all to authenticated using (owner = auth.uid()) with check (owner = auth.uid());
drop policy if exists own_all on cf_categories;
create policy own_all on cf_categories for all to authenticated using (owner = auth.uid()) with check (owner = auth.uid());
drop policy if exists own_all on cf_txns;
create policy own_all on cf_txns       for all to authenticated using (owner = auth.uid()) with check (owner = auth.uid());

-- anon (ยังไม่ login) แตะอะไรไม่ได้เลย
revoke all on cf_settings, cf_accounts, cf_parties, cf_categories, cf_txns from anon;

-- ตรวจ: select tablename, rowsecurity from pg_tables where tablename like 'cf_%';


-- ===== ส่วนเพิ่ม (เหมือน migrate_02_recurring_budget.sql) — ติดตั้งใหม่รันไฟล์นี้ไฟล์เดียวพอ =====

-- รายการประจำ: แม่แบบรายการ + ความถี่ · แอปสร้างรายการ "ประมาณการ" ล่วงหน้า 90 วันให้เอง
--   gen_until = สร้างรายการไว้ถึงวันที่เท่าไรแล้ว (รอบถัดไปสร้างต่อจากวันนี้)
create table if not exists cf_recurring (
  id             bigint generated always as identity primary key,
  owner          uuid not null default auth.uid() references auth.users on delete cascade,
  kind           text not null check (kind in ('flow','transfer','loan')),
  account_id     bigint not null references cf_accounts(id) on delete cascade,
  to_account_id  bigint references cf_accounts(id) on delete cascade,
  category_id    bigint references cf_categories(id) on delete cascade,
  party_id       bigint references cf_parties(id) on delete cascade,
  loan_type      text check (loan_type in ('borrow','repay','lend','collect')),
  amount         numeric(16,2) not null,
  note           text not null default '',
  freq           text not null check (freq in ('daily','weekly','monthly','yearly')),
  every          int  not null default 1 check (every >= 1),
  start_date     date not null,
  end_date       date,
  gen_until      date,
  active         boolean not null default true,
  created_at     timestamptz not null default now()
);

-- รายการที่สร้างจากรายการประจำ: 1 วันต่อ 1 รายการ (กันสร้างซ้ำ)
alter table cf_txns add column if not exists recurring_id bigint references cf_recurring(id) on delete set null;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'cf_txns_recurring_d_key') then
    alter table cf_txns add constraint cf_txns_recurring_d_key unique (recurring_id, d);
  end if;
end $$;

-- งบประมาณรายเดือนต่อหมวด (ใช้ซ้ำทุกเดือน)
create table if not exists cf_budgets (
  id           bigint generated always as identity primary key,
  owner        uuid not null default auth.uid() references auth.users on delete cascade,
  category_id  bigint not null references cf_categories(id) on delete cascade,
  amount       numeric(16,2) not null check (amount >= 0),
  unique (owner, category_id)
);

alter table cf_recurring enable row level security;
alter table cf_budgets   enable row level security;
drop policy if exists own_all on cf_recurring;
create policy own_all on cf_recurring for all to authenticated using (owner = auth.uid()) with check (owner = auth.uid());
drop policy if exists own_all on cf_budgets;
create policy own_all on cf_budgets   for all to authenticated using (owner = auth.uid()) with check (owner = auth.uid());
revoke all on cf_recurring, cf_budgets from anon;

-- ตรวจ: select tablename, rowsecurity from pg_tables where tablename in ('cf_recurring','cf_budgets');
