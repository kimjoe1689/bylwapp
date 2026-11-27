import { Hono } from "hono";
import { ADMIN_HTML } from "./admin-page";
import { csvLine, encode, jsonBody, Ordered, Raw } from "./json";
import { summarizeRQ1, summarizeRQ2, summarizeRQ3, summarizeRQ4, type Rate, type RQ1, type RQ2, type RQ4, type SUSResult } from "./metrics";
import { payloadHash, prepare, type MeasureEvent } from "./schema";
import {
  addGroundTruth,
  conflictJSON,
  conflicts,
  counts,
  createUser,
  deviceByToken,
  deviceStatusJSON,
  deviceStatuses,
  ensureAdmin,
  evidence,
  getEvent,
  groundTruthJSON,
  ingest,
  issueDeviceToken,
  issuePairingCode,
  registerDevice,
  listAllEvents,
  listEvents,
  listGroundTruth,
  login,
  ping,
  redeemPairingCode,
  series,
  seriesJSON,
  upsertDevice,
  userByToken,
  type StoredRow,
} from "./store";
import { DEFAULT_STALE_MS, formatRFC3339, parseDuration, parseRFC3339 } from "./time";

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const SESSION_TTL_MS = 12 * 60 * 60 * 1000;
const MAX_BODY = 1 << 20;
const TOKEN_NOTE = "Store this token on the collector. It is not shown again.";

type AppEnv = {
  Bindings: Env;
};

const app = new Hono<AppEnv>();

app.use("*", async (c, next) => {
  if (c.req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS });
  }
  try {
    await ensureAdmin(c.env);
  } catch (err) {
    console.log(JSON.stringify({ level: "error", msg: "bootstrap failed", err: String(err) }));
  }
  await next();
});

app.get("/health", async (c) => {
  try {
    await ping(c.env.DB);
  } catch {
    return json(503, { status: "degraded" });
  }
  return json(200, { status: "ok", time: formatRFC3339(new Date()) });
});

app.all("/", (c) => {
  if (c.req.method !== "GET" && c.req.method !== "HEAD") {
    return text("Method Not Allowed\n", 405, { Allow: "GET" });
  }
  const headers: Record<string, string> = {
    ...CORS,
    "Content-Type": "text/html; charset=utf-8",
    "Cache-Control": "no-cache",
  };
  if (c.req.method === "HEAD") {
    return new Response(null, { status: 200, headers });
  }
  return new Response(ADMIN_HTML, { status: 200, headers });
});

app.post("/api/v1/auth/login", async (c) => {
  const body = await readJSON(c.req.raw);
  if (!body.ok) {
    return json(400, { error: "invalid JSON" });
  }
  const username = typeof body.value.username === "string" ? body.value.username.trim() : "";
  const password = typeof body.value.password === "string" ? body.value.password : "";
  const session = await login(c.env.DB, username, password, SESSION_TTL_MS);
  if (!session) {
    return json(401, { error: "invalid credentials" });
  }
  return json(200, { token: session.token, role: session.user.role, username: session.user.username });
});

app.post("/api/v1/devices/register", async (c) => {
  const body = await readJSON(c.req.raw);
  if (!body.ok) {
    return json(400, { error: "invalid JSON" });
  }
  const requested = typeof body.value.device_id === "string" ? body.value.device_id.trim() : "";
  const deviceID = requested === "" ? `phone-${crypto.randomUUID().replaceAll("-", "")}` : requested;
  if (!/^[A-Za-z0-9._-]{1,128}$/.test(deviceID)) {
    return json(400, { error: "device_id must be a path-safe token" });
  }
  const nameRaw = typeof body.value.name === "string" ? body.value.name.trim() : "";
  const name = nameRaw === "" ? "bylwapp" : nameRaw.slice(0, 80);
  try {
    const issued = await registerDevice(c.env.DB, deviceID, name);
    return json(201, { token: issued.token, device_id: issued.device_id, note: TOKEN_NOTE });
  } catch (err) {
    console.log(JSON.stringify({ level: "error", msg: "register failed", err: String(err) }));
    return json(500, { error: "register failed" });
  }
});

app.post("/api/v1/devices/pair", async (c) => {
  const body = await readJSON(c.req.raw);
  if (!body.ok) {
    return json(400, { error: "invalid JSON" });
  }
  const code = typeof body.value.code === "string" ? body.value.code.trim() : "";
  if (!/^\d{6}$/.test(code)) {
    return json(400, { error: "pairing code rejected" });
  }
  const issued = await redeemPairingCode(c.env.DB, code);
  if (!issued) {
    return json(400, { error: "pairing code rejected" });
  }
  return json(201, { token: issued.token, device_id: issued.device_id, note: TOKEN_NOTE });
});

