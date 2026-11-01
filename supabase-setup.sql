-- Supabase SQL Editor: prototype schema for this demo.
-- WARNING: anon access below is intentionally open because the current app has no Supabase Auth.
-- Do not use this policy setup for a public production game; add Auth and owner/participant RLS first.
create table if not exists public.market_shops (
  id text primary key,
  payload jsonb not null,
  expire_at timestamptz
);
alter table public.market_shops enable row level security;
drop policy if exists "prototype public shop read" on public.market_shops;
drop policy if exists "prototype public shop write" on public.market_shops;
create policy "prototype public shop read" on public.market_shops for select to anon, authenticated using (true);
create policy "prototype public shop write" on public.market_shops for all to anon, authenticated using (true) with check (true);

create table if not exists public.private_messages (
  id bigint generated always as identity primary key,
  conversation_id text not null,
  sender_id text not null,
  sender_name text not null,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists private_messages_conversation_created_idx on public.private_messages (conversation_id, created_at);
alter table public.private_messages enable row level security;
drop policy if exists "prototype public dm read" on public.private_messages;
drop policy if exists "prototype public dm insert" on public.private_messages;
create policy "prototype public dm read" on public.private_messages for select to anon, authenticated using (true);
create policy "prototype public dm insert" on public.private_messages for insert to anon, authenticated with check (true);
alter publication supabase_realtime add table public.private_messages;

-- Shared listing images. Public bucket is used so another visitor can display media URLs.
insert into storage.buckets (id, name, public) values ('market-media', 'market-media', true)
on conflict (id) do update set public = true;
drop policy if exists "prototype market media upload" on storage.objects;
drop policy if exists "prototype market media public read" on storage.objects;
create policy "prototype market media upload" on storage.objects for insert to anon, authenticated with check (bucket_id = 'market-media');
create policy "prototype market media public read" on storage.objects for select to anon, authenticated using (bucket_id = 'market-media');
