-- Goodminton — run this ONCE in Supabase: SQL Editor → New query → paste → Run.

-- 1) Who is an admin
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.admins enable row level security;
-- (no policies on purpose: nobody can read or edit this list through the API)

create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$ select exists (select 1 from public.admins where user_id = auth.uid()) $$;

-- 2) Starting money / stock (one row only)
create table if not exists public.settings (
  id int primary key default 1 check (id = 1),
  opening_cash bigint not null default 0 check (opening_cash >= 0),
  opening_shuttles int not null default 0 check (opening_shuttles >= 0)
);
alter table public.settings add column if not exists fee int not null default 30000 check (fee >= 0);  -- price per player
insert into public.settings (id) values (1) on conflict do nothing;

-- 3) Every game day / court bill / shuttlecock bill
create table if not exists public.entries (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('game','court','shuttle')),
  date date not null,
  players int check (players >= 1),
  collected bigint check (collected >= 0),
  shuttles_used int check (shuttles_used >= 0),
  extra_courts int check (extra_courts >= 0),
  extra_cost bigint check (extra_cost >= 0),
  tubes int check (tubes >= 1),
  amount bigint check (amount >= 0),
  notes text,
  receipt_path text,
  created_at timestamptz not null default now(),
  constraint entry_shape check (
    (type = 'game'   and players is not null and collected is not null and shuttles_used is not null
                     and extra_courts is not null and extra_cost is not null)
 or (type = 'court'  and amount is not null)
 or (type = 'shuttle' and tubes is not null and amount is not null)
  )
);
create index if not exists entries_date_idx on public.entries (date desc);

-- 3b) Who played in each game, and whether they have paid
create table if not exists public.attendees (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references public.entries(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  paid boolean not null default false,
  cash boolean not null default false,
  paid_on date,
  created_at timestamptz not null default now()
);
create index if not exists attendees_entry_idx on public.attendees (entry_id);
-- keeps players in sign-up order (new players get a higher number)
create sequence if not exists public.attendees_pos_seq start 100000;
alter table public.attendees add column if not exists pos bigint;
alter table public.attendees alter column pos set default nextval('public.attendees_pos_seq');
grant usage on sequence public.attendees_pos_seq to authenticated;

-- 4) Security: everyone can READ, only admins can WRITE
alter table public.entries  enable row level security;
alter table public.settings enable row level security;
alter table public.attendees enable row level security;

drop policy if exists "anyone can read entries"  on public.entries;
drop policy if exists "admins write entries"     on public.entries;
drop policy if exists "anyone can read attendees" on public.attendees;
drop policy if exists "admins write attendees"    on public.attendees;
drop policy if exists "anyone can read settings" on public.settings;
drop policy if exists "admins update settings"   on public.settings;

create policy "anyone can read entries"  on public.entries  for select using (true);
create policy "admins write entries"     on public.entries  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy "anyone can read attendees" on public.attendees for select using (true);
create policy "admins write attendees"    on public.attendees for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy "anyone can read settings" on public.settings for select using (true);
create policy "admins update settings"   on public.settings for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- 5) Receipt / photo storage
-- Public bucket = anyone with the app can view receipts. Admins only can upload/delete.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', true, 3145728, array['image/jpeg','image/png','application/pdf'])
on conflict (id) do nothing;

drop policy if exists "admins manage receipts" on storage.objects;
create policy "admins manage receipts" on storage.objects for all to authenticated
  using (bucket_id = 'receipts' and public.is_admin())
  with check (bucket_id = 'receipts' and public.is_admin());

-- 6) Make yourself admin (do this AFTER creating your user in Authentication → Users)
-- Replace the email, then run just this line:
-- insert into public.admins (user_id) select id from auth.users where email = 'YOUR_EMAIL_HERE';
