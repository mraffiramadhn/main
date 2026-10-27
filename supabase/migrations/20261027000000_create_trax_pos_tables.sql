-- RamaSpace Trax POS schema. Apply with Supabase migration tooling.
create table if not exists public.trax_products (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 name text not null check (char_length(trim(name)) between 1 and 160),
 price numeric(14,2) not null check (price >= 0),
 stock_mode text not null default 'limited' check (stock_mode in ('limited','unlimited')),
 stock integer check (stock is null or stock >= 0),
 description text not null default '',
 active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check ((stock_mode='unlimited' and stock is null) or (stock_mode='limited' and stock is not null))
);
create index if not exists trax_products_owner_idx on public.trax_products(owner_id,created_at desc);
create table if not exists public.trax_payment_methods (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 type text not null check (type in ('cash','qris','bank_transfer')),
 label text not null check (char_length(trim(label)) between 1 and 120),
 details jsonb not null default '{}'::jsonb,
 active boolean not null default true,
 created_at timestamptz not null default now()
);
create index if not exists trax_payments_owner_idx on public.trax_payment_methods(owner_id);
create table if not exists public.trax_sales (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 code text not null,
 status text not null default 'completed' check (status in ('completed','cancelled')),
 payment_type text not null check (payment_type in ('cash','qris','bank_transfer')),
 payment_label text not null,
 total numeric(14,2) not null check (total >= 0),
 received numeric(14,2) not null default 0 check (received >= 0),
 change_amount numeric(14,2) not null default 0 check (change_amount >= 0),
 items jsonb not null default '[]'::jsonb check (jsonb_typeof(items)='array'),
 events jsonb not null default '[]'::jsonb check (jsonb_typeof(events)='array'),
 sold_at timestamptz not null default now(),
 created_at timestamptz not null default now(),
 unique(owner_id,code)
);
create index if not exists trax_sales_owner_sold_idx on public.trax_sales(owner_id,sold_at desc);
alter table public.trax_products enable row level security;
alter table public.trax_payment_methods enable row level security;
alter table public.trax_sales enable row level security;
drop policy if exists "Users manage own Trax products" on public.trax_products;
create policy "Users manage own Trax products" on public.trax_products for all to authenticated using ((select auth.uid())=owner_id) with check ((select auth.uid())=owner_id);
drop policy if exists "Users manage own Trax payment methods" on public.trax_payment_methods;
create policy "Users manage own Trax payment methods" on public.trax_payment_methods for all to authenticated using ((select auth.uid())=owner_id) with check ((select auth.uid())=owner_id);
drop policy if exists "Users manage own Trax sales" on public.trax_sales;
create policy "Users manage own Trax sales" on public.trax_sales for all to authenticated using ((select auth.uid())=owner_id) with check ((select auth.uid())=owner_id);
grant select,insert,update,delete on public.trax_products to authenticated;
grant select,insert,update,delete on public.trax_payment_methods to authenticated;
grant select,insert,update,delete on public.trax_sales to authenticated;