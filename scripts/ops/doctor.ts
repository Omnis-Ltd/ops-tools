// doctor.ts
// Preflight check unique pour l'ecosysteme Fadel OS : infra, MCP, completude .env, avancement backlogs.
// Usage : bun scripts/ops/doctor.ts   (depuis ops-tools/)
//    ou : make doctor (apres bun run build:doctor)

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { z } from "zod";
import { $ } from "bun";

// --- Schema du manifeste ---

const InfraConfigSchema = z.object({
  sshHost: z.string(),
  dockerNetwork: z.string(),
  expectedContainers: z.array(z.string()).min(1),
});

const McpConfigSchema = z.object({
  name: z.string(),
  serverRoot: z.string(),
  cursorConfigPath: z.string(),
  serverKey: z.string(),
});

const EnvConfigSchema = z.object({
  name: z.string(),
  path: z.string(),
});

const BacklogChecklistSchema = z.object({
  type: z.literal("checklist"),
  name: z.string(),
  path: z.string(),
});

const BacklogTableSchema = z.object({
  type: z.literal("table"),
  name: z.string(),
  path: z.string(),
  sectionHeader: z.string(),
  statusColumnHeader: z.string().default("Statut"),
});

const BacklogEntrySchema = z.discriminatedUnion("type", [
  BacklogChecklistSchema,
  BacklogTableSchema,
]);

export const FadelConfigSchema = z.object({
  version: z.literal(1),
  infra: InfraConfigSchema,
  mcp: z.array(McpConfigSchema),
  env: z.array(EnvConfigSchema),
  backlog: z.array(BacklogEntrySchema),
});

export type FadelConfig = z.infer<typeof FadelConfigSchema>;

export function loadConfig(configPath: string): FadelConfig {
  if (!fs.existsSync(configPath)) {
    throw new Error(`fadel-os.config.json introuvable : ${configPath}`);
  }
  const raw = fs.readFileSync(configPath, "utf8");
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    throw new Error(`fadel-os.config.json invalide (JSON malforme) : ${(err as Error).message}`);
  }
  const result = FadelConfigSchema.safeParse(parsed);
  if (!result.success) {
    const issues = result.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; ");
    throw new Error(`fadel-os.config.json invalide : ${issues}`);
  }
  return result.data;
}

// --- Moteur de findings ---

export type Severity = "pass" | "warn" | "fail";

export interface Finding {
  severity: Severity;
  category: string;
  message: string;
}

const findings: Finding[] = [];
const scores: Record<Severity, number> = { pass: 0, warn: 0, fail: 0 };

export function addFinding(severity: Severity, category: string, message: string): void {
  findings.push({ severity, category, message });
  scores[severity]++;
}

// --- Utilitaires ---

export function resolveWorkspacesRoot(): string {
  return process.env.WORKSPACES_ROOT ?? path.join(os.homedir(), "git", "Workspaces");
}

export function toShellPath(p: string): string {
  return p.replaceAll("\\", "/");
}

export function formatTimestamp(date: Date): string {
  const iso = date.toISOString(); // ex: 2026-07-24T08:59:29.123Z
  const [datePart, timePart] = iso.split("T");
  const compactDate = datePart.replaceAll("-", "");
  const compactTime = timePart.slice(0, 8).replaceAll(":", "");
  return `${compactDate}T${compactTime}Z`;
}

const colors = {
  green: (s: string) => `\x1b[32m${s}\x1b[0m`,
  yellow: (s: string) => `\x1b[33m${s}\x1b[0m`,
  red: (s: string) => `\x1b[31m${s}\x1b[0m`,
  cyan: (s: string) => `\x1b[36m${s}\x1b[0m`,
};

// --- Sections (squelette, remplies par les taches suivantes) ---

function listFilesRecursive(dir: string): string[] {
  if (!fs.existsSync(dir)) return [];
  const results: string[] = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...listFilesRecursive(fullPath));
    } else {
      results.push(fullPath);
    }
  }
  return results;
}

