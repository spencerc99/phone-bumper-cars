import { Hono } from 'hono';
import { cors } from 'hono/cors';

type Bindings = {
  DB: D1Database;
};

const app = new Hono<{ Bindings: Bindings }>();

app.use('*', cors());

// GET /shows — return all active shows
app.get('/shows', async (c) => {
  const { results } = await c.env.DB.prepare(
    'SELECT id, name, lat, lng, radius_meters FROM shows WHERE active = 1'
  ).all();
  return c.json({ shows: results });
});

// POST /users — create a user
app.post('/users', async (c) => {
  const body = await c.req.json<{ display_name: string }>();
  const id = crypto.randomUUID();
  const created_at = new Date().toISOString();
  // Generate a random color
  const color = '#' + Math.floor(Math.random() * 0xffffff).toString(16).padStart(6, '0');

  await c.env.DB.prepare(
    'INSERT INTO users (id, display_name, color, created_at) VALUES (?, ?, ?, ?)'
  ).bind(id, body.display_name, color, created_at).run();

  return c.json({ id, display_name: body.display_name, color, created_at }, 201);
});

// POST /trails — start a new trail
app.post('/trails', async (c) => {
  const body = await c.req.json<{ show_id: string; user_id: string }>();
  const id = crypto.randomUUID();
  const started_at = new Date().toISOString();

  await c.env.DB.prepare(
    'INSERT INTO trails (id, show_id, user_id, started_at) VALUES (?, ?, ?, ?)'
  ).bind(id, body.show_id, body.user_id, started_at).run();

  return c.json({ id, show_id: body.show_id, user_id: body.user_id, started_at, ended_at: null }, 201);
});

// POST /trails/:id/points — batch insert points
app.post('/trails/:id/points', async (c) => {
  const trailId = c.req.param('id');
  const body = await c.req.json<{ points: { lat: number; lng: number; recorded_at: string }[] }>();

  if (!body.points || body.points.length === 0) {
    return c.json({ error: 'No points provided' }, 400);
  }

  const stmt = c.env.DB.prepare(
    'INSERT INTO points (trail_id, lat, lng, recorded_at) VALUES (?, ?, ?, ?)'
  );

  const batch = body.points.map((p) =>
    stmt.bind(trailId, p.lat, p.lng, p.recorded_at)
  );

  await c.env.DB.batch(batch);

  return c.json({ inserted: body.points.length });
});

// POST /trails/:id/finish — mark trail as finished
app.post('/trails/:id/finish', async (c) => {
  const trailId = c.req.param('id');
  const ended_at = new Date().toISOString();

  await c.env.DB.prepare(
    'UPDATE trails SET ended_at = ? WHERE id = ?'
  ).bind(ended_at, trailId).run();

  const trail = await c.env.DB.prepare(
    'SELECT id, show_id, user_id, started_at, ended_at FROM trails WHERE id = ?'
  ).bind(trailId).first();

  if (!trail) {
    return c.json({ error: 'Trail not found' }, 404);
  }

  return c.json(trail);
});

// GET /trails?show_id=X — return all trails for a show with nested points
app.get('/trails', async (c) => {
  const showId = c.req.query('show_id');
  if (!showId) {
    return c.json({ error: 'show_id query parameter is required' }, 400);
  }

  const { results: trails } = await c.env.DB.prepare(
    `SELECT t.id, t.user_id, u.display_name AS user_display_name, u.color AS user_color,
            t.started_at, t.ended_at
     FROM trails t
     JOIN users u ON t.user_id = u.id
     WHERE t.show_id = ?
     ORDER BY t.started_at`
  ).bind(showId).all();

  // Fetch points for all trails in one batch
  const trailIds = trails.map((t: any) => t.id as string);

  const trailsWithPoints = [];
  if (trailIds.length > 0) {
    const placeholders = trailIds.map(() => '?').join(',');
    const { results: allPoints } = await c.env.DB.prepare(
      `SELECT trail_id, lat, lng, recorded_at FROM points
       WHERE trail_id IN (${placeholders})
       ORDER BY recorded_at`
    ).bind(...trailIds).all();

    // Group points by trail_id
    const pointsByTrail = new Map<string, any[]>();
    for (const p of allPoints) {
      const tid = p.trail_id as string;
      if (!pointsByTrail.has(tid)) {
        pointsByTrail.set(tid, []);
      }
      pointsByTrail.get(tid)!.push({
        lat: p.lat,
        lng: p.lng,
        recorded_at: p.recorded_at,
      });
    }

    for (const t of trails) {
      trailsWithPoints.push({
        id: t.id,
        user_id: t.user_id,
        user_display_name: t.user_display_name,
        user_color: t.user_color,
        started_at: t.started_at,
        ended_at: t.ended_at,
        points: pointsByTrail.get(t.id as string) || [],
      });
    }
  }

  return c.json({ trails: trailsWithPoints });
});

export default app;
