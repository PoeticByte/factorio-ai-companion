import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { spawn } from "child_process";
import { RCONClient } from "../rcon/client";
import { TOOLS, SKILLS, generateToolSchemas, generateSkillSchemas, buildRCONCommand } from "./tools";

// Track running skills by companionId
interface RunningSkill {
  pid: number;
  skillName: string;
  startTime: number;
}
const runningSkills = new Map<number, RunningSkill>();

export class FactorioMCPServer {
  private server: Server;
  private rcon: RCONClient;
  private pollingInterval?: NodeJS.Timeout;

  constructor(rconConfig: { host: string; port: number; password: string }) {
    this.server = new Server(
      {
        name: "factorio-companion",
        version: "0.14.0",
      },
      {
        capabilities: {
          tools: {},
        },
      }
    );

    this.rcon = new RCONClient(rconConfig);
    this.setupHandlers();
  }

  private setupHandlers() {
    // Generate all tool schemas from single source of truth
    this.server.setRequestHandler(ListToolsRequestSchema, async () => ({
      tools: [...generateToolSchemas(), ...generateSkillSchemas()],
    }));

    this.server.setRequestHandler(CallToolRequestSchema, async (request) => {
      const args = request.params.arguments as Record<string, any>;
      const toolName = request.params.name;

      // Helper to execute RCON and return formatted response
      const execRCON = async (command: string) => {
        const response = await this.rcon.sendCommand(command);
        return {
          content: [{
            type: "text" as const,
            text: response.success ? (response.data || "OK") : `Error: ${response.error}`
          }]
        };
      };

      // Helper to stop a companion's running skill (TS + Lua)
      const stopCompanionSkill = async (companionId: number): Promise<string | null> => {
        const skill = runningSkills.get(companionId);

        // Always clear Lua queues
        await this.rcon.sendCommand(`/fac_resource_mine_stop ${companionId}`);
        await this.rcon.sendCommand(`/fac_item_craft_stop ${companionId}`);
        await this.rcon.sendCommand(`/fac_blueprint_stop ${companionId}`);
        await this.rcon.sendCommand(`/fac_haul_stop ${companionId}`);
        await this.rcon.sendCommand(`/fac_refuel_stop ${companionId}`);
        await this.rcon.sendCommand(`/fac_move_stop ${companionId}`);

        if (!skill) {
          return null; // No TS skill was running
        }

        // Kill the TS process
        try {
          process.kill(skill.pid);
          runningSkills.delete(companionId);
          return `Stopped ${skill.skillName} (pid ${skill.pid})`;
        } catch (e) {
          runningSkills.delete(companionId);
          return `Process ${skill.pid} already dead`;
        }
      };

      // Tools that require stopping active skills before execution
      const AUTO_STOP_TOOLS = [
        'move_to', 'move_follow',
        'action_attack', 'action_flee', 'action_patrol', 'action_wololo'
      ];

      // Check if it's a regular RCON tool
      if (TOOLS[toolName]) {
        // Auto-stop skills for movement/action commands
        if (AUTO_STOP_TOOLS.includes(toolName) && args.companionId !== undefined) {
          const stopMsg = await stopCompanionSkill(args.companionId as number);
          if (stopMsg) {
            console.error(`[Auto-stop] ${stopMsg} for ${toolName}`);
          }
        }

        const cmd = buildRCONCommand(toolName, args);
        return execRCON(cmd);
      }

      // Check if it's a skill (background process)
      if (SKILLS[toolName]) {
        const skill = SKILLS[toolName];
        const companionId = args.companionId as number;

        // Check if companion already has a running skill
        const existing = runningSkills.get(companionId);
        if (existing) {
          return {
            content: [{
              type: "text" as const,
              text: `Companion ${companionId} already running ${existing.skillName} (pid ${existing.pid}). Stop it first with skill_stop.`
            }]
          };
        }

        // Build args array from params
        const scriptArgs = Object.entries(skill.params).map(([name, config]) => {
          const value = args[name] ?? config.default ?? "";
          return String(value);
        });

        const proc = spawn("bun", ["run", `src/${skill.script}`, ...scriptArgs], {
          cwd: process.cwd(),
          detached: true,
          stdio: "ignore"
        });

        // Track the running skill
        runningSkills.set(companionId, {
          pid: proc.pid!,
          skillName: toolName,
          startTime: Date.now()
        });

        // Clean up when process exits
        proc.on("exit", () => {
          runningSkills.delete(companionId);
        });

        proc.unref();

        return {
          content: [{
            type: "text" as const,
            text: `Started ${toolName} for companion ${companionId} (pid ${proc.pid})`
          }]
        };
      }

      // session_status - get current state and instructions
      if (toolName === "session_status") {
        // Get companions from Lua
        const companionsResponse = await this.rcon.sendCommand("/fac_companion_list");
        let companions: any = {};
        try {
          companions = companionsResponse.success ? JSON.parse(companionsResponse.data || "{}") : {};
        } catch { /* ignore parse errors */ }

        // Get running skills from TS
        const skills: Record<number, RunningSkill> = {};
        runningSkills.forEach((skill, id) => {
          skills[id] = skill;
        });

        const status = {
          companions: companions.companions || {},
          companionCount: companions.count || 0,
          runningSkills: skills,
          instructions: {
            step1: "Spawn companions: companion_spawn(companionId: 1)",
            step2: "Start reactive loop: Bash(run_in_background: true): bun run src/reactive-all.ts",
            step3: "Poll messages: TaskOutput(task_id, block: true, timeout: 120000)",
            step4: "Parse JSON array, respond with chat_say + actions, repeat from step2"
          },
          reactiveLoopCommand: "bun run src/reactive-all.ts"
        };

        return {
          content: [{
            type: "text" as const,
            text: JSON.stringify(status, null, 2)
          }]
        };
      }

      // companion_status - unified Lua state/task/inventory + TS background-skill tracking
      if (toolName === "companion_status") {
        const companionId = args.companionId as number;

        // Rich status from Lua (state, task, position, health, inventory)
        const statusResponse = await this.rcon.sendCommand(`/fac_companion_status ${companionId}`);
        let status: any = {};
        try {
          status = JSON.parse(statusResponse.data || "{}");
        } catch {}

        // Merge TS-tracked background skill (mine_until / combat_until child process)
        const skill = runningSkills.get(companionId);
        const backgroundSkill = skill ? {
          running: true,
          skillName: skill.skillName,
          pid: skill.pid,
          elapsedSeconds: Math.floor((Date.now() - skill.startTime) / 1000)
        } : { running: false };

        return {
          content: [{
            type: "text" as const,
            text: JSON.stringify({ ...status, backgroundSkill })
          }]
        };
      }

      // companion_stop - kill a running skill AND clear Lua queues
      if (toolName === "companion_stop") {
        const companionId = args.companionId as number;
        const stopMsg = await stopCompanionSkill(companionId);

        if (!stopMsg) {
          return {
            content: [{ type: "text" as const, text: `No TS skill running for companion ${companionId}. Cleared Lua queues.` }]
          };
        }

        return {
          content: [{
            type: "text" as const,
            text: `${stopMsg}. Cleared Lua queues.`
          }]
        };
      }

      throw new Error(`Unknown tool: ${toolName}`);
    });
  }

  private async checkForMessages() {
    try {
      const response = await this.rcon.sendCommand("/fac_chat_get");

      if (response.success && response.data) {
        const messages = JSON.parse(response.data || "[]");

        if (Array.isArray(messages) && messages.length > 0) {
          messages.forEach((msg: { player: string; message: string; tick: number }) => {
            this.server.notification({
              method: "notifications/message",
              params: {
                level: "info",
                logger: "factorio-companion",
                data: msg,
              },
            });
          });

          console.error(`Sent ${messages.length} notification(s)`);
        }
      }
    } catch (error) {
      // Silently ignore polling errors
    }
  }

  private startPolling() {
    console.error("Starting message polling (every 3 seconds)...");

    this.pollingInterval = setInterval(async () => {
      await this.checkForMessages();
    }, 3000);
  }

  async start() {
    console.error("Starting Factorio MCP Server...");
    await this.rcon.connect();
    console.error("RCON connected");

    const transport = new StdioServerTransport();
    await this.server.connect(transport);
    console.error("MCP server running on stdio");

    this.startPolling();
  }

  async stop() {
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval);
    }
    await this.rcon.disconnect();
  }
}