async function checkInfra(config: FadelConfig, workspacesRoot: string): Promise<void> {
  const sshExe = "C:/Windows/System32/OpenSSH/ssh.exe";
  const dockerCmd = `docker ps --filter network=${config.infra.dockerNetwork} --format '{{json .}}'`;

  let sshOutput: string;
  try {
    sshOutput = await $`${sshExe} -o BatchMode=yes -o ConnectTimeout=5 ${config.infra.sshHost} ${dockerCmd}`.text();
  } catch {
    addFinding("fail", "infra", `VPS ${config.infra.sshHost} injoignable`);
    return;
  }

  interface DockerPsEntry {
    Names: string;
    State: string;
    Status: string;
  }

  const runningContainers = new Map<string, DockerPsEntry>();
  for (const rawLine of sshOutput.split("\n")) {
    const trimmed = rawLine.trim();
    if (!trimmed) continue;
    try {
      const obj = JSON.parse(trimmed) as DockerPsEntry;
      runningContainers.set(obj.Names, obj);
    } catch {
      continue;
    }
  }

  for (const name of config.infra.expectedContainers) {
    const container = runningContainers.get(name);
    if (!container) {
      addFinding("fail", "infra", `${name} : conteneur introuvable sur ${config.infra.dockerNetwork}`);
      continue;
    }
    if (container.State !== "running") {
      addFinding("fail", "infra", `${name} : arrete (etat=${container.State})`);
    } else if (container.Status.includes("(unhealthy)")) {
      addFinding("warn", "infra", `${name} : running mais unhealthy`);
    } else {
      addFinding("pass", "infra", `${name} : running (${container.Status})`);
    }
  }
}

async function checkMcp(config: FadelConfig, workspacesRoot: string): Promise<void> {
  for (const server of config.mcp) {
    const serverRoot = path.join(workspacesRoot, ...server.serverRoot.split("/"));
    const distIndex = path.join(serverRoot, "dist", "index.js");
    const srcDir = path.join(serverRoot, "src");

    if (!fs.existsSync(distIndex)) {
      addFinding("warn", "mcp", `${server.name} : dist/index.js absent (build jamais lance)`);
    } else {
      const distTime = fs.statSync(distIndex).mtimeMs;
      const srcFiles = listFilesRecursive(srcDir);
      const newestSrcTime =
        srcFiles.length > 0 ? Math.max(...srcFiles.map((f) => fs.statSync(f).mtimeMs)) : null;
      if (newestSrcTime !== null && newestSrcTime > distTime) {
        addFinding("warn", "mcp", `${server.name} : build obsolete (dist/ plus ancien que src/)`);
      } else {
        addFinding("pass", "mcp", `${server.name} : build a jour (dist/index.js)`);
      }
    }

    const cursorConfigPath = path.join(workspacesRoot, ...server.cursorConfigPath.split("/"));
    if (fs.existsSync(cursorConfigPath)) {
      const mcpJson = JSON.parse(fs.readFileSync(cursorConfigPath, "utf8"));
      const serverEntry = mcpJson.mcpServers?.[server.serverKey];
      const referencedPath: string | undefined = serverEntry?.args?.find((a: string) =>
        /index\.js$/.test(a)
      );
      if (referencedPath && fs.existsSync(referencedPath)) {
        addFinding(
          "pass",
          "mcp",
          `${server.name} : mcp.json pointe vers un dist/index.js existant (${referencedPath})`
        );
      } else if (referencedPath) {
        addFinding("warn", "mcp", `${server.name} : mcp.json pointe vers un chemin introuvable (${referencedPath})`);
      } else {
        addFinding(
          "warn",
          "mcp",
          `${server.name} : mcp.json ne reference pas index.js pour le serveur ${server.serverKey}`
        );
      }
    } else {
      addFinding("warn", "mcp", `${server.cursorConfigPath} absent`);
    }

    let lastActivity: string | null = null;
    try {
      const out = await $`git -C ${toShellPath(serverRoot)} log -1 --format=%cd -- .`.text();
      lastActivity = out.trim() || null;
    } catch {
      lastActivity = null;
    }
    if (lastActivity) {
      addFinding("pass", "mcp", `${server.name} : derniere activite ${lastActivity}`);
    } else {
      addFinding("warn", "mcp", `${server.name} : aucun historique git trouve pour ${server.serverRoot}`);
    }
  }
}

