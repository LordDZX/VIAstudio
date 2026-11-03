-- Existing shops may already overlap. Keep overlap validation for new shops
-- and coordinate changes, but allow unrelated payload edits (music, contact,
-- listings) when the stored position does not change.
begin;

drop trigger if exists market_shops_no_overlap on public.market_shops;
drop trigger if exists market_shops_no_overlap_insert on public.market_shops;
drop trigger if exists market_shops_no_overlap_position_update on public.market_shops;

create trigger market_shops_no_overlap_insert
before insert on public.market_shops
for each row execute function public.enforce_market_shop_non_overlap();

create trigger market_shops_no_overlap_position_update
before update of payload on public.market_shops
for each row
when ((old.payload -> 'position') is distinct from (new.payload -> 'position'))
execute function public.enforce_market_shop_non_overlap();

commit;
