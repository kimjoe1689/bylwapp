import { describe, expect, it } from "vitest";
import { summarizeRQ1, summarizeRQ2, summarizeRQ3, summarizeRQ4, type EventView, type LedgerRow } from "../src/metrics";

describe("research summaries", () => {
  it("stays not_evaluable without rows", () => {
    const report = summarizeRQ1([], []);
    expect(report.delivery_rate.status).toBe("not_evaluable");
    expect(report.ack_rate.status).toBe("not_evaluable");
    expect(report.ack_rate.value).toBeNull();
  });

  it("uses only observed rows", () => {
    const events: EventView[] = [
      { device_id: "phone-1", measurement_type: "reminder", monotonic_us: 2, values: { schedule_id: "med-1", disposition: "ACK_TIMELY" } },
      { device_id: "phone-1", measurement_type: "reminder", monotonic_us: 1, values: { schedule_id: "med-1", disposition: "COMMAND_LOGGED" } },
      { device_id: "phone-1", measurement_type: "worn_state", monotonic_us: 3, values: { match_key: "w1", worn: true } },
    ];
    const ledger: LedgerRow[] = [
      { device_id: "phone-1", match_key: "med-1", reference_type: "reminder_eligible", reference_value: "true" },
      { device_id: "phone-1", match_key: "med-1", reference_type: "reminder_perceived", reference_value: "true" },
      { device_id: "phone-1", match_key: "w1", reference_type: "worn", reference_value: "true" },
      { device_id: "phone-1", match_key: "missing", reference_type: "worn", reference_value: "false" },
    ];
    const rq1 = summarizeRQ1(events, ledger);
    expect(rq1.device_journal.ack_timely).toBe(1);
    expect(rq1.ack_rate.status).toBe("computed");
    expect(rq1.delivery_rate.numerator).toBe(1);
    expect(rq1.delivery_rate.denominator).toBe(1);
    const rq2 = summarizeRQ2(events, ledger);
    expect(rq2.confusion.tp).toBe(1);
    expect(rq2.unmatched_ground_truth).toBe(1);
  });

  it("requires every SUS item", () => {
    const partial = summarizeRQ4([{ device_id: "p", measurement_type: "sus", monotonic_us: 1, values: { q1: 5 } }]);
    expect(partial.sus[0]?.status).toBe("not_evaluable");
    const values: Record<string, unknown> = {};
    for (let i = 1; i <= 10; i++) {
      values[`q${i}`] = 5;
    }
    const full = summarizeRQ4([{ device_id: "p", measurement_type: "sus", monotonic_us: 1, values }]);
    expect(full.sus[0]?.status).toBe("computed");
    expect(full.sus[0]?.score).toBe(50);
  });

  it("does not invent loss", () => {
    const report = summarizeRQ3(0, 0, 0);
    expect(report.duplicate_attempt_rate.status).toBe("not_evaluable");
    expect(report.pending_on_server).toBe("not_observable");
  });
});