app.post("/api/v1/devices/:device_id/events", async (c) => {
  const deviceID = await devicePrincipal(c);
  if (deviceID instanceof Response) {
    return deviceID;
  }
  if (c.req.param("device_id") !== deviceID) {
    return json(403, { error: "device token does not match the path" });
  }
  const body = await readJSON(c.req.raw);
  if (!body.ok) {
    return json(400, { error: "invalid JSON" });
  }
  const parsed = parseEvent(body.value.event);
  if (!parsed.ok) {
    return json(400, { error: parsed.error });
  }
  let event: MeasureEvent;
  try {
    event = prepare(parsed.event);
  } catch (err) {
    return json(400, { error: err instanceof Error ? err.message : "invalid event" });
  }
  if (event.device_id !== deviceID) {
    return json(400, { error: "event.device_id does not match the path" });
  }
  let hashed: { hash: string; canonical: string };
  try {
    hashed = await payloadHash(event);
  } catch (err) {
    return json(400, { error: err instanceof Error ? err.message : "invalid event" });
  }
  const presented = typeof body.value.payload_hash === "string" ? body.value.payload_hash : "";
  if (presented.trim().toLowerCase() !== hashed.hash.toLowerCase()) {
    return json(400, { error: "payload_hash does not match the canonical event" });
  }
  try {
    const outcome = await ingest(c.env.DB, event, hashed.hash, hashed.canonical);
    const status = outcome.result === "stored" ? 201 : outcome.result === "duplicate" ? 200 : 409;
    return json(status, {
      result: outcome.result,
      event_id: event.event_id,
      payload_hash: outcome.payload_hash,
      server_received_at: outcome.server_received_at,
    });
  } catch (err) {
    console.log(JSON.stringify({ level: "error", msg: "ingest failed", err: String(err) }));
    return json(500, { error: "ingest failed" });
  }
});

app.get("/api/v1/devices/:device_id/events/:event_id", async (c) => {
  const deviceID = c.req.param("device_id");
  const user = await userIfAny(c);
  if (user) {
    if (user.role !== "admin" && user.role !== "caregiver") {
      return json(403, { error: "forbidden" });
    }
  } else {
    const tokenDevice = await devicePrincipal(c);
    if (tokenDevice instanceof Response) {
      return tokenDevice;
    }
    if (tokenDevice !== deviceID) {
      return json(403, { error: "device token does not match the path" });
    }
  }
  const item = await getEvent(c.env.DB, deviceID, c.req.param("event_id"));
  if (!item) {
    return json(404, { error: "not found" });
  }
  return json(200, {
    result: "stored",
    event: new Raw(item.canonical_json),
    payload_hash: item.payload_hash,
    server_received_at: item.server_received_at,
  });
});

app.get("/api/v1/dashboard/events", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const items = await listEvents(c.env.DB, 100);
  return json(200, {
    note: "最近 100 条是可见性视图，不是丢失清单，也不是论文第四章的结果。",
    events: items.map(storedEventJSON),
  });
});

app.get("/api/v1/dashboard/devices", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const items = await deviceStatuses(c.env.DB, staleAfter(c.env));
  return json(200, items.map(deviceStatusJSON));
});

app.get("/api/v1/dashboard/conflicts", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const items = await conflicts(c.env.DB, 100);
  return json(200, items.map(conflictJSON));
});

app.get("/api/v1/dashboard/series", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const kind = c.req.query("type") ?? "";
  if (kind === "") {
    return json(400, { error: "type is required" });
  }
  const points = await series(c.env.DB, c.req.query("device_id") ?? "", kind, 100);
  return json(200, points.map(seriesJSON));
});

app.get("/api/v1/exports/events.json", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const items = await listAllEvents(c.env.DB);
  return attachment(
    jsonBody({
      note: "Raw server receipt log. Not a Chapter 4 result.",
      events: items.map(storedEventJSON),
    }),
    "application/json; charset=utf-8",
    "events.json",
  );
});