async function checkEnv(config: FadelConfig, workspacesRoot: string): Promise<void> {
  // Remplie par Task 4
}

async function checkBacklog(config: FadelConfig, workspacesRoot: string): Promise<void> {
  // Remplie par Task 5
}

// --- Orchestration ---

function printReportAndExit(opsToolsRoot: string): never {
  console.log(colors.cyan(`\n=== Findings (${findings.length}) ===`));
  const sorted = [...findings].sort((a, b) =>
    a.severity === b.severity ? a.category.localeCompare(b.category) : a.severity.localeCompare(b.severity)
  );
  for (const f of sorted) {
    const color = f.severity === "pass" ? colors.green : f.severity === "warn" ? colors.yellow : colors.red;
    console.log(color(`  [${f.severity.toUpperCase().padStart(4)}] ${f.category.padEnd(10)} ${f.message}`));
  }

  console.log(colors.cyan("\n=== Score ==="));
  console.log(`  PASS: ${scores.pass}  WARN: ${scores.warn}  FAIL: ${scores.fail}`);

  const timestamp = formatTimestamp(new Date());
  const outDir = path.join(opsToolsRoot, "meta", "rex");
  const outFile = path.join(outDir, `doctor_${timestamp}.md`);
  fs.mkdirSync(outDir, { recursive: true });

  const mdLines = [
    `# ops doctor - ${new Date().toISOString().slice(0, 16).replace("T", " ")}`,
    "",
    "| Severity | Category | Message |",
    "|---|---|---|",
    ...sorted.map((f) => `| ${f.severity} | ${f.category} | ${f.message.replaceAll("|", "/")} |`),
    "",
    `**Score:** PASS=${scores.pass} WARN=${scores.warn} FAIL=${scores.fail}`,
  ];
  fs.writeFileSync(outFile, mdLines.join("\n"), "utf8");
  console.log(colors.green(`\nRapport: ${outFile}`));

  process.exit(scores.fail > 0 ? 1 : 0);
}

async function main(): Promise<void> {
  const workspacesRoot = resolveWorkspacesRoot();
  const opsToolsRoot = path.join(workspacesRoot, "ops-tools");

  console.log(colors.cyan("\n=== ops doctor ==="));
  console.log(`Workspaces: ${workspacesRoot}\n`);

  if (fs.existsSync(workspacesRoot)) {
    addFinding("pass", "bootstrap", `Workspaces root resolu : ${workspacesRoot}`);
  } else {
    addFinding("fail", "bootstrap", `Workspaces root introuvable : ${workspacesRoot}`);
  }

  const configPath = path.join(workspacesRoot, "fadel-os.config.json");
  let config: FadelConfig;
  try {
    config = loadConfig(configPath);
  } catch (err) {
    addFinding("fail", "bootstrap", (err as Error).message);
    printReportAndExit(opsToolsRoot);
  }

  const sections: Array<{ name: string; fn: (c: FadelConfig, w: string) => Promise<void> }> = [
    { name: "infra", fn: checkInfra },
    { name: "mcp", fn: checkMcp },
    { name: "env", fn: checkEnv },
    { name: "backlog", fn: checkBacklog },
  ];

  for (const section of sections) {
    console.log(colors.yellow(`\n--- ${section.name} ---`));
    try {
      await section.fn(config, workspacesRoot);
    } catch (err) {
      addFinding("fail", section.name, `Section ${section.name} : erreur inattendue (${(err as Error).message})`);
    }
  }

  printReportAndExit(opsToolsRoot);
}

if (import.meta.main) {
  await main();
}
