/**
 * Kabal Crash Reporter - Cloudflare Worker
 * 
 * Receives crash reports from iOS and backend, stores in D1
 */

interface CrashReport {
  platform: 'ios' | 'backend';
  app_version: string;
  error_name: string;
  message?: string;
  stack_trace?: string;
  user_id?: string;
  device_info?: Record<string, unknown>;
  context?: Record<string, unknown>;
}

interface Env {
  DB: D1Database;
  API_SECRET: string;
}

function authenticate(request: Request, env: Env): Response | null {
  const apiKey = request.headers.get('X-API-Key');
  
  if (!apiKey || apiKey !== env.API_SECRET) {
    return new Response(
      JSON.stringify({ error: 'Unauthorized' }),
      { status: 401, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } }
    );
  }
  return null;
}

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: CORS_HEADERS });
    }

    const url = new URL(request.url);

    // POST /crashes - Submit a new crash report (auth required)
    if (request.method === 'POST' && url.pathname === '/crashes') {
      const authError = authenticate(request, env);
      if (authError) return authError;
      return handleCrashSubmit(request, env);
    }

    // GET /crashes - List crashes (for dashboard/debugging)
    if (request.method === 'GET' && url.pathname === '/crashes') {
      return handleCrashList(request, env);
    }

    // GET /crashes/new - Get new crashes (for cron, auth required)
    if (request.method === 'GET' && url.pathname === '/crashes/new') {
      const authError = authenticate(request, env);
      if (authError) return authError;
      return handleNewCrashes(request, env);
    }

    // PATCH /crashes/:id - Update crash status (auth required)
    if (request.method === 'PATCH' && url.pathname.startsWith('/crashes/')) {
      const authError = authenticate(request, env);
      if (authError) return authError;
      return handleCrashUpdate(request, env);
    }

    // Health check
    if (url.pathname === '/health') {
      return new Response(JSON.stringify({ status: 'ok' }), {
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    return new Response('Not Found', { status: 404, headers: CORS_HEADERS });
  },
};

async function handleCrashSubmit(request: Request, env: Env): Promise<Response> {
  try {
    const body: CrashReport = await request.json();

    // Validate required fields
    if (!body.platform || !body.app_version || !body.error_name) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: platform, app_version, error_name' }),
        { status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } }
      );
    }

    const timestamp = Math.floor(Date.now() / 1000);

    const result = await env.DB.prepare(
      `INSERT INTO crashes (platform, app_version, error_name, message, stack_trace, user_id, device_info, context, timestamp)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).bind(
      body.platform,
      body.app_version,
      body.error_name,
      body.message || null,
      body.stack_trace || null,
      body.user_id || null,
      body.device_info ? JSON.stringify(body.device_info) : null,
      body.context ? JSON.stringify(body.context) : null,
      timestamp
    ).run();

    return new Response(
      JSON.stringify({ success: true, id: result.meta.last_row_id }),
      { status: 201, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } }
    );
  } catch (e) {
    console.error('Error submitting crash:', e);
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } }
    );
  }
}

async function handleCrashList(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const status = url.searchParams.get('status');
  const platform = url.searchParams.get('platform');
  const limit = Math.min(parseInt(url.searchParams.get('limit') || '50'), 100);

  let query = 'SELECT * FROM crashes';
  const conditions: string[] = [];
  const bindings: unknown[] = [];

  if (status) {
    conditions.push('status = ?');
    bindings.push(status);
  }
  if (platform) {
    conditions.push('platform = ?');
    bindings.push(platform);
  }

  if (conditions.length > 0) {
    query += ' WHERE ' + conditions.join(' AND ');
  }

  query += ' ORDER BY timestamp DESC LIMIT ?';
  bindings.push(limit);

  const result = await env.DB.prepare(query).bind(...bindings).all();

  return new Response(JSON.stringify(result.results), {
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

async function handleNewCrashes(request: Request, env: Env): Promise<Response> {
  const result = await env.DB.prepare(
    'SELECT * FROM crashes WHERE status = ? ORDER BY timestamp DESC LIMIT 50'
  ).bind('new').all();

  return new Response(JSON.stringify(result.results), {
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

async function handleCrashUpdate(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const id = url.pathname.split('/').pop();
  
  if (!id || isNaN(parseInt(id))) {
    return new Response(JSON.stringify({ error: 'Invalid crash ID' }), {
      status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' }
    });
  }

  try {
    const body = await request.json();
    const updates: string[] = [];
    const bindings: unknown[] = [];

    if (body.status) {
      updates.push('status = ?');
      bindings.push(body.status);
    }
    if (body.fix_commit) {
      updates.push('fix_commit = ?');
      bindings.push(body.fix_commit);
    }
    if (body.fix_pr_url) {
      updates.push('fix_pr_url = ?');
      bindings.push(body.fix_pr_url);
    }
    if (body.notes) {
      updates.push('notes = ?');
      bindings.push(body.notes);
    }

    if (updates.length === 0) {
      return new Response(JSON.stringify({ error: 'No fields to update' }), {
        status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' }
      });
    }

    updates.push('updated_at = unixepoch()');
    bindings.push(id);

    await env.DB.prepare(
      `UPDATE crashes SET ${updates.join(', ')} WHERE id = ?`
    ).bind(...bindings).run();

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    console.error('Error updating crash:', e);
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' }
    });
  }
}
