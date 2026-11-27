// Chapter 3 summaries. A zero denominator is not_evaluable. These functions
// never fill in a rate that was not observed.

export interface Rate {
  status: string;
  value: number | null;
  numerator: number;
  denominator: number;
  reason?: string;
}

export interface EventView {
  device_id: string;
  measurement_type: string;
  monotonic_us: number;
  values: Record<string, unknown>;
}

export interface LedgerRow {
  device_id: string;
  match_key: string;
  reference_type: string;
  reference_value: string;
}

function ratio(num: number, den: number, emptyReason: string): Rate {
  if (den === 0) {
    return { status: "not_evaluable", value: null, numerator: num, denominator: 0, reason: emptyReason };
  }
  return { status: "computed", value: num / den, numerator: num, denominator: den };
}

function str(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function asFloat(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function truthy(value: string): boolean {
  return value === "true" || value === "1" || value === "yes" || value === "perceived";
}

function truthyValue(value: unknown): boolean {
  if (typeof value === "boolean") {
    return value;
  }
  if (typeof value === "string") {
    return truthy(value);
  }
  return false;
}

export interface RQ1 {
  note: string;
  device_journal: Record<string, number>;
  observer: Record<string, number>;
  ack_rate: Rate;
  miss_rate: Rate;
  delivery_rate: Rate;
}

export function summarizeRQ1(events: EventView[], ledger: LedgerRow[]): RQ1 {
  const counts: Record<string, number> = {
    scheduled: 0,
    command_logged: 0,
    ack_timely: 0,
    ack_delayed: 0,
    missed: 0,
    censored: 0,
  };
  const latest = new Map<string, EventView>();
  for (const event of events) {
    if (event.measurement_type !== "reminder") {
      continue;
    }
    let key = str(event.values.schedule_id);
    if (key === "") {
      key = str(event.values.match_key);
    }
    if (key === "") {
      continue;
    }
    const prev = latest.get(key);
    if (!prev || event.monotonic_us >= prev.monotonic_us) {
      latest.set(key, event);
    }
  }
  for (const event of latest.values()) {
    switch (str(event.values.disposition)) {
      case "SCHEDULED":
        counts.scheduled++;
        break;
      case "COMMAND_LOGGED":
        counts.command_logged++;
        break;
      case "ACK_TIMELY":
        counts.ack_timely++;
        break;
      case "ACK_DELAYED":
        counts.ack_delayed++;
        break;
      case "MISSED":
        counts.missed++;
        break;
      case "CENSORED":
        counts.censored++;
        break;
      default:
        break;
    }
  }
  const acked = counts.ack_timely + counts.ack_delayed;
  const fired = counts.command_logged + acked + counts.missed + counts.censored;
  let observerEligible = 0;
  let observerPerceived = 0;
  for (const row of ledger) {
    if (row.reference_type === "reminder_eligible" && truthy(row.reference_value)) {
      observerEligible++;
    }
    if (row.reference_type === "reminder_perceived" && truthy(row.reference_value)) {
      observerPerceived++;
    }
  }
  return {
    note: "Device-journal rates use reminder events only. Observer delivery rate stays not_evaluable until an independent ledger has eligible rows. Empty output is not a measured zero performance.",
    device_journal: counts,
    observer: { eligible: observerEligible, perceived: observerPerceived },
    ack_rate: ratio(acked, fired, "no fired reminder instances in the device journal"),
    miss_rate: ratio(counts.missed, fired, "no fired reminder instances in the device journal"),
    delivery_rate: ratio(observerPerceived, observerEligible, "no observer-marked eligible reminders"),
  };
}

export interface RQ2 {
  note: string;
  confusion: Record<string, number>;
  unmatched_ground_truth: number;
  recall: Rate;
  specificity: Rate;
}

function family(measurementType: string): string {
  switch (measurementType) {
    case "worn_state":
      return "worn";
    case "data_gap":
      return "data_gap";
    case "care_attention":
      return "care_attention";
    default:
      return measurementType;
  }
}

function positiveEvent(event: EventView): boolean {
  switch (event.measurement_type) {
    case "worn_state":
      return truthyValue(event.values.worn);
    case "data_gap":
      return truthyValue(event.values.gap);
    case "care_attention":
      return str(event.values.flag) === "CARE_ATTENTION_OVERDUE";
    default:
      return false;
  }
}

export function summarizeRQ2(events: EventView[], ledger: LedgerRow[]): RQ2 {
  const index = new Map<string, EventView>();
  for (const event of events) {
    const match = str(event.values.match_key);
    if (match === "") {
      continue;
    }
    const key = `${event.device_id}|${match}|${family(event.measurement_type)}`;
    const prev = index.get(key);
    if (!prev || event.monotonic_us >= prev.monotonic_us) {
      index.set(key, event);
    }
  }
  let tp = 0;
  let tn = 0;
  let fp = 0;
  let fn = 0;
  let unmatched = 0;
  for (const row of ledger) {
    if (row.reference_type !== "worn" && row.reference_type !== "data_gap" && row.reference_type !== "care_attention") {
      continue;
    }
    const event = index.get(`${row.device_id}|${row.match_key}|${row.reference_type}`);
    if (!event) {
      unmatched++;
      continue;
    }
    const got = positiveEvent(event);
    const want = truthy(row.reference_value);
    if (want && got) {
      tp++;
    } else if (!want && !got) {
      tn++;
    } else if (!want && got) {
      fp++;
    } else {
      fn++;
    }
  }
  return {
    note: "Confusion counts exist only for ground-truth rows that share device_id and match_key with a device event. Unmatched rows are not treated as errors.",
    confusion: { tp, tn, fp, fn },
    unmatched_ground_truth: unmatched,
    recall: ratio(tp, tp + fn, "no positive matched ground-truth rows"),
    specificity: ratio(tn, tn + fp, "no negative matched ground-truth rows"),
  };
}

export interface RQ3 {
  note: string;
  stored_events: number;
  duplicate_acks: number;
  conflicts: number;
  duplicate_attempt_rate: Rate;
  pending_on_server: string;
}

export function summarizeRQ3(stored: number, duplicates: number, conflicts: number): RQ3 {
  const attempts = stored + duplicates + conflicts;
  return {
    note: "Counts are server ingest attempts. Pending events that never left the phone are not visible here. This is not a data-loss estimate.",
    stored_events: stored,
    duplicate_acks: duplicates,
    conflicts,
    duplicate_attempt_rate: ratio(duplicates, attempts, "no ingest attempts"),
    pending_on_server: "not_observable",
  };
}

export interface SUSResult {
  device_id: string;
  match_key: string;
  score: number | null;
  status: string;
  reason?: string;
}

export interface RQ4 {
  note: string;
  task_dispositions: Record<string, number>;
  sus: SUSResult[];
}

function itoa(n: number): string {
  return n === 10 ? "10" : String(n);
}

function scoreSUS(event: EventView): SUSResult {
  const result: SUSResult = {
    device_id: event.device_id,
    match_key: str(event.values.match_key),
    score: null,
    status: "not_evaluable",
  };
  let sum = 0;
  for (let i = 1; i <= 10; i++) {
    const key = "q" + itoa(i);
    if (!(key in event.values)) {
      result.reason = "missing item";
      return result;
    }
    const n = Math.trunc(asFloat(event.values[key]));
    if (n < 1 || n > 5) {
      result.reason = "item outside 1..5";
      return result;
    }
    sum += i % 2 === 1 ? n - 1 : 5 - n;
  }
  result.score = 2.5 * sum;
  result.status = "computed";
  return result;
}

export function summarizeRQ4(events: EventView[]): RQ4 {
  const tasks: Record<string, number> = { unassisted: 0, assisted: 0, abandoned: 0, not_started: 0 };
  const scores: SUSResult[] = [];
  for (const event of events) {
    if (event.measurement_type === "usability_task") {
      const disposition = str(event.values.disposition);
      if (disposition in tasks) {
        tasks[disposition]++;
      }
    }
    if (event.measurement_type === "sus") {
      scores.push(scoreSUS(event));
    }
  }
  return {
    note: "SUS is scored only when q1 through q10 are all present. A missing item does not become a total. Task counts are logged dispositions, not a completed ethics study.",
    task_dispositions: tasks,
    sus: scores,
  };
}
