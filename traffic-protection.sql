-- Existing-project migration: run in Supabase SQL Editor after reviewing.
-- Does not change or delete existing shop data.

-- Speeds up the query used by lease-expiry cleanup.
create index if not exists market_shops_expire_at_idx
  on public.market_shops (expire_at)
  where expire_at is not null;

-- Retire the old per-shop uploaded-image quota on existing projects.
drop trigger if exists market_shops_image_limit on public.market_shops;
drop function if exists public.enforce_market_shop_image_limit();
drop function if exists public.market_shop_uploaded_image_count(jsonb);
