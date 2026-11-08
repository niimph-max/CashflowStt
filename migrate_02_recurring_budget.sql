-- ============================================================================
--  Cashflow — ส่วนเพิ่ม: รายการประจำ (recurring) + งบประมาณ (budget)
--  รันครั้งเดียวในโปรเจกต์ Fillbook (หลัง schema.sql) · ไม่แตะข้อมูลเดิม
-- ============================================================================

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
