// Go's encoding/json, close enough for the API contract:
// struct field order is preserved via Ordered, map keys are sorted,
// strings escape &, <, >, U+2028 and U+2029, and responses end with a newline.

export class Ordered {
  constructor(public readonly entries: ReadonlyArray<readonly [string, unknown]>) {}
}

export class Raw {
  constructor(public readonly text: string) {}
}

export function jsonString(value: string): string {
  let out = '"';
  for (const ch of value) {
    const code = ch.codePointAt(0) ?? 0;
    switch (ch) {
      case '"':
        out += '\\"';
        break;
      case "\\":
        out += "\\\\";
        break;
      case "\b":
        out += "\\b";
        break;
      case "\f":
        out += "\\f";
        break;
      case "\n":
        out += "\\n";
        break;
      case "\r":
        out += "\\r";
        break;
      case "\t":
        out += "\\t";
        break;
      case "&":
        out += "\\u0026";
        break;
      case "<":
        out += "\\u003c";
        break;
      case ">":
        out += "\\u003e";
        break;
      default:
        if (code < 0x20 || code === 0x2028 || code === 0x2029) {
          out += "\\u" + code.toString(16).padStart(4, "0");
        } else {
          out += ch;
        }
    }
  }
  out += '"';
  return out;
}

function formatNumber(value: number, canonical: boolean): string {
  if (!Number.isFinite(value)) {
    throw new Error("values cannot contain NaN or infinity");
  }
  if (Object.is(value, -0)) {
    return "0";
  }
  const whole = value === Math.trunc(value) && Math.abs(value) < 1e15;
  if (canonical) {
    if (whole) {
      return String(Math.trunc(value));
    }
    return value.toFixed(4);
  }
  return JSON.stringify(value);
}

export function encode(value: unknown, canonical = false): string {
  if (value === null || value === undefined) {
    return "null";
  }
  if (typeof value === "boolean") {
    return value ? "true" : "false";
  }
  if (typeof value === "number") {
    return formatNumber(value, canonical);
  }
  if (typeof value === "string") {
    return jsonString(value);
  }
  if (value instanceof Raw) {
    return value.text;
  }
  if (value instanceof Ordered) {
    const parts = value.entries
      .filter(([, item]) => item !== undefined)
      .map(([key, item]) => jsonString(key) + ":" + encode(item, canonical));
    return "{" + parts.join(",") + "}";
  }
  if (Array.isArray(value)) {
    return "[" + value.map((item) => encode(item, canonical)).join(",") + "]";
  }
  if (typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>).filter(([, item]) => item !== undefined);
    entries.sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
    return "{" + entries.map(([key, item]) => jsonString(key) + ":" + encode(item, canonical)).join(",") + "}";
  }
  throw new Error("unsupported value type");
}

export function jsonBody(value: unknown): string {
  return encode(value) + "\n";
}

export function csvField(value: string): string {
  if (/[",\n\r]/.test(value)) {
    return `"${value.replaceAll('"', '""')}"`;
  }
  return value;
}

export function csvLine(fields: string[]): string {
  return fields.map(csvField).join(",") + "\n";
}
