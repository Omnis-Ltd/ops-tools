import { describe, expect, test } from "bun:test";
import { FadelConfigSchema, formatTimestamp } from "./doctor";

describe("FadelConfigSchema", () => {
  const validConfig = {
    version: 1,
    infra: {
      sshHost: "seo-prod",
      dockerNetwork: "seo-prod-network",
      expectedContainers: ["prod-n8n"],
    },
    mcp: [
      {
        name: "harness",
        serverRoot: "harness/mcp-server",
        cursorConfigPath: "harness/.cursor/mcp.json",
        serverKey: "harness",
      },
    ],
    env: [{ name: "ops-tools", path: "ops-tools" }],
    backlog: [
      { type: "checklist", name: "UPSKILLING.md", path: "my-curriculum/docs/UPSKILLING.md" },
      {
        type: "table",
        name: "harness/BACKLOG.md",
        path: "harness/BACKLOG.md",
        sectionHeader: "## Vue priorisee",
      },
    ],
  };

  test("accepts a valid config", () => {
    const result = FadelConfigSchema.safeParse(validConfig);
    expect(result.success).toBe(true);
  });

  test("rejects a config with wrong version", () => {
    const result = FadelConfigSchema.safeParse({ ...validConfig, version: 2 });
    expect(result.success).toBe(false);
  });

  test("rejects a backlog entry with unknown type", () => {
    const bad = { ...validConfig, backlog: [{ type: "unknown", name: "x", path: "x" }] };
    const result = FadelConfigSchema.safeParse(bad);
    expect(result.success).toBe(false);
  });

  test("defaults statusColumnHeader to Statut when omitted", () => {
    const result = FadelConfigSchema.safeParse(validConfig);
    expect(result.success).toBe(true);
    if (result.success) {
      const table = result.data.backlog[1];
      expect(table.type).toBe("table");
      if (table.type === "table") {
        expect(table.statusColumnHeader).toBe("Statut");
      }
    }
  });
});

describe("formatTimestamp", () => {
  test("formats a UTC date as yyyyMMddTHHmmssZ", () => {
    const date = new Date(Date.UTC(2026, 6, 24, 8, 59, 29));
    expect(formatTimestamp(date)).toBe("20260724T085929Z");
  });
});
