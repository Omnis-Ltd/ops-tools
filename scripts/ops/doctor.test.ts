import { describe, expect, test } from "bun:test";
import { FadelConfigSchema, formatTimestamp, extractEnvKeys, parseChecklist, parseBacklogTable } from "./doctor";

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

describe("extractEnvKeys", () => {
  test("extracts key names, ignoring values and comments", () => {
    const content = ["# comment", "NOTION_API_KEY=secret_abc123", "", "PORT=3000", "not a valid line"].join(
      "\n"
    );
    expect(extractEnvKeys(content)).toEqual(["NOTION_API_KEY", "PORT"]);
  });

  test("returns an empty array for content with no valid keys", () => {
    expect(extractEnvKeys("# just a comment\n")).toEqual([]);
  });
});

describe("parseChecklist", () => {
  test("counts checked and unchecked items per section", () => {
    const content = [
      "## Project A",
      "- [x] done task",
      "- [ ] pending task",
      "- [x] another done",
      "## Project B",
      "- [ ] only pending",
    ].join("\n");
    const result = parseChecklist(content);
    expect(result.get("Project A")).toEqual({ done: 2, total: 3 });
    expect(result.get("Project B")).toEqual({ done: 0, total: 1 });
  });

  test("ignores lines before the first section header", () => {
    const content = "- [x] orphan\n## Project A\n- [x] real";
    const result = parseChecklist(content);
    expect(result.has("Project A")).toBe(true);
    expect(result.get("Project A")).toEqual({ done: 1, total: 1 });
  });

  test("handles CRLF line endings in section headers", () => {
    const content = "## Project A\r\n- [x] done task\r\n- [ ] pending task\r\n";
    const result = parseChecklist(content);
    expect(result.get("Project A")).toEqual({ done: 1, total: 2 });
  });

  test("returns an empty map for content with no section headers", () => {
    const result = parseChecklist("- [x] orphan checkbox with no section\n");
    expect(result.size).toBe(0);
  });
});

describe("parseBacklogTable", () => {
  const fixture = [
    "## Other Section",
    "| # | Statut |",
    "|---|---|",
    "| 1 | ✅ |",
    "## Vue priorisee",
    "| # | ID | Statut |",
    "|---|---|---|",
    "| 1 | A | ✅ |",
    "| 2 | B | 🔄 |",
    "| 3 | C | ⬜ |",
    "## Next Section",
    "| # | Statut |",
    "|---|---|",
    "| 1 | ✅ |",
  ].join("\n");

  test("counts only the table under the exact target section header", () => {
    const result = parseBacklogTable(fixture, "## Vue priorisee");
    expect(result).toEqual({ done: 1, total: 3 });
  });

  test("returns done=0 total=0 when the section header is not found", () => {
    const result = parseBacklogTable(fixture, "## Nonexistent Section");
    expect(result).toEqual({ done: 0, total: 0 });
  });

  test("returns done=0 total=0 when the Statut column is not present in the table", () => {
    const content = "## Target\n| # | Other |\n|---|---|\n| 1 | x |";
    const result = parseBacklogTable(content, "## Target");
    expect(result).toEqual({ done: 0, total: 0 });
  });
});
