import { hashPassword, randomPairingCode, randomToken, sha256Hex, verifyPassword } from "./crypto";
import { encode, Ordered } from "./json";
import type { EventView, LedgerRow } from "./metrics";
import type { MeasureEvent } from "./schema";
import { nowNano, parseGoTime } from "./time";

export interface UserRow {
  id: number;
  username: string;
  role: string;
}

export interface IngestOutcome {
  result: "stored" | "duplicate" | "conflict";
  payload_hash: string;
  server_received_at: string;
}

export interface StoredRow {
  canonical_json: string;
  payload_hash: string;
  server_received_at: string;
}

export interface DeviceStatus {
  device_id: string;
  name: string;
  last_received_at: string | null;
  stale: boolean;
  operating_state: string;
  sensor_address: string;
  sensor_kind: string;
  sensor_model: string;
  open_conflicts: number;
  duplicate_acks: number;
  event_count: number;
}

export interface ConflictRow {
  device_id: string;
  event_id: string;
  stored_hash: string;
  presented_hash: string;
  at: string;
}

export interface SeriesPoint {
  at: string;
  value: number;
  label: string;
}

export interface GroundTruth {
  id: number;
  device_id: string;
  match_key: string;
  reference_type: string;
  reference_value: string;
  observed_at: string;
  observer: string;
  notes: string;
}

function num(value: unknown): number {
  return typeof value === "number" ? value : Number(value ?? 0);
}

export async function ping(db: D1Database): Promise<void> {
  await db.prepare("SELECT 1 AS ok").first();
}

export async function countUsers(db: D1Database): Promise<number> {
  const row = await db.prepare("SELECT COUNT(1) AS n FROM users").first<{ n: number }>();
  return num(row?.n);
}

export async function ensureAdmin(env: { DB: D1Database; BOOTSTRAP_ADMIN_USER?: string; BOOTSTRAP_ADMIN_PASSWORD?: string }): Promise<void> {
  const existing = await countUsers(env.DB);
  if (existing > 0) {
    return;
  }
  const username = env.BOOTSTRAP_ADMIN_USER ?? "";
  const password = env.BOOTSTRAP_ADMIN_PASSWORD ?? "";
  if (username === "" || password.length < 8) {
    return;
  }
  try {
    await createUser(env.DB, username, password, "admin");
    console.log(JSON.stringify({ level: "info", msg: "bootstrapped admin", username }));
  } catch (err) {
    const again = await countUsers(env.DB);
    if (again === 0) {
      throw err;
    }
  }
}

export async function createUser(db: D1Database, username: string, password: string, role: string): Promise<void> {
  if (role !== "admin" && role !== "caregiver") {
    throw new Error("invalid role");
  }
  const passwordHash = await hashPassword(password);
  await db
    .prepare("INSERT INTO users(username, password_hash, role, created_at) VALUES (?, ?, ?, ?)")
    .bind(username, passwordHash, role, nowNano())
    .run();
}

export async function login(
  db: D1Database,
  username: string,
  password: string,
  ttlMs: number,
): Promise<{ token: string; user: UserRow } | null> {
  const row = await db
    .prepare("SELECT id, username, role, password_hash FROM users WHERE username = ?")
    .bind(username)
    .first<{ id: number; username: string; role: string; password_hash: string }>();
  if (!row || !(await verifyPassword(password, row.password_hash))) {
    return null;
  }
  const token = randomToken();
  const tokenHash = await sha256Hex(token);
  const expires = nowNano(new Date(Date.now() + ttlMs));
  await db
    .prepare("INSERT INTO sessions(token_hash, user_id, expires_at) VALUES (?, ?, ?)")
    .bind(tokenHash, row.id, expires)
    .run();
  return { token, user: { id: row.id, username: row.username, role: row.role } };
}

