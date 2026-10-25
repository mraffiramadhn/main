-- Finance Hub schema for Supabase
-- Run this in Supabase Dashboard > SQL Editor after creating your project.
-- All tables use Row Level Security (RLS); each signed-in user can access only their own rows.

create table if not exists public.finance_assets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 100),
  asset_type text not null check (asset_type in ('Kas','Rekening','Tabungan','Deposito','Investasi','Piutang','Lainnya')),
  amount bigint not null check (amount >= 0),
  note text not null default '' check (char_length(note) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.finance_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  transaction_date date not null default current_date,
  transaction_type text not null check (transaction_type in ('income','expense')),
  category text not null check (char_length(category) between 1 and 100),
  amount bigint not null check (amount > 0),
  note text not null default '' check (char_length(note) <= 500),
  created_at timestamptz not null default now()
);

create table if not exists public.finance_liabilities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 100),
  amount bigint not null check (amount >= 0),
  note text not null default '' check (char_length(note) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.finance_goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null default 'Target tabungan' check (char_length(name) between 1 and 100),
  target_amount bigint not null default 0 check (target_amount >= 0),
  current_amount bigint not null default 0 check (current_amount >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, name)
);

alter table public.finance_assets enable row level security;
alter table public.finance_transactions enable row level security;
alter table public.finance_liabilities enable row level security;
alter table public.finance_goals enable row level security;

drop policy if exists "Users manage their own assets" on public.finance_assets;
create policy "Users manage their own assets" on public.finance_assets
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users manage their own transactions" on public.finance_transactions;
create policy "Users manage their own transactions" on public.finance_transactions
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users manage their own liabilities" on public.finance_liabilities;
create policy "Users manage their own liabilities" on public.finance_liabilities
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users manage their own goals" on public.finance_goals;
create policy "Users manage their own goals" on public.finance_goals
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

create index if not exists finance_assets_user_id_idx on public.finance_assets(user_id);
create index if not exists finance_transactions_user_date_idx on public.finance_transactions(user_id, transaction_date desc);
create index if not exists finance_liabilities_user_id_idx on public.finance_liabilities(user_id);
create index if not exists finance_goals_user_id_idx on public.finance_goals(user_id);

-- Important: do not disable RLS or expose a service_role key in frontend code.
