-- Existing-project migration: run in Supabase SQL Editor after reviewing.
-- Does not change or delete existing shop data.

-- Speeds up the query used by lease-expiry cleanup.
create index if not exists market_shops_expire_at_idx
  on public.market_shops (expire_at)
  where expire_at is not null;

-- Count only images actually stored in this project's Storage bucket.
-- Supports current product.media[] records and older product-level mediaKey records.
create or replace function public.market_shop_uploaded_image_count(p_payload jsonb)
returns integer
language sql
immutable
set search_path = public
as $$
  select (
    select count(*)::integer
    from jsonb_array_elements(
      case when jsonb_typeof(p_payload->'products') = 'array'
        then p_payload->'products' else '[]'::jsonb end
    ) as products(product)
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(product->'media') = 'array'
        then product->'media' else '[]'::jsonb end
    ) as media_items(media)
    where media->>'mediaKey' is not null
      and coalesce(media->>'publicURL', '') like '%/storage/v1/object/public/market-media/%'
  ) + (
    select count(*)::integer
    from jsonb_array_elements(
      case when jsonb_typeof(p_payload->'products') = 'array'
        then p_payload->'products' else '[]'::jsonb end
    ) as products(product)
    where case when jsonb_typeof(product->'media') = 'array'
      then jsonb_array_length(product->'media') = 0 else true end
      and product->>'mediaKey' is not null
      and coalesce(product->>'publicURL', '') like '%/storage/v1/object/public/market-media/%'
  );
$$;

-- Existing shops above five images are grandfathered: they may remove or replace
-- images, but a write cannot increase their stored-image count further.
create or replace function public.enforce_market_shop_image_limit()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  new_count integer;
  old_count integer := 0;
begin
  new_count := public.market_shop_uploaded_image_count(new.payload);
  if tg_op = 'UPDATE' then
    old_count := public.market_shop_uploaded_image_count(old.payload);
  end if;

  if new_count > 5 and new_count > old_count then
    raise exception 'MARKET_SHOP_IMAGE_LIMIT: a shop may store at most five uploaded images'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists market_shops_image_limit on public.market_shops;
create trigger market_shops_image_limit
before insert or update of payload on public.market_shops
for each row execute function public.enforce_market_shop_image_limit();