export async function userByToken(db: D1Database, token: string): Promise<UserRow | null> {
  const row = await db
    .prepare(
      `SELECT u.id AS id, u.username AS username, u.role AS role, s.expires_at AS expires_at
       FROM sessions s JOIN users u ON u.id = s.user_id
       WHERE s.token_hash = ?`,
    )
    .bind(await sha256Hex(token))
    .first<{ id: number; username: string; role: string; expires_at: string }>();
  if (!row) {
    return null;
  }
  const exp = parseGoTime(row.expires_at);
  if (!exp || Date.now() > exp.getTime()) {
    return null;
  }
  return { id: row.id, username: row.username, role: row.role };
}

export async function upsertDevice(db: D1Database, id: string, name: string): Promise<void> {
  await db
    .prepare(
      `INSERT INTO devices(device_id, name, created_at) VALUES (?, ?, ?)
       ON CONFLICT(device_id) DO UPDATE SET name = excluded.name`,
    )
    .bind(id, name, nowNano())
    .run();
}

export async function issueDeviceToken(db: D1Database, deviceID: string): Promise<string | null> {
  const row = await db.prepare("SELECT COUNT(1) AS n FROM devices WHERE device_id = ?").bind(deviceID).first<{ n: number }>();
  if (num(row?.n) === 0) {
    return null;
  }
  const token = randomToken();
  await db
    .prepare("INSERT INTO device_tokens(token_hash, device_id, created_at) VALUES (?, ?, ?)")
    .bind(await sha256Hex(token), deviceID, nowNano())
    .run();
  return token;
}

export async function deviceByToken(db: D1Database, token: string): Promise<string | null> {
  const row = await db
    .prepare("SELECT device_id, revoked_at FROM device_tokens WHERE token_hash = ?")
    .bind(await sha256Hex(token))
    .first<{ device_id: string; revoked_at: string | null }>();
  if (!row || row.revoked_at) {
    return null;
  }
  return row.device_id;
}

export async function issuePairingCode(db: D1Database, deviceID: string): Promise<{ code: string; expires_at: string } | null> {
  const row = await db.prepare("SELECT COUNT(1) AS n FROM devices WHERE device_id = ?").bind(deviceID).first<{ n: number }>();
  if (num(row?.n) === 0) {
    return null;
  }
  const created = nowNano();
  const expires = nowNano(new Date(Date.now() + 10 * 60 * 1000));
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = randomPairingCode();
    try {
      await db
        .prepare("INSERT INTO pairing_codes(code, device_id, expires_at, created_at) VALUES (?, ?, ?, ?)")
        .bind(code, deviceID, expires, created)
        .run();
      return { code, expires_at: expires };
    } catch (err) {
      const message = String(err);
      if (!message.toLowerCase().includes("unique")) {
        throw err;
      }
    }
  }
  throw new Error("pairing code collision");
}

export async function redeemPairingCode(db: D1Database, code: string): Promise<{ token: string; device_id: string } | null> {
  const row = await db
    .prepare("SELECT device_id, expires_at, used_at FROM pairing_codes WHERE code = ?")
    .bind(code)
    .first<{ device_id: string; expires_at: string; used_at: string | null }>();
  if (!row || row.used_at) {
    return null;
  }
  const exp = parseGoTime(row.expires_at);
  if (!exp || Date.now() > exp.getTime()) {
    return null;
  }
  const token = randomToken();
  const usedAt = nowNano();
  const updated = await db
    .prepare("UPDATE pairing_codes SET used_at = ? WHERE code = ? AND used_at IS NULL")
    .bind(usedAt, code)
    .run();
  if (num(updated.meta?.changes) !== 1) {
    return null;
  }
  try {
    await db
      .prepare("INSERT INTO device_tokens(token_hash, device_id, created_at) VALUES (?, ?, ?)")
      .bind(await sha256Hex(token), row.device_id, usedAt)
      .run();
  } catch (err) {
    await db.prepare("UPDATE pairing_codes SET used_at = NULL WHERE code = ? AND used_at = ?").bind(code, usedAt).run();
    throw err;
  }
  return { token, device_id: row.device_id };
}

