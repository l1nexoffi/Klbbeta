-- KLB STORE wallet, manual payments and seller listings (Supabase)
-- Run only after the existing profiles table and public.is_admin() are installed.
-- This migration creates server-side balance operations; do not credit balances from browser code.

create extension if not exists pgcrypto;

create table if not exists public.wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  available numeric(14,2) not null default 0 check (available >= 0),
  reserved numeric(14,2) not null default 0 check (reserved >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.wallet_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  operation text not null check (operation in ('deposit','withdrawal_reserve','withdrawal_refund','withdrawal_paid','purchase','sale','adjustment')),
  amount numeric(14,2) not null,
  reference_id uuid,
  note text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.deposit_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount numeric(14,2) not null check (amount between 100 and 1000000),
  comment_code char(5) not null,
  status text not null default 'pending' check (status in ('pending','checking','approved','rejected','expired')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id),
  unique(comment_code)
);

create table if not exists public.withdrawal_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  method text not null check (method in ('bank_phone','usdt_trc20')),
  bank_name text,
  phone text,
  crypto_address text,
  amount numeric(14,2) not null check (amount >= 500),
  status text not null default 'pending' check (status in ('pending','paid','rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id),
  check ((method='bank_phone' and bank_name is not null and phone is not null and crypto_address is null)
      or (method='usdt_trc20' and crypto_address is not null and bank_name is null and phone is null))
);

create table if not exists public.wallet_payment_settings (
  id boolean primary key default true check (id),
  deposit_bank text not null default '',
  deposit_card text not null default '',
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

insert into public.wallet_payment_settings(id) values(true) on conflict(id) do nothing;

create table if not exists public.seller_listings (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  description text not null,
  category text not null,
  price numeric(14,2) not null check (price > 0),
  stock integer not null default 1 check (stock > 0),
  image_url text,
  status text not null default 'pending' check (status in ('pending','active','rejected','paused')),
  moderation_note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.wallets enable row level security;
alter table public.wallet_ledger enable row level security;
alter table public.deposit_requests enable row level security;
alter table public.withdrawal_requests enable row level security;
alter table public.wallet_payment_settings enable row level security;
alter table public.seller_listings enable row level security;

drop policy if exists wallets_read_self_or_admin on public.wallets;
create policy wallets_read_self_or_admin on public.wallets for select using (user_id=auth.uid() or public.is_admin());
drop policy if exists ledger_read_self_or_admin on public.wallet_ledger;
create policy ledger_read_self_or_admin on public.wallet_ledger for select using (user_id=auth.uid() or public.is_admin());
drop policy if exists deposits_read_self_or_admin on public.deposit_requests;
create policy deposits_read_self_or_admin on public.deposit_requests for select using (user_id=auth.uid() or public.is_admin());
drop policy if exists withdrawals_read_self_or_admin on public.withdrawal_requests;
create policy withdrawals_read_self_or_admin on public.withdrawal_requests for select using (user_id=auth.uid() or public.is_admin());
drop policy if exists settings_admin_only on public.wallet_payment_settings;
create policy settings_admin_only on public.wallet_payment_settings for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists listings_public_active_or_owner_admin on public.seller_listings;
create policy listings_public_active_or_owner_admin on public.seller_listings for select using (status='active' or seller_id=auth.uid() or public.is_admin());
drop policy if exists listings_seller_insert on public.seller_listings;
create policy listings_seller_insert on public.seller_listings for insert with check (seller_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='seller'));
drop policy if exists listings_seller_update on public.seller_listings;
create policy listings_seller_update on public.seller_listings for update using (seller_id=auth.uid() or public.is_admin()) with check (seller_id=auth.uid() or public.is_admin());
drop policy if exists listings_seller_delete on public.seller_listings;
create policy listings_seller_delete on public.seller_listings for delete using (seller_id=auth.uid() or public.is_admin());

-- User creates a deposit request; code is generated server-side and unique.
create or replace function public.create_deposit_request(p_amount numeric)
returns public.deposit_requests language plpgsql security definer set search_path=public as $$
declare r public.deposit_requests; c char(5);
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_amount < 100 or p_amount > 1000000 then raise exception 'Invalid amount'; end if;
  loop c := lpad((floor(random()*90000)+10000)::text,5,'0'); exit when not exists(select 1 from public.deposit_requests where comment_code=c); end loop;
  insert into public.deposit_requests(user_id,amount,comment_code) values(auth.uid(),p_amount,c) returning * into r;
  return r;
end $$;

-- User requests withdrawal. Amount is reserved atomically.
create or replace function public.create_withdrawal_request(p_method text,p_amount numeric,p_bank text default null,p_phone text default null,p_address text default null)
returns public.withdrawal_requests language plpgsql security definer set search_path=public as $$
declare r public.withdrawal_requests; w public.wallets;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_amount < 500 then raise exception 'Minimum withdrawal is 500'; end if;
  if p_method not in ('bank_phone','usdt_trc20') then raise exception 'Unsupported method'; end if;
  if p_method='bank_phone' and (coalesce(trim(p_bank),'')='' or coalesce(trim(p_phone),'')='') then raise exception 'Bank and phone required'; end if;
  if p_method='usdt_trc20' and (coalesce(trim(p_address),'')='' or p_address !~ '^T[1-9A-HJ-NP-Za-km-z]{33}$') then raise exception 'Invalid TRC20 address'; end if;
  insert into public.wallets(user_id) values(auth.uid()) on conflict(user_id) do nothing;
  update public.wallets set available=available-p_amount,reserved=reserved+p_amount,updated_at=now() where user_id=auth.uid() and available>=p_amount returning * into w;
  if not found then raise exception 'Insufficient balance'; end if;
  insert into public.withdrawal_requests(user_id,method,bank_name,phone,crypto_address,amount) values(auth.uid(),p_method,p_bank,p_phone,p_address,p_amount) returning * into r;
  insert into public.wallet_ledger(user_id,operation,amount,reference_id,note) values(auth.uid(),'withdrawal_reserve',-p_amount,r.id,'Funds reserved for withdrawal');
  return r;
end $$;

create or replace function public.admin_review_deposit(p_request uuid,p_approve boolean)
returns void language plpgsql security definer set search_path=public as $$
declare d public.deposit_requests; begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  select * into d from public.deposit_requests where id=p_request for update;
  if not found or d.status not in ('pending','checking') then raise exception 'Request unavailable'; end if;
  update public.deposit_requests set status=case when p_approve then 'approved' else 'rejected' end,reviewed_at=now(),reviewed_by=auth.uid() where id=p_request;
  if p_approve then
    insert into public.wallets(user_id,available) values(d.user_id,d.amount) on conflict(user_id) do update set available=wallets.available+excluded.available,updated_at=now();
    insert into public.wallet_ledger(user_id,operation,amount,reference_id,note) values(d.user_id,'deposit',d.amount,d.id,'Deposit confirmed by administrator');
  end if;
end $$;

create or replace function public.admin_review_withdrawal(p_request uuid,p_paid boolean)
returns void language plpgsql security definer set search_path=public as $$
declare r public.withdrawal_requests; begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  select * into r from public.withdrawal_requests where id=p_request for update;
  if not found or r.status<>'pending' then raise exception 'Request unavailable'; end if;
  if p_paid then
    update public.wallets set reserved=reserved-r.amount,updated_at=now() where user_id=r.user_id and reserved>=r.amount;
    update public.withdrawal_requests set status='paid',reviewed_at=now(),reviewed_by=auth.uid() where id=p_request;
    insert into public.wallet_ledger(user_id,operation,amount,reference_id,note) values(r.user_id,'withdrawal_paid',-r.amount,r.id,'Withdrawal marked paid');
  else
    update public.wallets set available=available+r.amount,reserved=reserved-r.amount,updated_at=now() where user_id=r.user_id and reserved>=r.amount;
    update public.withdrawal_requests set status='rejected',reviewed_at=now(),reviewed_by=auth.uid() where id=p_request;
    insert into public.wallet_ledger(user_id,operation,amount,reference_id,note) values(r.user_id,'withdrawal_refund',r.amount,r.id,'Withdrawal rejected; funds returned');
  end if;
end $$;

revoke all on function public.create_deposit_request(numeric) from public;
revoke all on function public.create_withdrawal_request(text,numeric,text,text,text) from public;
revoke all on function public.admin_review_deposit(uuid,boolean) from public;
revoke all on function public.admin_review_withdrawal(uuid,boolean) from public;
grant execute on function public.create_deposit_request(numeric) to authenticated;
grant execute on function public.create_withdrawal_request(text,numeric,text,text,text) to authenticated;
grant execute on function public.admin_review_deposit(uuid,boolean) to authenticated;
grant execute on function public.admin_review_withdrawal(uuid,boolean) to authenticated;

-- Authenticated users may read transfer instructions, but cannot change them.
create or replace function public.get_deposit_instructions()
returns table(bank text, card_or_details text)
language sql security definer set search_path=public as $$
  select deposit_bank, deposit_card from public.wallet_payment_settings where id=true;
$$;
revoke all on function public.get_deposit_instructions() from public;
grant execute on function public.get_deposit_instructions() to authenticated;

-- Admin-only seller promotion/revocation. Applications are reviewed separately in the admin UI.
create or replace function public.admin_set_seller(p_user uuid,p_approved boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  update public.profiles set role=case when p_approved then 'seller' else 'user' end where id=p_user;
  if not found then raise exception 'Profile not found'; end if;
end $$;
revoke all on function public.admin_set_seller(uuid,boolean) from public;
grant execute on function public.admin_set_seller(uuid,boolean) to authenticated;
