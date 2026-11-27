import { env, SELF } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { payloadHash, prepare, type MeasureEvent } from "../src/schema";

const origin = "https://bylw-api.zzjteacher.com";

async function call(method: string, path: string, body?: unknown, token = "") {
  const headers = new Headers();
  if (body !== undefined) {
    headers.set("Content-Type", "application/json");
  }
  if (token) {
    headers.set("Authorization", `Bearer ${token}`);
  }
  const response = await SELF.fetch(origin + path, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  const type = response.headers.get("content-type") ?? "";
  let json: unknown = null;
  if (type.includes("json") && text) {
    json = JSON.parse(text);
  }
  return { status: response.status, text, json, headers: response.headers };
}

function sample(overrides: Partial<MeasureEvent> = {}): MeasureEvent {
  return prepare({
    schema_version: "",
    event_id: "evt-0001",
    device_id: "phone-1",
    session_id: "sess-1",
    sensor_address: "AA-BB-CC-DD-EE-01",
    sensor_kind: "blood_pressure",
    sensor_model: "Yuwell YE680B",
    measurement_type: "blood_pressure",
    unit: "mmHg",
    monotonic_us: 1000,
    wall_time_utc: "2026-11-27T08:15:09Z",
    clock_state: "NTP_SYNCED",
    operating_state: "NOMINAL",
    values: { systolic: 120, diastolic: 80, pulse: 72 },
    ...overrides,
  });
}

async function login(username: string, password: string): Promise<string> {
  const res = await call("POST", "/api/v1/auth/login", { username, password });
  expect(res.status, res.text).toBe(200);
  return (res.json as { token: string }).token;
}

async function reset(): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM ingest_log"),
    env.DB.prepare("DELETE FROM events"),
    env.DB.prepare("DELETE FROM ground_truth"),
    env.DB.prepare("DELETE FROM pairing_codes"),
    env.DB.prepare("DELETE FROM device_tokens"),
    env.DB.prepare("DELETE FROM sessions"),
    env.DB.prepare("DELETE FROM devices"),
    env.DB.prepare("DELETE FROM users"),
  ]);
}

beforeEach(async () => {
  await reset();
});

