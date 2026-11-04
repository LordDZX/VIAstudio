-- Remove the retired five-image aggregate limit from existing Supabase projects.
-- This does not delete or modify any shop or image data.

begin;

drop trigger if exists market_shops_image_limit on public.market_shops;
drop function if exists public.enforce_market_shop_image_limit();
drop function if exists public.market_shop_uploaded_image_count(jsonb);

commit;