app.get("/api/v1/exports/events.csv", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const items = await listAllEvents(c.env.DB);
  let body = csvLine([
    "server_received_at",
    "device_id",
    "event_id",
    "payload_hash",
    "measurement_type",
    "unit",
    "sensor_address",
    "sensor_kind",
    "sensor_model",
    "monotonic_us",
    "wall_time_utc",
    "clock_state",
    "operating_state",
    "values_json",
  ]);
  for (const item of items) {
    const event = JSON.parse(item.canonical_json) as MeasureEvent;
    body += csvLine([
      item.server_received_at,
      event.device_id,
      event.event_id,
      item.payload_hash,
      event.measurement_type,
      event.unit,
      event.sensor_address,
      event.sensor_kind,
      event.sensor_model,
      String(event.monotonic_us),
      event.wall_time_utc ?? "",
      event.clock_state,
      event.operating_state,
      encode(event.values),
    ]);
  }
  return attachment(body, "text/csv; charset=utf-8", "events.csv");
});

app.get("/api/v1/exports/reconciliation.json", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const tally = await counts(c.env.DB);
  const rows = await conflicts(c.env.DB, 500);
  return json(200, {
    note: "Server-side receipt reconciliation. Duplicate and conflict counts are ingest attempts. This file does not estimate data loss and is not a Chapter 4 result.",
    counts: {
      stored_events: tally.stored,
      duplicate_acks: tally.duplicates,
      conflicts: tally.conflicts,
    },
    conflicts: rows.map(conflictJSON),
  });
});

app.get("/api/v1/exports/rq1.json", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const report = await reports(c.env.DB);
  return json(200, rq1JSON(report.rq1));
});

app.get("/api/v1/exports/rq2.json", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const report = await reports(c.env.DB);
  return json(200, rq2JSON(report.rq2));
});

app.get("/api/v1/exports/rq3.json", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const report = await reports(c.env.DB);
  return json(200, rq3JSON(report.rq3));
});

app.get("/api/v1/exports/rq4.json", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const report = await reports(c.env.DB);
  return json(200, rq4JSON(report.rq4));
});

app.get("/api/v1/ground-truth", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const rows = await listGroundTruth(c.env.DB);
  return json(200, rows.map(groundTruthJSON));
});

app.post("/api/v1/ground-truth", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const body = await readJSON(c.req.raw);
  if (!body.ok) {
    return json(400, { error: "invalid JSON" });
  }
  const parsed = parseGroundTruth(body.value);
  if (!parsed.ok) {
    return json(parsed.status, { error: parsed.error });
  }
  try {
    await addGroundTruth(c.env.DB, parsed.row);
  } catch {
    return json(400, { error: "could not save ground truth" });
  }
  return json(201, { status: "stored" });
});

app.post("/api/v1/ground-truth/import", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const text = await readText(c.req.raw);
  if (!text.ok) {
    return json(400, { error: "invalid CSV" });
  }
  const rows = parseCSV(text.value);
  if (!rows) {
    return json(400, { error: "invalid CSV" });
  }
  let saved = 0;
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    if (i === 0 && row.length > 0 && row[0] === "device_id") {
      continue;
    }
    if (row.length < 6) {
      continue;
    }
    const observed = parseRFC3339(row[4]);
    if (!observed) {
      return json(400, { error: "observed_at must be RFC3339" });
    }
    try {
      await addGroundTruth(c.env.DB, {
        device_id: row[0],
        match_key: row[1],
        reference_type: row[2],
        reference_value: row[3],
        observed_at: formatRFC3339(observed),
        observer: row[5],
        notes: row.length > 6 ? row[6] : "",
      });
    } catch {
      return json(400, { error: "could not import a row" });
    }
    saved++;
  }
  return json(201, { imported: saved });
});

app.post("/api/v1/admin/users", async (c) => {
  const user = await requireAdmin(c);
  if (user instanceof Response) {
    return user;
  }
  const body = await readJSON(c.req.raw);
  if (!body.ok) {
    return json(400, { error: "invalid JSON" });
  }
  const password = typeof body.value.password === "string" ? body.value.password : "";
  const username = typeof body.value.username === "string" ? body.value.username : "";
  const role = typeof body.value.role === "string" ? body.value.role : "";
  if (password.length < 8) {
    return json(400, { error: "password must be at least 8 characters" });
  }
  try {
    await createUser(c.env.DB, username.trim(), password, role);
  } catch {
    return json(400, { error: "could not create user" });
  }
  return json(201, { username, role });
});

