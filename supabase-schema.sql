-- KLB STORE production database schema (Supabase/PostgreSQL)
-- Run in Supabase SQL Editor after creating a project.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  role text not null default 'user' check (role in ('user','seller','admin')),
  status text not null default 'active' check (status in ('active','blocked')),
  bio text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.seller_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  nickname text not null,
  description text not null,
  benefit text not null,
  age integer not null check (age between 1 and 100),
  telegram text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  description text not null,
  category text not null,
  price numeric(12,2) not null check (price >= 0),
  image_url text,
  status text not null default 'pending' check (status in ('pending','active','rejected','paused','sold')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references public.profiles(id),
  seller_id uuid not null references public.profiles(id),
  product_id uuid references public.products(id) on delete set null,
  product_title text not null,
  amount numeric(12,2) not null check (amount >= 0),
  status text not null default 'created' check (status in ('created','paid','in_progress','completed','cancelled','disputed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.favorites (
  user_id uuid not null references public.profiles(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, product_id)
);

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id) on delete cascade,
  buyer_id uuid not null references public.profiles(id),
  seller_id uuid not null references public.profiles(id),
  rating integer not null check (rating between 1 and 5),
  comment text not null default '',
  created_at timestamptz not null default now()
);

-- Username is used as the login identifier in the frontend. A synthetic email
-- is mapped from the username; email confirmation must be disabled for this flow.
create or replace function public.username_to_auth_email(p_username text)
returns text language sql immutable as $$
  select lower(regexp_replace(trim(p_username), '[^a-zA-Z0-9_]', '', 'g')) || '@login.klbstore.invalid';
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare uname text;
begin
  uname := trim(coalesce(new.raw_user_meta_data->>'username', ''));
  if length(uname) < 3 then uname := split_part(new.email, '@', 1); end if;
  insert into public.profiles(id, username) values (new.id, uname)
  on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Prevent clients from changing role/status. Admins are assigned through SQL/service role.
create or replace function public.protect_profile_privileges()
returns trigger language plpgsql as $$
begin
  if (new.role is distinct from old.role or new.status is distinct from old.status)
     and coalesce(auth.role(), '') <> 'service_role' and not public.is_admin() then
    raise exception 'role/status changes are restricted';
  end if;
  return new;
end;
$$;
drop trigger if exists protect_profile_privileges_trigger on public.profiles;
create trigger protect_profile_privileges_trigger before update on public.profiles
for each row execute function public.protect_profile_privileges();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin' and p.status = 'active');
$$;
create or replace function public.is_seller()
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles p where p.id = auth.uid() and p.role in ('seller','admin') and p.status = 'active');
$$;

alter table public.profiles enable row level security;
alter table public.seller_applications enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.favorites enable row level security;
alter table public.reviews enable row level security;

-- Profiles: public username/profile; owner can edit non-privileged fields; admin can manage.
drop policy if exists profiles_public_read on public.profiles;
create policy profiles_public_read on public.profiles for select using (true);
drop policy if exists profiles_owner_update on public.profiles;
create policy profiles_owner_update on public.profiles for update using (id = auth.uid() or public.is_admin()) with check (id = auth.uid() or public.is_admin());

-- Seller applications: applicant creates/reads their own; admin reviews.
drop policy if exists seller_applications_insert_self on public.seller_applications;
create policy seller_applications_insert_self on public.seller_applications for insert with check (user_id = auth.uid());
drop policy if exists seller_applications_read on public.seller_applications;
create policy seller_applications_read on public.seller_applications for select using (user_id = auth.uid() or public.is_admin());
drop policy if exists seller_applications_admin_update on public.seller_applications;
create policy seller_applications_admin_update on public.seller_applications for update using (public.is_admin()) with check (public.is_admin());

-- Products: public sees approved active listings; seller owns their listings; admins manage all.
drop policy if exists products_read on public.products;
create policy products_read on public.products for select using (status = 'active' or seller_id = auth.uid() or public.is_admin());
drop policy if exists products_insert_seller on public.products;
create policy products_insert_seller on public.products for insert with check (seller_id = auth.uid() and public.is_seller());
drop policy if exists products_update_owner_admin on public.products;
create policy products_update_owner_admin on public.products for update using (seller_id = auth.uid() or public.is_admin()) with check (seller_id = auth.uid() or public.is_admin());
drop policy if exists products_delete_owner_admin on public.products;
create policy products_delete_owner_admin on public.products for delete using (seller_id = auth.uid() or public.is_admin());

-- Orders: buyer creates only for active product; participants/admin read; admin and seller can update status.
drop policy if exists orders_read_participants on public.orders;
create policy orders_read_participants on public.orders for select using (buyer_id = auth.uid() or seller_id = auth.uid() or public.is_admin());
drop policy if exists orders_insert_buyer on public.orders;
create policy orders_insert_buyer on public.orders for insert with check (buyer_id = auth.uid() and exists(select 1 from public.products p where p.id = product_id and p.status = 'active'));
drop policy if exists orders_update_participants on public.orders;
create policy orders_update_participants on public.orders for update using (seller_id = auth.uid() or public.is_admin()) with check (seller_id = auth.uid() or public.is_admin());

-- Favorites are private to the owner.
drop policy if exists favorites_owner_all on public.favorites;
create policy favorites_owner_all on public.favorites for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Reviews visible publicly; buyer can leave a review for completed order.
drop policy if exists reviews_read_public on public.reviews;
create policy reviews_read_public on public.reviews for select using (true);
drop policy if exists reviews_insert_completed_order on public.reviews;
create policy reviews_insert_completed_order on public.reviews for insert with check (buyer_id = auth.uid() and exists(select 1 from public.orders o where o.id = order_id and o.buyer_id = auth.uid() and o.status = 'completed'));

-- Bootstrap administrator after the user has signed up:
-- UPDATE public.profiles SET role='admin' WHERE username='Kolobok';