export async function ingest(db: D1Database, event: MeasureEvent, hash: string, canonical: string): Promise<IngestOutcome> {
  const existing = await db
    .prepare("SELECT payload_hash, server_received_at FROM events WHERE device_id = ? AND event_id = ?")
    .bind(event.device_id, event.event_id)
    .first<{ payload_hash: string; server_received_at: string }>();
  if (!existing) {
    const received = nowNano();
    const valuesJSON = encode(event.values);
    try {
      await db.batch([
        db
          .prepare(
            `INSERT INTO events(device_id, event_id, payload_hash, canonical_json, server_received_at,
              measurement_type, unit, sensor_address, sensor_kind, sensor_model, monotonic_us,
              wall_time_utc, clock_state, operating_state, values_json)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          )
          .bind(
            event.device_id,
            event.event_id,
            hash,
            canonical,
            received,
            event.measurement_type,
            event.unit,
            event.sensor_address,
            event.sensor_kind,
            event.sensor_model,
            event.monotonic_us,
            event.wall_time_utc,
            event.clock_state,
            event.operating_state,
            valuesJSON,
          ),
        db
          .prepare(
            `INSERT INTO ingest_log(device_id, event_id, result, presented_hash, stored_hash, at)
             VALUES (?, ?, 'stored', ?, ?, ?)`,
          )
          .bind(event.device_id, event.event_id, hash, hash, received),
      ]);
      return { result: "stored", payload_hash: hash, server_received_at: received };
    } catch (err) {
      const again = await db
        .prepare("SELECT payload_hash, server_received_at FROM events WHERE device_id = ? AND event_id = ?")
        .bind(event.device_id, event.event_id)
        .first<{ payload_hash: string; server_received_at: string }>();
      if (!again) {
        throw err;
      }
      return replay(db, event, hash, again.payload_hash, again.server_received_at);
    }
  }
  return replay(db, event, hash, existing.payload_hash, existing.server_received_at);
}

async function replay(
  db: D1Database,
  event: MeasureEvent,
  hash: string,
  storedHash: string,
  received: string,
): Promise<IngestOutcome> {
  const result = storedHash === hash ? "duplicate" : "conflict";
  const at = nowNano();
  await db
    .prepare(
      `INSERT INTO ingest_log(device_id, event_id, result, presented_hash, stored_hash, at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    )
    .bind(event.device_id, event.event_id, result, hash, storedHash, at)
    .run();
  return { result, payload_hash: storedHash, server_received_at: received };
}

export async function getEvent(db: D1Database, deviceID: string, eventID: string): Promise<StoredRow | null> {
  return db
    .prepare("SELECT canonical_json, payload_hash, server_received_at FROM events WHERE device_id = ? AND event_id = ?")
    .bind(deviceID, eventID)
    .first<StoredRow>();
}

export async function listEvents(db: D1Database, limit: number): Promise<StoredRow[]> {
  const capped = limit <= 0 || limit > 500 ? 100 : limit;
  const rows = await db
    .prepare(
      `SELECT canonical_json, payload_hash, server_received_at
       FROM events ORDER BY server_received_at DESC, event_id DESC LIMIT ?`,
    )
    .bind(capped)
    .all<StoredRow>();
  return rows.results;
}

export async function listAllEvents(db: D1Database): Promise<StoredRow[]> {
  const rows = await db
    .prepare(
      `SELECT canonical_json, payload_hash, server_received_at
       FROM events ORDER BY server_received_at ASC, event_id ASC`,
    )
    .all<StoredRow>();
  return rows.results;
}

export async function deviceStatuses(db: D1Database, staleMs: number): Promise<DeviceStatus[]> {
  const devices = await db.prepare("SELECT device_id, name FROM devices ORDER BY device_id").all<{ device_id: string; name: string }>();
  const out: DeviceStatus[] = [];
  for (const device of devices.results) {
    const status: DeviceStatus = {
      device_id: device.device_id,
      name: device.name,
      last_received_at: null,
      stale: true,
      operating_state: "",
      sensor_address: "",
      sensor_kind: "",
      sensor_model: "",
      open_conflicts: 0,
      duplicate_acks: 0,
      event_count: 0,
    };
    const latest = await db
      .prepare(
        `SELECT server_received_at, operating_state, sensor_address, sensor_kind, sensor_model
         FROM events WHERE device_id = ? ORDER BY server_received_at DESC LIMIT 1`,
      )
      .bind(device.device_id)
      .first<{
        server_received_at: string;
        operating_state: string;
        sensor_address: string;
        sensor_kind: string;
        sensor_model: string;
      }>();
    if (latest) {
      status.last_received_at = latest.server_received_at;
      const at = parseGoTime(latest.server_received_at);
      status.stale = !at || Date.now() - at.getTime() > staleMs;
      status.operating_state = latest.operating_state;
      status.sensor_address = latest.sensor_address;
      status.sensor_kind = latest.sensor_kind;
      status.sensor_model = latest.sensor_model;
    }
    status.event_count = num(
      (await db.prepare("SELECT COUNT(1) AS n FROM events WHERE device_id = ?").bind(device.device_id).first<{ n: number }>())?.n,
    );
    status.open_conflicts = num(
      (
        await db
          .prepare("SELECT COUNT(1) AS n FROM ingest_log WHERE device_id = ? AND result = 'conflict'")
          .bind(device.device_id)
          .first<{ n: number }>()
      )?.n,
    );
    status.duplicate_acks = num(
      (
        await db
          .prepare("SELECT COUNT(1) AS n FROM ingest_log WHERE device_id = ? AND result = 'duplicate'")
          .bind(device.device_id)
          .first<{ n: number }>()
      )?.n,
    );
    out.push(status);
  }
  return out;
}

export function deviceStatusJSON(status: DeviceStatus): Ordered {
  return new Ordered([
    ["device_id", status.device_id],
    ["name", status.name],
    ["last_received_at", status.last_received_at],
    ["stale", status.stale],
    ["operating_state", status.operating_state],
    ["sensor_address", status.sensor_address],
    ["sensor_kind", status.sensor_kind],
    ["sensor_model", status.sensor_model],
    ["open_conflicts", status.open_conflicts],
    ["duplicate_acks", status.duplicate_acks],
    ["event_count", status.event_count],
  ]);
}

export async function conflicts(db: D1Database, limit: number): Promise<ConflictRow[]> {
  const capped = limit <= 0 ? 100 : limit;
  const rows = await db
    .prepare(
      `SELECT device_id, event_id, stored_hash, presented_hash, at
       FROM ingest_log WHERE result = 'conflict' ORDER BY id DESC LIMIT ?`,
    )
    .bind(capped)
    .all<ConflictRow>();
  return rows.results;
}

export function conflictJSON(row: ConflictRow): Ordered {
  return new Ordered([
    ["device_id", row.device_id],
    ["event_id", row.event_id],
    ["stored_hash", row.stored_hash],
    ["presented_hash", row.presented_hash],
    ["at", row.at],
  ]);
}

function seriesValue(kind: string, values: Record<string, unknown>): { value: number; label: string } {
  const asFloat = (value: unknown) => (typeof value === "number" && Number.isFinite(value) ? value : 0);
  switch (kind) {
    case "blood_pressure":
      return { value: asFloat(values.systolic), label: "systolic" };
    case "heart_rate":
      return { value: asFloat(values.bpm), label: "bpm" };
    case "spo2":
      return { value: asFloat(values.spo2), label: "spo2" };
    case "temperature":
      return { value: asFloat(values.celsius), label: "celsius" };
    case "steps":
      return { value: asFloat(values.steps), label: "steps" };
    case "stress":
      return { value: asFloat(values.stress), label: "stress" };
    case "hrv":
      return { value: asFloat(values.hrv_ms), label: "hrv_ms" };
    default:
      return { value: 0, label: "" };
  }
}

export async function series(db: D1Database, deviceID: string, measurementType: string, limit: number): Promise<SeriesPoint[]> {
  const capped = limit <= 0 || limit > 500 ? 100 : limit;
  const query = deviceID
    ? `SELECT server_received_at, values_json, measurement_type FROM events WHERE measurement_type = ? AND device_id = ? ORDER BY server_received_at DESC LIMIT ?`
    : `SELECT server_received_at, values_json, measurement_type FROM events WHERE measurement_type = ? ORDER BY server_received_at DESC LIMIT ?`;
  const stmt = deviceID
    ? db.prepare(query).bind(measurementType, deviceID, capped)
    : db.prepare(query).bind(measurementType, capped);
  const rows = await stmt.all<{ server_received_at: string; values_json: string; measurement_type: string }>();
  return rows.results.map((row) => {
    let payload: Record<string, unknown> = {};
    try {
      const parsed = JSON.parse(row.values_json) as unknown;
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        payload = parsed as Record<string, unknown>;
      }
    } catch {
      payload = {};
    }
    const point = seriesValue(row.measurement_type, payload);
    return { at: row.server_received_at, value: point.value, label: point.label };
  });
}

export function seriesJSON(point: SeriesPoint): Ordered {
  return new Ordered([
    ["at", point.at],
    ["value", point.value],
    ["label", point.label],
  ]);
}

export async function counts(db: D1Database): Promise<{ stored: number; duplicates: number; conflicts: number }> {
  const stored = num((await db.prepare("SELECT COUNT(1) AS n FROM events").first<{ n: number }>())?.n);
  const duplicates = num(
    (await db.prepare("SELECT COUNT(1) AS n FROM ingest_log WHERE result = 'duplicate'").first<{ n: number }>())?.n,
  );
  const conflictCount = num(
    (await db.prepare("SELECT COUNT(1) AS n FROM ingest_log WHERE result = 'conflict'").first<{ n: number }>())?.n,
  );
  return { stored, duplicates, conflicts: conflictCount };
}

export async function addGroundTruth(
  db: D1Database,
  row: Omit<GroundTruth, "id"> & { observed_at: string },
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO ground_truth(device_id, match_key, reference_type, reference_value, observed_at, observer, notes, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(row.device_id, row.match_key, row.reference_type, row.reference_value, row.observed_at, row.observer, row.notes, nowNano())
    .run();
}

export async function listGroundTruth(db: D1Database): Promise<GroundTruth[]> {
  const rows = await db
    .prepare(
      `SELECT id, device_id, match_key, reference_type, reference_value, observed_at, observer, notes
       FROM ground_truth ORDER BY id`,
    )
    .all<GroundTruth>();
  return rows.results;
}

export function groundTruthJSON(row: GroundTruth): Ordered {
  return new Ordered([
    ["id", row.id],
    ["device_id", row.device_id],
    ["match_key", row.match_key],
    ["reference_type", row.reference_type],
    ["reference_value", row.reference_value],
    ["observed_at", row.observed_at],
    ["observer", row.observer],
    ["notes", row.notes],
  ]);
}

export async function evidence(db: D1Database): Promise<{ events: EventView[]; ledger: LedgerRow[] }> {
  const rows = await db
    .prepare("SELECT device_id, measurement_type, monotonic_us, values_json FROM events ORDER BY rowid")
    .all<{ device_id: string; measurement_type: string; monotonic_us: number; values_json: string }>();
  const events: EventView[] = rows.results.map((row) => {
    let values: Record<string, unknown> = {};
    try {
      const parsed = JSON.parse(row.values_json) as unknown;
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        values = parsed as Record<string, unknown>;
      }
    } catch {
      values = {};
    }
    return {
      device_id: row.device_id,
      measurement_type: row.measurement_type,
      monotonic_us: num(row.monotonic_us),
      values,
    };
  });
  const ledgerRows = await listGroundTruth(db);
  const ledger = ledgerRows.map((row) => ({
    device_id: row.device_id,
    match_key: row.match_key,
    reference_type: row.reference_type,
    reference_value: row.reference_value,
  }));
  return { events, ledger };
}
