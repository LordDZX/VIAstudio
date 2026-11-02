import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const cronSecret = Deno.env.get("EXPIRE_SHOPS_CRON_SECRET");
const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}");
const serviceKey = secretKeys.default || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !serviceKey || !cronSecret) {
  throw new Error("Missing Supabase URL, server secret key, or expiry cron secret.");
}

const admin = createClient(supabaseUrl, serviceKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

function collectCloudMediaKeys(value: unknown, keys = new Set<string>()): Set<string> {
  if (Array.isArray(value)) {
    value.forEach((item) => collectCloudMediaKeys(item, keys));
  } else if (value && typeof value === "object") {
    const object = value as Record<string, unknown>;
    const publicUrl = typeof object.publicURL === "string" ? object.publicURL : "";
    if (
      typeof object.mediaKey === "string" &&
      /^[A-Za-z0-9_-]{1,240}$/.test(object.mediaKey) &&
      publicUrl.startsWith(supabaseUrl + "/storage/v1/object/public/market-media/")
    ) {
      keys.add(object.mediaKey);
    }
    Object.values(object).forEach((item) => collectCloudMediaKeys(item, keys));
  }
  return keys;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return Response.json({ error: "POST required" }, { status: 405 });
  if (request.headers.get("authorization") !== "Bearer " + cronSecret) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { data: expiredRows, error: claimError } = await admin.rpc("claim_expired_market_shops", {
    p_limit: 100,
  });
  if (claimError) {
    console.error("Could not claim expired storefronts", claimError);
    return Response.json({ error: "Could not claim expired storefronts" }, { status: 500 });
  }

  let cleaned = 0;
  let failed = 0;
  for (const row of expiredRows || []) {
    const expiresAt = row.expire_at as string;
    const ownerId = row.owner_id || row.payload?.lease?.ownerId;
    const keys = [...collectCloudMediaKeys(row.payload)];
    const paths = ownerId ? keys.map((key) => String(ownerId) + "/" + key) : [];

    try {
      if (keys.length && !ownerId) throw new Error("Expired shop has media but no owner folder.");
      for (let i = 0; i < paths.length; i += 1000) {
        const { error } = await admin.storage.from("market-media").remove(paths.slice(i, i + 1000));
        if (error) throw error;
      }
      const { data: finalized, error: finalizeError } = await admin.rpc("finalize_expired_market_shop", {
        p_shop_id: row.id,
        p_expire_at: expiresAt,
      });
      if (finalizeError) throw finalizeError;
      if (finalized) cleaned++;
    } catch (error) {
      failed++;
      console.error("Expired storefront cleanup failed", row.id, error);
      const { error: releaseError } = await admin.rpc("release_expired_market_shop", {
        p_shop_id: row.id,
        p_expire_at: expiresAt,
      });
      if (releaseError) console.error("Could not release expired storefront claim", row.id, releaseError);
    }
  }

  return Response.json({ claimed: expiredRows?.length || 0, cleaned, failed });
});