describe("Go API contract", () => {
  it("answers health, CORS, and the admin page", async () => {
    const health = await call("GET", "/health");
    expect(health.status).toBe(200);
    expect(health.headers.get("access-control-allow-origin")).toBe("*");
    expect(health.headers.get("content-type")).toContain("application/json");
    expect(health.text.endsWith("\n")).toBe(true);
    const body = health.json as { status: string; time: string };
    expect(body.status).toBe("ok");
    expect(body.time).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);

    const options = await call("OPTIONS", "/api/v1/auth/login");
    expect(options.status).toBe(204);
    expect(options.headers.get("access-control-allow-headers")).toBe("Authorization, Content-Type");
    expect(options.headers.get("access-control-allow-methods")).toBe("GET, POST, OPTIONS");

    const page = await call("GET", "/");
    expect(page.status).toBe(200);
    expect(page.text).toContain("管理后台");
    expect(page.headers.get("content-type")).toContain("text/html");
  });

  it("keeps the first receipt and separates device and caregiver roles", async () => {
    const admin = await login("admin", "admin-pass-1");
    const created = await call("POST", "/api/v1/admin/users", { username: "care", password: "care-pass-1", role: "caregiver" }, admin);
    expect(created.status).toBe(201);
    const care = await login("care", "care-pass-1");
    const device = await call("POST", "/api/v1/admin/devices", { device_id: "phone-1", name: "采集手机" }, admin);
    expect(device.status).toBe(201);
    const tokenRes = await call("POST", "/api/v1/admin/devices/phone-1/tokens", {}, admin);
    expect(tokenRes.status).toBe(201);
    const deviceToken = (tokenRes.json as { token: string; note: string }).token;
    expect((tokenRes.json as { note: string }).note).toContain("not shown again");

    const event = sample();
    const hashed = await payloadHash(event);
    const first = await call("POST", "/api/v1/devices/phone-1/events", { event, payload_hash: hashed.hash }, deviceToken);
    expect(first.status, first.text).toBe(201);
    expect(first.text).toContain('"stored"');
    const dup = await call("POST", "/api/v1/devices/phone-1/events", { event, payload_hash: hashed.hash.toUpperCase() }, deviceToken);
    expect(dup.status, dup.text).toBe(200);
    expect(dup.text).toContain('"duplicate"');
    expect((dup.json as { payload_hash: string }).payload_hash).toBe(hashed.hash);
    expect((dup.json as { server_received_at: string }).server_received_at).toBe(
      (first.json as { server_received_at: string }).server_received_at,
    );

    const changed = sample({ monotonic_us: 9999 });
    const changedHash = await payloadHash(changed);
    const conflict = await call("POST", "/api/v1/devices/phone-1/events", { event: changed, payload_hash: changedHash.hash }, deviceToken);
    expect(conflict.status, conflict.text).toBe(409);
    expect((conflict.json as { payload_hash: string }).payload_hash).toBe(hashed.hash);

    const read = await call("GET", "/api/v1/devices/phone-1/events/evt-0001", undefined, deviceToken);
    expect(read.status, read.text).toBe(200);
    expect(read.text).toContain(hashed.hash);
    expect(read.text).not.toContain(changedHash.hash);
    expect(read.text).toContain('"monotonic_us":1000');

    const denied = await call("GET", "/api/v1/dashboard/events", undefined, deviceToken);
    expect(denied.status).toBe(401);
    const forbidden = await call("POST", "/api/v1/admin/devices", { device_id: "x", name: "x" }, care);
    expect(forbidden.status).toBe(403);
    const list = await call("GET", "/api/v1/dashboard/events", undefined, care);
    expect(list.status, list.text).toBe(200);
    expect(list.text).toContain("evt-0001");
    expect(list.text).toContain("最近 100 条是可见性视图");
    const series = await call("GET", "/api/v1/dashboard/series?type=blood_pressure", undefined, care);
    expect(series.status, series.text).toBe(200);
    expect(series.text).toContain("systolic");
    const missingType = await call("GET", "/api/v1/dashboard/series", undefined, care);
    expect(missingType.status).toBe(400);

    const recon = await call("GET", "/api/v1/exports/reconciliation.json", undefined, admin);
    expect(recon.status, recon.text).toBe(200);
    expect(recon.text.includes('"conflicts": 1') || recon.text.includes('"conflicts":1')).toBe(true);
    expect(recon.headers.get("content-disposition")).toBeNull();

    const csv = await call("GET", "/api/v1/exports/events.csv", undefined, admin);
    expect(csv.status).toBe(200);
    expect(csv.headers.get("content-type")).toContain("text/csv");
    expect(csv.headers.get("content-disposition")).toContain('filename="events.csv"');
    expect(csv.text.split("\n")[0]).toBe(
      "server_received_at,device_id,event_id,payload_hash,measurement_type,unit,sensor_address,sensor_kind,sensor_model,monotonic_us,wall_time_utc,clock_state,operating_state,values_json",
    );
    expect(csv.text).toContain("evt-0001");
    expect(csv.text).toContain("2026-11-27T08:15:09Z");

    const exported = await call("GET", "/api/v1/exports/events.json", undefined, admin);
    expect(exported.status).toBe(200);
    expect(exported.headers.get("content-disposition")).toContain('filename="events.json"');
    expect(exported.text).toContain("Raw server receipt log");

    const badHash = await call("POST", "/api/v1/devices/phone-1/events", { event, payload_hash: "00" }, deviceToken);
    expect(badHash.status).toBe(400);
    expect(badHash.text).toContain("payload_hash does not match");
    const wrongDevice = await call("POST", "/api/v1/devices/other/events", { event, payload_hash: hashed.hash }, deviceToken);
    expect(wrongDevice.status).toBe(403);
  });

  it("returns not_evaluable research exports until rows exist", async () => {
    const admin = await login("admin", "admin-pass-1");
    const rq1 = await call("GET", "/api/v1/exports/rq1.json", undefined, admin);
    const rq3 = await call("GET", "/api/v1/exports/rq3.json", undefined, admin);
    const rq4 = await call("GET", "/api/v1/exports/rq4.json", undefined, admin);
    expect(rq1.status).toBe(200);
    expect(rq1.text).toContain('"not_evaluable"');
    expect(rq3.text).toContain('"pending_on_server":"not_observable"');
    expect(rq4.text).toContain('"sus":[]');
    expect((rq1.json as { ack_rate: { value: null } }).ack_rate.value).toBeNull();
  });

  it("imports a ground-truth CSV and scores the matched row", async () => {
    const admin = await login("admin", "admin-pass-1");
    await call("POST", "/api/v1/admin/devices", { device_id: "phone-1", name: "采集手机" }, admin);
    const tokenRes = await call("POST", "/api/v1/admin/devices/phone-1/tokens", {}, admin);
    const deviceToken = (tokenRes.json as { token: string }).token;
    const event = sample({
      event_id: "evt-worn",
      sensor_address: "local",
      sensor_kind: "collector",
      sensor_model: "app",
      measurement_type: "worn_state",
      unit: "state",
      monotonic_us: 3,
      wall_time_utc: null,
      clock_state: "UNSET",
      operating_state: "NOMINAL",
      values: { match_key: "w1", worn: true },
    });
    const hashed = await payloadHash(event);
    const stored = await call("POST", "/api/v1/devices/phone-1/events", { event, payload_hash: hashed.hash }, deviceToken);
    expect(stored.status, stored.text).toBe(201);

    const csv = "device_id,match_key,reference_type,reference_value,observed_at,observer,notes\nphone-1,w1,worn,true,2026-11-27T16:15:09+08:00,nurse,ok\nshort,row\n";
    const imported = await SELF.fetch(origin + "/api/v1/ground-truth/import", {
      method: "POST",
      headers: { Authorization: `Bearer ${admin}`, "Content-Type": "text/csv" },
      body: csv,
    });
    expect(imported.status).toBe(201);
    const importedBody = (await imported.json()) as { imported: number };
    expect(importedBody.imported).toBe(1);

    const ledger = await call("GET", "/api/v1/ground-truth", undefined, admin);
    expect(ledger.status).toBe(200);
    const rows = ledger.json as Array<{ observed_at: string; reference_type: string }>;
    expect(rows[0]?.observed_at).toBe("2026-11-27T08:15:09Z");
    expect(rows[0]?.reference_type).toBe("worn");

    const rq2 = await call("GET", "/api/v1/exports/rq2.json", undefined, admin);
    expect(rq2.status, rq2.text).toBe(200);
    expect((rq2.json as { confusion: { tp: number } }).confusion.tp).toBe(1);

    const bad = await SELF.fetch(origin + "/api/v1/ground-truth/import", {
      method: "POST",
      headers: { Authorization: `Bearer ${admin}` },
      body: "phone-1,w2,worn,true,not-a-time,nurse\n",
    });
    expect(bad.status).toBe(400);
    expect(await bad.text()).toContain("observed_at must be RFC3339");
  });

  it("exchanges a one-time pairing code for a device token", async () => {
    const admin = await login("admin", "admin-pass-1");
    await call("POST", "/api/v1/admin/devices", { device_id: "phone-1", name: "采集手机" }, admin);
    const missing = await call("POST", "/api/v1/admin/devices/missing/pairing-codes", {}, admin);
    expect(missing.status).toBe(404);
    const issued = await call("POST", "/api/v1/admin/devices/phone-1/pairing-codes", {}, admin);
    expect(issued.status, issued.text).toBe(201);
    const code = (issued.json as { code: string; ttl_seconds: number }).code;
    expect(code).toMatch(/^\d{6}$/);
    expect((issued.json as { ttl_seconds: number }).ttl_seconds).toBe(600);

    const redeemed = await call("POST", "/api/v1/devices/pair", { code });
    expect(redeemed.status, redeemed.text).toBe(201);
    expect((redeemed.json as { device_id: string }).device_id).toBe("phone-1");
    const deviceToken = (redeemed.json as { token: string }).token;
    const again = await call("POST", "/api/v1/devices/pair", { code });
    expect(again.status).toBe(400);

    await env.DB.prepare(
      "INSERT INTO pairing_codes(code, device_id, expires_at, created_at) VALUES ('222222', 'phone-1', '2020-01-01T00:00:00Z', '2020-01-01T00:00:00Z')",
    ).run();
    const expired = await call("POST", "/api/v1/devices/pair", { code: "222222" });
    expect(expired.status).toBe(400);

    const event = sample();
    const hashed = await payloadHash(event);
    const stored = await call("POST", "/api/v1/devices/phone-1/events", { event, payload_hash: hashed.hash }, deviceToken);
    expect(stored.status, stored.text).toBe(201);

    const anon = await call("POST", "/api/v1/admin/devices/phone-1/pairing-codes");
    expect(anon.status).toBe(401);
    const careUser = await call("POST", "/api/v1/admin/users", { username: "care", password: "care-pass-1", role: "caregiver" }, admin);
    expect(careUser.status).toBe(201);
    const care = await login("care", "care-pass-1");
    const denied = await call("POST", "/api/v1/admin/devices/phone-1/pairing-codes", {}, care);
    expect(denied.status).toBe(403);
  });

  it("rejects a short password and a bad login", async () => {
    const admin = await login("admin", "admin-pass-1");
    const bad = await call("POST", "/api/v1/auth/login", { username: "admin", password: "wrong-pass" });
    expect(bad.status).toBe(401);
    const short = await call("POST", "/api/v1/admin/users", { username: "a", password: "short", role: "caregiver" }, admin);
    expect(short.status).toBe(400);
    expect(short.text).toContain("at least 8 characters");
  });
});
