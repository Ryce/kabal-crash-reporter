export interface Env {
  DB: D1Database;
  API_KEY: string;
  ADMIN_TOKEN?: string;
}

type CrashIngestBody = {
  appId: string;
  platform?: string;
  appVersion?: string;
  buildNumber?: string;
  osVersion?: string;
  deviceModel?: string;
  userId?: string;
  title?: string;
  reason?: string;
  stackTrace?: string;
  payload?: unknown;
};

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });

const unauthorized = () => json({ error: "unauthorized" }, 401);

const toIso = () => new Date().toISOString();

async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function getAuthToken(req: Request) {
  return req.headers.get("x-api-key") || "";
}

function makeId(prefix: string) {
  const rand = crypto.getRandomValues(new Uint8Array(8));
  const hex = [...rand].map((b) => b.toString(16).padStart(2, "0")).join("");
  return `${prefix}_${Date.now()}_${hex}`;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/health") return json({ ok: true });

    if (getAuthToken(request) !== env.API_KEY) return unauthorized();

    if (request.method === "POST" && url.pathname === "/v1/crashes") {
      const body = (await request.json()) as CrashIngestBody;
      if (!body?.appId) return json({ error: "appId is required" }, 400);

      const now = toIso();
      const platform = body.platform ?? "ios";
      const fpSource = `${body.appId}|${platform}|${body.title ?? ""}|${body.reason ?? ""}|${body.stackTrace ?? ""}`;
      const fingerprint = await sha256Hex(fpSource);

      const existing = await env.DB
        .prepare("SELECT id, occurrence_count FROM crash_reports WHERE app_id = ?1 AND fingerprint = ?2")
        .bind(body.appId, fingerprint)
        .first<{ id: string; occurrence_count: number }>();

      if (existing) {
        await env.DB
          .prepare(`UPDATE crash_reports SET
            occurrence_count = occurrence_count + 1,
            last_seen_at = ?1,
            updated_at = ?1,
            status = CASE WHEN status = resolved THEN regressed ELSE status END
            WHERE id = ?2`)
          .bind(now, existing.id)
          .run();

        return json({ ok: true, id: existing.id, deduped: true });
      }

      const id = makeId("crash");
      await env.DB
        .prepare(`INSERT INTO crash_reports (
          id, app_id, platform, app_version, build_number, os_version, device_model, user_id,
          fingerprint, title, reason, stack_trace, payload_json, status,
          occurrence_count, first_seen_at, last_seen_at, created_at, updated_at
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, new, 1, ?14, ?14, ?14, ?14)`)
        .bind(
          id,
          body.appId,
          platform,
          body.appVersion ?? null,
          body.buildNumber ?? null,
          body.osVersion ?? null,
          body.deviceModel ?? null,
          body.userId ?? null,
          fingerprint,
          body.title ?? null,
          body.reason ?? null,
          body.stackTrace ?? null,
          JSON.stringify(body.payload ?? null),
          now,
        )
        .run();

      return json({ ok: true, id, deduped: false }, 201);
    }

    if (request.method === "GET" && url.pathname === "/v1/crashes/new") {
      const limit = Math.min(Number(url.searchParams.get("limit") || "20"), 100);
      const appId = url.searchParams.get("appId");

      const query = appId
        ? env.DB.prepare(`SELECT * FROM crash_reports WHERE status IN (new,regressed) AND app_id = ?1 ORDER BY last_seen_at DESC LIMIT ?2`).bind(appId, limit)
        : env.DB.prepare(`SELECT * FROM crash_reports WHERE status IN (new,regressed) ORDER BY last_seen_at DESC LIMIT ?1`).bind(limit);

      const rows = await query.all();
      return json({ ok: true, crashes: rows.results ?? [] });
    }

    if (request.method === "POST" && url.pathname.startsWith("/v1/crashes/") && url.pathname.endsWith("/status")) {
      const crashId = url.pathname.split("/")[3];
      const body = (await request.json()) as { status?: string };
      const status = body.status;
      const allowed = new Set(["new", "triaged", "in_progress", "resolved", "ignored", "regressed"]);
      if (!status || !allowed.has(status)) return json({ error: "invalid status" }, 400);
      await env.DB.prepare("UPDATE crash_reports SET status = ?1, updated_at = ?2 WHERE id = ?3").bind(status, toIso(), crashId).run();
      return json({ ok: true });
    }

    if (request.method === "POST" && url.pathname === "/v1/feedback") {
      const body = (await request.json()) as { appId?: string; crashId?: string; userId?: string; message?: string; payload?: unknown };
      if (!body?.appId || !body?.message) return json({ error: "appId and message are required" }, 400);
      const id = makeId("feedback");
      await env.DB
        .prepare("INSERT INTO crash_feedback (id, crash_id, app_id, user_id, message, payload_json, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)")
        .bind(id, body.crashId ?? null, body.appId, body.userId ?? null, body.message, JSON.stringify(body.payload ?? null), toIso())
        .run();
      return json({ ok: true, id }, 201);
    }

    return json({ error: "not found" }, 404);
  },
};