app.post("/api/v1/admin/devices", async (c) => {
  const user = await requireAdmin(c);
  if (user instanceof Response) {
    return user;
  }
  const body = await readJSON(c.req.raw);
  if (!body.ok) {
    return json(400, { error: "invalid JSON" });
  }
  const deviceID = typeof body.value.device_id === "string" ? body.value.device_id : "";
  const name = typeof body.value.name === "string" ? body.value.name : "";
  try {
    await upsertDevice(c.env.DB, deviceID.trim(), name.trim());
  } catch {
    return json(400, { error: "could not save device" });
  }
  return json(201, { device_id: deviceID, name });
});

app.post("/api/v1/admin/devices/:device_id/tokens", async (c) => {
  const user = await requireAdmin(c);
  if (user instanceof Response) {
    return user;
  }
  const token = await issueDeviceToken(c.env.DB, c.req.param("device_id"));
  if (!token) {
    return json(404, { error: "device not found" });
  }
  return json(201, { token, note: TOKEN_NOTE });
});

app.post("/api/v1/admin/devices/:device_id/pairing-codes", async (c) => {
  const user = await requireAdmin(c);
  if (user instanceof Response) {
    return user;
  }
  const deviceID = c.req.param("device_id");
  try {
    const issued = await issuePairingCode(c.env.DB, deviceID);
    if (!issued) {
      return json(404, { error: "device not found" });
    }
    return json(201, { code: issued.code, device_id: deviceID, expires_at: issued.expires_at, ttl_seconds: 600 });
  } catch (err) {
    console.log(JSON.stringify({ level: "error", msg: "pairing code failed", err: String(err) }));
    return json(500, { error: "pairing code failed" });
  }
});

app.notFound(() => text("404 page not found\n", 404));

app.onError((err) => {
  console.log(JSON.stringify({ level: "error", msg: "unhandled", err: err.message }));
  return json(500, { error: "internal error" });
});

export default app;

function json(status: number, value: unknown): Response {
  return new Response(jsonBody(value), {
    status,
    headers: { ...CORS, "Content-Type": "application/json; charset=utf-8" },
  });
}

function text(body: string, status: number, extra?: Record<string, string>): Response {
  return new Response(body, {
    status,
    headers: { ...CORS, "Content-Type": "text/plain; charset=utf-8", ...extra },
  });
}

function attachment(body: string, contentType: string, filename: string): Response {
  return new Response(body, {
    status: 200,
    headers: {
      ...CORS,
      "Content-Type": contentType,
      "Content-Disposition": `attachment; filename="${filename}"`,
    },
  });
}

function bearer(request: Request): string {
  const value = request.headers.get("Authorization") ?? "";
  const prefix = "Bearer ";
  if (!value.startsWith(prefix)) {
    return "";
  }
  return value.slice(prefix.length).trim();
}

async function readText(request: Request): Promise<{ ok: true; value: string } | { ok: false }> {
  const declared = request.headers.get("content-length");
  if (declared && Number(declared) > MAX_BODY) {
    return { ok: false };
  }
  const textBody = await request.text();
  if (textBody.length > MAX_BODY) {
    return { ok: false };
  }
  return { ok: true, value: textBody };
}

async function readJSON(request: Request): Promise<{ ok: true; value: Record<string, unknown> } | { ok: false }> {
  const textBody = await readText(request);
  if (!textBody.ok) {
    return { ok: false };
  }
  if (textBody.value.trim() === "") {
    return { ok: true, value: {} };
  }
  try {
    const parsed = JSON.parse(textBody.value) as unknown;
    if (parsed === null) {
      return { ok: true, value: {} };
    }
    if (typeof parsed !== "object" || Array.isArray(parsed)) {
      return { ok: false };
    }
    return { ok: true, value: parsed as Record<string, unknown> };
  } catch {
    return { ok: false };
  }
}

async function userIfAny(c: { env: Env; req: { raw: Request } }): Promise<{ role: string } | null> {
  const token = bearer(c.req.raw);
  if (!token) {
    return null;
  }
  const user = await userByToken(c.env.DB, token);
  return user ? { role: user.role } : null;
}

async function requireUser(c: { env: Env; req: { raw: Request } }): Promise<{ role: string } | Response> {
  const user = await userIfAny(c);
  if (!user) {
    return json(401, { error: "login required" });
  }
  return user;
}

async function requireAdmin(c: { env: Env; req: { raw: Request } }): Promise<{ role: string } | Response> {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  if (user.role !== "admin") {
    return json(403, { error: "admin required" });
  }
  return user;
}

