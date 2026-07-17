# Audit editeurs - 2026-07-07 23:11

| Severity | Category | Message |
|---|---|---|
| fail | notion | artmap : mcps/plugin-notion-workspace-notion absent ou vide (slug: c-Users-delfa-git-Workspaces-artmap) |
| pass | claude | settings.json present (modele: claude-fable-5[1m]) |
| pass | mcp | Cursor MCP harness: 2 serveur(s) dans harness/.cursor/mcp.json |
| pass | notion | Projets dependants Notion: artmap |
| pass | notion | Plugin Notion installe (cache cursor-public/notion-workspace) |
| pass | paths | skills-curated.json : C:\Users\delfa\git\Workspaces\harness\manifests\skills-curated.json |
| pass | paths | Cursor user settings : C:\Users\delfa\AppData\Roaming\Cursor\User\settings.json |
| pass | paths | RULES.md : C:\Users\delfa\git\Workspaces\harness\RULES.md |
| pass | paths | VS Code user settings : C:\Users\delfa\AppData\Roaming\Code\User\settings.json |
| pass | plugins | Plugin actif: superpowers@claude-plugins-official |
| pass | plugins | Plugin actif: everything-claude-code@everything-claude-code |
| pass | plugins | Plugin actif: frontend-design@claude-plugins-official |
| pass | rules | Cursor rules harness: 1 fichier(s), 1 alwaysApply |
| pass | secrets | harness/.gitignore exclut .cursor/mcp.json |
| pass | secrets | N8N_API_KEY present (fichier gitignore attendu) |
| pass | skills | everything-claude-code cache: 0 SKILL.md |
| pass | skills | Cursor skills globaux: 19 SKILL.md |
| pass | skills | Superpowers cache: 0 SKILL.md (versions multiples possibles) |
| warn | mcp | ~/.cursor/mcp.json contient des placeholders \ non resolus (Connection closed) |
| warn | mcp | MCP context7 utilise @latest (R-SEC-1 / reproductibilite) |
| warn | notion | artmap : reconnecter plugin Notion (Settings > Plugins > Enable, puis MCP > Connect OAuth, Reload Window) |
| warn | paths | VS Code MCP global absent : C:\Users\delfa\.vscode\mcp.json |
| warn | plugins | superpowers actif - skills proactifs (using-superpowers, brainstorming) |
| warn | rules | Aucun copilot-instructions.md - regles harness non propagees VS Code |
| warn | rules | CLAUDE.md racine Workspaces vide - pas de regles transverses Claude Code |
| warn | skills | Skill Cursor a cout eleve disponible: review-security (subagents/loops) |
| warn | skills | Skill Cursor a cout eleve disponible: split-to-prs (subagents/loops) |
| warn | skills | Skill Cursor a cout eleve disponible: babysit (subagents/loops) |
| warn | skills | Skill Cursor a cout eleve disponible: loop (subagents/loops) |
| warn | skills | Skill Cursor a cout eleve disponible: review-bugbot (subagents/loops) |

**Score:** PASS=17 WARN=12 FAIL=1
