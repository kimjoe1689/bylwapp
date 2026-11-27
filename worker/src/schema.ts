import { encode, jsonString } from "./json";
import { formatRFC3339, parseRFC3339 } from "./time";

export const SCHEMA_VERSION = "bylw-measure/1";

export interface MeasureEvent {
  schema_version: string;
  event_id: string;
  device_id: string;
  session_id: string;
  sensor_address: string;
  sensor_kind: string;
  sensor_model: string;
  measurement_type: string;
  unit: string;
  monotonic_us: number;
  wall_time_utc: string | null;
  clock_state: string;
  operating_state: string;
  values: Record<string, unknown>;
}

const KINDS = ["blood_pressure", "heart_rate", "ring", "collector"];
const TYPES = [
  "blood_pressure",
  "heart_rate",
  "steps",
  "spo2",
  "sleep",
  "sleep_session",
  "stress",
  "hrv",
  "temperature",
  "operating_state",
  "reminder",
  "care_attention",
  "worn_state",
  "data_gap",
  "usability_task",
  "sus",
];
const CLOCKS = ["UNSET", "NTP_SYNCED", "HOLDOVER", "INVALID"];
const OPS = ["NOMINAL", "BLE_DISCONNECTED", "NETWORK_DEGRADED", "AUTH_FAILURE", "CLOCK_DEGRADED"];

export class SchemaError extends Error {}

function token(value: string): boolean {
  if (value.length < 1 || value.length > 128) {
    return false;
  }
  return /^[A-Za-z0-9._-]+$/.test(value);
}

function oneOf(value: string, allowed: string[]): boolean {
  return allowed.includes(value);
}

export function normalizeWallClock(raw: string | null | undefined): string | null {
  if (raw == null || raw.trim() === "") {
    return null;
  }
  const parsed = parseRFC3339(raw.trim());
  if (!parsed) {
    throw new SchemaError(`wall_time_utc: parsing time ${JSON.stringify(raw.trim())} as "2006-01-02T15:04:05Z07:00": cannot parse`);
  }
  return formatRFC3339(parsed);
}

export function prepare(event: MeasureEvent): MeasureEvent {
  const wall = normalizeWallClock(event.wall_time_utc);
  return {
    ...event,
    schema_version: event.schema_version === "" ? SCHEMA_VERSION : event.schema_version,
    wall_time_utc: wall,
    values: event.values ?? {},
  };
}

export function validate(event: MeasureEvent): void {
  if (event.schema_version !== SCHEMA_VERSION) {
    throw new SchemaError(`schema_version must be ${SCHEMA_VERSION}`);
  }
  if (!token(event.event_id) || !token(event.device_id) || !token(event.session_id)) {
    throw new SchemaError("event_id, device_id, and session_id must be path-safe tokens");
  }
  if (!token(event.sensor_address) || !token(event.sensor_kind)) {
    throw new SchemaError("sensor_address and sensor_kind must be path-safe tokens");
  }
  if (event.sensor_model.length > 80 || event.unit.length > 16 || event.unit === "") {
    throw new SchemaError("unit is required and model/unit lengths are limited");
  }
  if (event.monotonic_us < 0) {
    throw new SchemaError("monotonic_us must be >= 0");
  }
  if (!oneOf(event.clock_state, CLOCKS)) {
    throw new SchemaError("clock_state is invalid");
  }
  if (!oneOf(event.operating_state, OPS)) {
    throw new SchemaError("operating_state is invalid");
  }
  if (!oneOf(event.sensor_kind, KINDS)) {
    throw new SchemaError("sensor_kind is invalid");
  }
  if (!oneOf(event.measurement_type, TYPES)) {
    throw new SchemaError("measurement_type is invalid");
  }
  const timed = event.clock_state === "NTP_SYNCED" || event.clock_state === "HOLDOVER";
  if (timed && event.wall_time_utc == null) {
    throw new SchemaError("wall_time_utc is required when the clock is NTP_SYNCED or HOLDOVER");
  }
  if (!timed && event.wall_time_utc != null) {
    throw new SchemaError("wall_time_utc must be null when the clock is UNSET or INVALID");
  }
  if (event.wall_time_utc != null && !parseRFC3339(event.wall_time_utc)) {
    throw new SchemaError("wall_time_utc: invalid RFC3339 timestamp");
  }
  if (event.values == null) {
    throw new SchemaError("values is required");
  }
}

export function canonicalJSON(event: MeasureEvent): string {
  validate(event);
  const values = encode(event.values, true);
  const parts: Array<[string, string]> = [
    ["clock_state", jsonString(event.clock_state)],
    ["device_id", jsonString(event.device_id)],
    ["event_id", jsonString(event.event_id)],
    ["measurement_type", jsonString(event.measurement_type)],
    ["monotonic_us", String(Math.trunc(event.monotonic_us))],
    ["operating_state", jsonString(event.operating_state)],
    ["schema_version", jsonString(event.schema_version)],
    ["sensor_address", jsonString(event.sensor_address)],
    ["sensor_kind", jsonString(event.sensor_kind)],
    ["sensor_model", jsonString(event.sensor_model)],
    ["session_id", jsonString(event.session_id)],
    ["unit", jsonString(event.unit)],
    ["values", values],
    ["wall_time_utc", event.wall_time_utc == null ? "null" : jsonString(event.wall_time_utc)],
  ];
  let out = "{";
  parts.forEach((part, index) => {
    if (index > 0) {
      out += ",";
    }
    out += jsonString(part[0]) + ":" + part[1];
  });
  out += "}";
  return out;
}

export async function payloadHash(event: MeasureEvent): Promise<{ hash: string; canonical: string }> {
  const canonical = canonicalJSON(event);
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical));
  const bytes = new Uint8Array(digest);
  let hash = "";
  for (const byte of bytes) {
    hash += byte.toString(16).padStart(2, "0");
  }
  return { hash, canonical };
}