async function devicePrincipal(c: { env: Env; req: { raw: Request } }): Promise<string | Response> {
  const token = bearer(c.req.raw);
  if (!token) {
    return json(401, { error: "device token required" });
  }
  const deviceID = await deviceByToken(c.env.DB, token);
  if (!deviceID) {
    return json(401, { error: "device token rejected" });
  }
  return deviceID;
}

function staleAfter(env: Env): number {
  if (!env.STALE_AFTER) {
    return DEFAULT_STALE_MS;
  }
  return parseDuration(env.STALE_AFTER) ?? DEFAULT_STALE_MS;
}

function optionalString(value: unknown): string | null {
  if (value === undefined || value === null) {
    return "";
  }
  return typeof value === "string" ? value : null;
}

function parseEvent(raw: unknown): { ok: true; event: MeasureEvent } | { ok: false; error: string } {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return { ok: false, error: "invalid JSON" };
  }
  const source = raw as Record<string, unknown>;
  const eventID = optionalString(source.event_id);
  const deviceID = optionalString(source.device_id);
  const sessionID = optionalString(source.session_id);
  const sensorAddress = optionalString(source.sensor_address);
  const sensorKind = optionalString(source.sensor_kind);
  const sensorModel = optionalString(source.sensor_model);
  const measurementType = optionalString(source.measurement_type);
  const unit = optionalString(source.unit);
  const clockState = optionalString(source.clock_state);
  const operatingState = optionalString(source.operating_state);
  const schemaVersion = optionalString(source.schema_version);
  if (
    eventID === null ||
    deviceID === null ||
    sessionID === null ||
    sensorAddress === null ||
    sensorKind === null ||
    sensorModel === null ||
    measurementType === null ||
    unit === null ||
    clockState === null ||
    operatingState === null ||
    schemaVersion === null
  ) {
    return { ok: false, error: "invalid JSON" };
  }
  let monotonic = 0;
  if (source.monotonic_us !== undefined && source.monotonic_us !== null) {
    if (typeof source.monotonic_us !== "number" || !Number.isInteger(source.monotonic_us)) {
      return { ok: false, error: "invalid JSON" };
    }
    monotonic = source.monotonic_us;
  }
  let wall: string | null = null;
  if (source.wall_time_utc !== undefined && source.wall_time_utc !== null) {
    if (typeof source.wall_time_utc !== "string") {
      return { ok: false, error: "invalid JSON" };
    }
    wall = source.wall_time_utc;
  }
  let values: Record<string, unknown> = {};
  if (source.values !== undefined && source.values !== null) {
    if (typeof source.values !== "object" || Array.isArray(source.values)) {
      return { ok: false, error: "invalid JSON" };
    }
    values = source.values as Record<string, unknown>;
  }
  return {
    ok: true,
    event: {
      schema_version: schemaVersion,
      event_id: eventID,
      device_id: deviceID,
      session_id: sessionID,
      sensor_address: sensorAddress,
      sensor_kind: sensorKind,
      sensor_model: sensorModel,
      measurement_type: measurementType,
      unit,
      monotonic_us: monotonic,
      wall_time_utc: wall,
      clock_state: clockState,
      operating_state: operatingState,
      values,
    },
  };
}

function parseGroundTruth(
  body: Record<string, unknown>,
): { ok: true; row: { device_id: string; match_key: string; reference_type: string; reference_value: string; observed_at: string; observer: string; notes: string } } | { ok: false; status: number; error: string } {
  const deviceID = optionalString(body.device_id);
  const matchKey = optionalString(body.match_key);
  const referenceType = optionalString(body.reference_type);
  const referenceValue = optionalString(body.reference_value);
  const observer = optionalString(body.observer);
  const notes = optionalString(body.notes);
  if (deviceID === null || matchKey === null || referenceType === null || referenceValue === null || observer === null || notes === null) {
    return { ok: false, status: 400, error: "invalid JSON" };
  }
  let observed = formatRFC3339(new Date());
  if (body.observed_at !== undefined && body.observed_at !== null && body.observed_at !== "") {
    if (typeof body.observed_at !== "string") {
      return { ok: false, status: 400, error: "invalid JSON" };
    }
    if (body.observed_at !== "0001-01-01T00:00:00Z") {
      const parsed = parseRFC3339(body.observed_at);
      if (!parsed) {
        return { ok: false, status: 400, error: "invalid JSON" };
      }
      observed = formatRFC3339(parsed);
    }
  }
  if (deviceID === "" || matchKey === "" || referenceType === "" || observer === "") {
    return { ok: false, status: 400, error: "device_id, match_key, reference_type, and observer are required" };
  }
  return {
    ok: true,
    row: {
      device_id: deviceID,
      match_key: matchKey,
      reference_type: referenceType,
      reference_value: referenceValue,
      observed_at: observed,
      observer,
      notes,
    },
  };
}

