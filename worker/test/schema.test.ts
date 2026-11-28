import { describe, expect, it } from "vitest";
import { canonicalJSON, payloadHash, prepare, type MeasureEvent } from "../src/schema";

const VECTOR = `{"clock_state":"NTP_SYNCED","device_id":"phone-1","event_id":"evt-0001","measurement_type":"blood_pressure","monotonic_us":1000,"operating_state":"NOMINAL","schema_version":"bylw-measure/1","sensor_address":"AA-BB-CC-DD-EE-01","sensor_kind":"blood_pressure","sensor_model":"Yuwell YE680B","session_id":"sess-1","unit":"mmHg","values":{"diastolic":80,"pulse":72,"systolic":120},"wall_time_utc":"2026-11-27T08:15:09Z"}`;
const VECTOR_HASH = "9b9e90354ba15670c60fdf194a44d52eda406ca85a6c8e9c14c8ea14043777e4";

function base(overrides: Partial<MeasureEvent> = {}): MeasureEvent {
  return {
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
  };
}

describe("canonical event", () => {
  it("matches the Go hash vector", async () => {
    const event = prepare(base());
    expect(canonicalJSON(event)).toBe(VECTOR);
    const first = await payloadHash(event);
    const second = await payloadHash(event);
    expect(first.hash).toBe(VECTOR_HASH);
    expect(second.hash).toBe(first.hash);
    expect(first.canonical).toBe(VECTOR);
  });

  it("normalizes offsets to UTC and rejects a wall clock on UNSET", () => {
    const event = prepare(
      base({
        event_id: "evt-2",
        sensor_address: "local",
        sensor_kind: "collector",
        sensor_model: "app",
        measurement_type: "operating_state",
        unit: "state",
        monotonic_us: 2,
        wall_time_utc: "2026-11-27T16:15:09+08:00",
        clock_state: "HOLDOVER",
        operating_state: "CLOCK_DEGRADED",
        values: { state: "CLOCK_DEGRADED" },
      }),
    );
    expect(event.wall_time_utc).toBe("2026-11-27T08:15:09Z");
    expect(() =>
      canonicalJSON({ ...event, clock_state: "UNSET", wall_time_utc: "2026-11-27T08:15:09Z" }),
    ).toThrow(/wall_time_utc must be null/);
  });

  it("formats fractional values and escapes HTML in the canonical preimage", () => {
    const event = prepare(base({ values: { note: "a<b&c>", systolic: 120.5 } }));
    const body = canonicalJSON(event);
    expect(body).toContain('"note":"a\\u003cb\\u0026c\\u003e"');
    expect(body).toContain('"systolic":120.5000');
  });
});
