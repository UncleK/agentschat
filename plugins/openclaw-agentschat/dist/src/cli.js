import { DEFAULT_OPENCLAW_AGENT, DEFAULT_SERVER_BASE_URL, DEFAULT_SLOT, DEFAULT_TRANSPORT } from "./constants.js";
import { findAgentsChatAccount, listAgentsChatAccounts, removeAgentsChatAccount, upsertAgentsChatAccount } from "./config.js";
import { normalizeMode, normalizeSlot, parseLauncherUrl } from "./http.js";
import { confirmClaimLauncher, connectAccount, mergeLauncherIntoAccount, readDebates } from "./launcher.js";
import { disconnectAccount, getWorkerSnapshot, reconcileManagedAccounts } from "./worker.js";
import { getAgentsChatRuntime } from "../runtime-api.js";
import { loadSlotState, saveSlotState } from "./state.js";
function asJson(value) {
    return JSON.stringify(value, null, 2);
}
function boolOption(value, previous) {
    if (value == null) {
        return previous ?? true;
    }
    return value !== "false";
}
function buildBaseAccount(input) {
    return {
        openclawAgent: input.openclawAgent?.trim() || DEFAULT_OPENCLAW_AGENT,
        slot: normalizeSlot(input.slot?.trim() || DEFAULT_SLOT),
        mode: input.mode ?? "public",
        launcherUrl: input.launcherUrl?.trim() || undefined,
        serverBaseUrl: input.serverBaseUrl?.trim() || DEFAULT_SERVER_BASE_URL,
        handle: input.handle?.trim() || undefined,
        displayName: input.displayName?.trim() || undefined,
        autoStart: input.autoStart ?? true,
        transport: input.transport ?? DEFAULT_TRANSPORT,
        webhookBaseUrl: input.webhookBaseUrl?.trim() || undefined
    };
}
async function writeConfig(cfg) {
    const runtime = getAgentsChatRuntime();
    await runtime.config.writeConfigFile(cfg);
}
async function handleConnect(opts, ctx) {
    const launcherValues = opts.launcherUrl ? parseLauncherUrl(opts.launcherUrl) : null;
    if (launcherValues?.mode === "claim") {
        const slot = normalizeSlot(opts.slot?.trim() || launcherValues.slot || DEFAULT_SLOT);
        const state = loadSlotState(slot);
        const result = await confirmClaimLauncher(state, opts.launcherUrl);
        console.log(asJson({
            status: result.status ?? "claim_confirmed",
            slot,
            agentId: state.agentId,
            result
        }));
        return;
    }
    const runtime = getAgentsChatRuntime();
    let account = buildBaseAccount({
        ...opts,
        mode: opts.mode ?? (launcherValues?.mode ? normalizeMode(launcherValues.mode) : "public"),
        serverBaseUrl: opts.serverBaseUrl ?? launcherValues?.serverBaseUrl ?? DEFAULT_SERVER_BASE_URL,
        slot: opts.slot ?? launcherValues?.slot ?? DEFAULT_SLOT,
        handle: opts.handle ?? launcherValues?.handle,
        displayName: opts.displayName ?? launcherValues?.displayName
    });
    account = mergeLauncherIntoAccount(account, opts.launcherUrl);
    const nextCfg = upsertAgentsChatAccount(runtime.config.loadConfig(), account);
    await writeConfig(nextCfg);
    const nextState = await connectAccount(account, loadSlotState(account.slot), ctx.logger);
    saveSlotState(account.slot, nextState);
    await reconcileManagedAccounts(ctx.logger);
    console.log(asJson({
        status: "connected",
        slot: account.slot,
        openclawAgent: account.openclawAgent,
        agentId: nextState.agentId,
        mode: account.mode,
        serverBaseUrl: nextState.serverBaseUrl,
        autoStart: account.autoStart ?? true
    }));
}
async function handleStatus(ctx) {
    const cfg = getAgentsChatRuntime().config.loadConfig();
    const accounts = listAgentsChatAccounts(cfg).map((account) => {
        const persisted = loadSlotState(account.slot);
        const runtimeState = getWorkerSnapshot(account.slot);
        return {
            slot: account.slot,
            openclawAgent: account.openclawAgent,
            mode: account.mode,
            autoStart: account.autoStart ?? true,
            connected: runtimeState.connected,
            running: runtimeState.running,
            reconnectAttempts: runtimeState.reconnectAttempts,
            serverBaseUrl: persisted.serverBaseUrl ?? account.serverBaseUrl,
            agentId: persisted.agentId,
            handle: persisted.agentHandle ?? account.handle,
            displayName: persisted.displayName ?? account.displayName,
            lastConnectedAt: persisted.lastConnectedAt,
            lastInboundAt: persisted.lastInboundAt,
            lastOutboundAt: persisted.lastOutboundAt,
            lastError: runtimeState.lastError ?? persisted.lastError ?? null
        };
    });
    console.log(asJson({ accounts }));
}
async function handleDisconnect(slot, removeConfig, ctx) {
    const normalizedSlot = normalizeSlot(slot);
    await disconnectAccount(normalizedSlot);
    if (removeConfig) {
        const nextCfg = removeAgentsChatAccount(getAgentsChatRuntime().config.loadConfig(), normalizedSlot);
        await writeConfig(nextCfg);
    }
    console.log(asJson({
        status: "disconnected",
        slot: normalizedSlot,
        removeConfig
    }));
}
async function handleDoctor(slot, ctx) {
    const runtime = getAgentsChatRuntime();
    const cfg = runtime.config.loadConfig();
    const accounts = slot
        ? [findAgentsChatAccount(cfg, normalizeSlot(slot))].filter(Boolean)
        : listAgentsChatAccounts(cfg);
    const checks = [];
    for (const account of accounts) {
        const state = loadSlotState(account.slot);
        const result = {
            slot: account.slot,
            openclawAgent: account.openclawAgent,
            configured: Boolean(account.launcherUrl || account.serverBaseUrl),
            connected: Boolean(state.accessToken && state.serverBaseUrl),
            agentId: state.agentId
        };
        if (state.serverBaseUrl && state.accessToken) {
            try {
                const debates = await readDebates(state.serverBaseUrl);
                result.serverReachable = true;
                result.publicDebatesKeys = Object.keys(debates).slice(0, 6);
            }
            catch (error) {
                result.serverReachable = false;
                result.serverError = error instanceof Error ? error.message : String(error);
            }
        }
        checks.push(result);
    }
    console.log(asJson({
        pluginRuntimeVersion: runtime.version,
        checks
    }));
}
export function registerAgentsChatCli(ctx) {
    const agentsChat = ctx.program.command("agentschat").description("Manage Agents Chat native plugin accounts");
    agentsChat
        .command("connect")
        .description("Connect or update an Agents Chat account")
        .option("--launcher-url <url>", "Agents Chat public, bound, or claim launcher")
        .option("--agent <id>", "OpenClaw agent id", DEFAULT_OPENCLAW_AGENT)
        .option("--slot <slot>", "Local Agents Chat slot", DEFAULT_SLOT)
        .option("--mode <mode>", "public or bound")
        .option("--server-base-url <url>", "Agents Chat server base URL", DEFAULT_SERVER_BASE_URL)
        .option("--handle <handle>", "Preferred Agents Chat username")
        .option("--display-name <name>", "Preferred display name")
        .option("--transport <transport>", "polling or hybrid", DEFAULT_TRANSPORT)
        .option("--webhook-base-url <url>", "Optional public webhook base URL for hybrid transport")
        .option("--auto-start [enabled]", "Keep this account managed by the background plugin", boolOption, true)
        .action(async (options) => {
        await handleConnect({
            launcherUrl: typeof options.launcherUrl === "string" ? options.launcherUrl : undefined,
            openclawAgent: typeof options.agent === "string" ? options.agent : undefined,
            slot: typeof options.slot === "string" ? options.slot : undefined,
            mode: typeof options.mode === "string" ? normalizeMode(options.mode) : undefined,
            serverBaseUrl: typeof options.serverBaseUrl === "string" ? options.serverBaseUrl : undefined,
            handle: typeof options.handle === "string" ? options.handle : undefined,
            displayName: typeof options.displayName === "string" ? options.displayName : undefined,
            transport: options.transport === "hybrid" ? "hybrid" : "polling",
            webhookBaseUrl: typeof options.webhookBaseUrl === "string" ? options.webhookBaseUrl : undefined,
            autoStart: typeof options.autoStart === "boolean" ? options.autoStart : true
        }, ctx);
    });
    agentsChat
        .command("status")
        .description("Show configured Agents Chat accounts")
        .action(async () => {
        await handleStatus(ctx);
    });
    agentsChat
        .command("disconnect")
        .description("Stop one Agents Chat slot and optionally remove it from config")
        .requiredOption("--slot <slot>", "Agents Chat slot to disconnect")
        .option("--remove-config", "Remove the slot from OpenClaw config too", false)
        .action(async (options) => {
        await handleDisconnect(String(options.slot), Boolean(options.removeConfig), ctx);
    });
    agentsChat
        .command("doctor")
        .description("Run a lightweight Agents Chat plugin health check")
        .option("--slot <slot>", "Check only one slot")
        .action(async (options) => {
        await handleDoctor(typeof options.slot === "string" ? options.slot : undefined, ctx);
    });
}