function parseCSV(text: string): string[][] | null {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          quoted = false;
        }
      } else {
        field += ch;
      }
      continue;
    }
    if (ch === '"') {
      quoted = true;
      continue;
    }
    if (ch === ",") {
      row.push(field);
      field = "";
      continue;
    }
    if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && text[i + 1] === "\n") {
        i++;
      }
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
      continue;
    }
    field += ch;
  }
  if (quoted) {
    return null;
  }
  if (field.length > 0 || row.length > 0) {
    row.push(field);
    rows.push(row);
  }
  return rows;
}

function storedEventJSON(row: StoredRow): Ordered {
  const event = JSON.parse(row.canonical_json) as MeasureEvent;
  return new Ordered([
    ["event", eventStruct(event)],
    ["payload_hash", row.payload_hash],
    ["canonical_json", row.canonical_json],
    ["server_received_at", row.server_received_at],
  ]);
}

function eventStruct(event: MeasureEvent): Ordered {
  return new Ordered([
    ["schema_version", event.schema_version],
    ["event_id", event.event_id],
    ["device_id", event.device_id],
    ["session_id", event.session_id],
    ["sensor_address", event.sensor_address],
    ["sensor_kind", event.sensor_kind],
    ["sensor_model", event.sensor_model],
    ["measurement_type", event.measurement_type],
    ["unit", event.unit],
    ["monotonic_us", event.monotonic_us],
    ["wall_time_utc", event.wall_time_utc],
    ["clock_state", event.clock_state],
    ["operating_state", event.operating_state],
    ["values", event.values],
  ]);
}

function rateJSON(rate: Rate): Ordered {
  const entries: Array<[string, unknown]> = [
    ["status", rate.status],
    ["value", rate.value],
    ["numerator", rate.numerator],
    ["denominator", rate.denominator],
  ];
  if (rate.reason) {
    entries.push(["reason", rate.reason]);
  }
  return new Ordered(entries);
}

function rq1JSON(report: RQ1): Ordered {
  return new Ordered([
    ["note", report.note],
    ["device_journal", report.device_journal],
    ["observer", report.observer],
    ["ack_rate", rateJSON(report.ack_rate)],
    ["miss_rate", rateJSON(report.miss_rate)],
    ["delivery_rate", rateJSON(report.delivery_rate)],
  ]);
}

function rq2JSON(report: RQ2): Ordered {
  return new Ordered([
    ["note", report.note],
    ["confusion", report.confusion],
    ["unmatched_ground_truth", report.unmatched_ground_truth],
    ["recall", rateJSON(report.recall)],
    ["specificity", rateJSON(report.specificity)],
  ]);
}

function rq3JSON(report: ReturnType<typeof summarizeRQ3>): Ordered {
  return new Ordered([
    ["note", report.note],
    ["stored_events", report.stored_events],
    ["duplicate_acks", report.duplicate_acks],
    ["conflicts", report.conflicts],
    ["duplicate_attempt_rate", rateJSON(report.duplicate_attempt_rate)],
    ["pending_on_server", report.pending_on_server],
  ]);
}

function susJSON(item: SUSResult): Ordered {
  const entries: Array<[string, unknown]> = [
    ["device_id", item.device_id],
    ["match_key", item.match_key],
    ["score", item.score],
    ["status", item.status],
  ];
  if (item.reason) {
    entries.push(["reason", item.reason]);
  }
  return new Ordered(entries);
}

function rq4JSON(report: RQ4): Ordered {
  return new Ordered([
    ["note", report.note],
    ["task_dispositions", report.task_dispositions],
    ["sus", report.sus.map(susJSON)],
  ]);
}

async function reports(db: D1Database): Promise<{ rq1: RQ1; rq2: RQ2; rq3: ReturnType<typeof summarizeRQ3>; rq4: RQ4 }> {
  const found = await evidence(db);
  const tally = await counts(db);
  return {
    rq1: summarizeRQ1(found.events, found.ledger),
    rq2: summarizeRQ2(found.events, found.ledger),
    rq3: summarizeRQ3(tally.stored, tally.duplicates, tally.conflicts),
    rq4: summarizeRQ4(found.events),
  };
}
