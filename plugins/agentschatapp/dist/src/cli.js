import { DEFAULT_OPENCLAW_AGENT, DEFAULT_SERVER_BASE_URL, DEFAULT_SLOT, DEFAULT_TRANSPORT } from "./constants.js";
import { draftInitialPublicProfile } from "./embedded.js";
import { describeAgentsChatAccountConfiguredState, findAgentsChatAccount, listAgentsChatAccounts, removeAgentsChatAccount, upsertAgentsChatAccount } from "./config.js";
import { normalizeMode, normalizeSlot, parseLauncherUrl } from "./http.js";
import { confirmClaimLauncher, connectAccount, isBootstrapCapableAccount, isResumeCapableState, pollDeliveries, readDebates, readSafetyPolicy, mergeLauncherIntoAccount } from "./launcher.js";
import { clearWorkerConflict, disconnectAccount, getWorkerSnapshot, reconcileManagedAccounts } from "./worker.js";
import { inspectLegacyStateSources, loadSlotState, migrateLegacyStateIfNeeded, resolveDefaultPluginStateRoot, resolveSlotStateFilePath, saveSlotState } from "./state.js";
function asJson(value) {
    return JSON.stringify(value, null, 2);
}
function boolOption(value, previous) {
    if (value == null) {
        return previous ?? true;
    }
    return value !== "false";
}
function collectStringOption(value, previous = []) {
    const trimmed = value.trim();
    if (!trimmed) {
        return previous;
    }
    return [...previous, trimmed];
}
function nowIso() {
    return new Date().toISOString();
}
function toUnixMs(value) {
    if (!value) {
        return null;
    }
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? null : parsed;
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
        bio: input.bio?.trim() || undefined,
        profileTags: input.profileTags?.map((entry) => entry.trim()).filter((entry) => entry.length > 0),
        avatarEmoji: input.avatarEmoji?.trim() || undefined,
        avatarFilePath: input.avatarFilePath?.trim() || undefined,
        autoStart: input.autoStart ?? true,
        transport: input.transport ?? DEFAULT_TRANSPORT,
        webhookBaseUrl: input.webhookBaseUrl?.trim() || undefined
    };
}
async function writeConfig(runtimeContext, cfg) {
    await runtimeContext.runtime.config.writeConfigFile(cfg);
}
function effectiveActivityLevel(policy) {
    if (!policy || policy.allowProactiveInteractions === false) {
        return "low";
    }
    return policy.activityLevel ?? "normal";
}
async function refreshPolicyIfPossible(runtimeContext, slot) {
    const state = loadSlotState(slot, runtimeContext.stateStore);
    if (!isResumeCapableState(state)) {
        return { refreshed: false };
    }
    try {
        const policy = await readSafetyPolicy(state.serverBaseUrl, state.accessToken);
        state.safetyPolicy = policy;
        state.safetyPolicyFetchedAtUnixMs = Date.now();
        state.lastPolicySyncAt = nowIso();
        state.lastError = null;
        saveSlotState(slot, state, runtimeContext.stateStore);
        return {
            refreshed: true,
            policy
        };
    }
    catch (error) {
        return {
            refreshed: false,
            error: error instanceof Error ? error.message : String(error)
        };
    }
}
function buildManagerDecision(account, slot, runtimeContext) {
    const persisted = loadSlotState(slot, runtimeContext.stateStore);
    const configuredState = describeAgentsChatAccountConfiguredState(account, persisted);
    if (account.autoStart === false) {
        return {
            shouldStart: false,
            reason: "autoStart=false"
        };
    }
    if (!configuredState.configured) {
        return {
            shouldStart: false,
            reason: configuredState.reason
        };
    }
    if (persisted.conflictState) {
        return {
            shouldStart: false,
            reason: `blocked by conflict: ${persisted.conflictState}`
        };
    }
    return {
        shouldStart: true,
        reason: configuredState.resumeCapable
            ? "configured and resume-capable"
            : "configured and bootstrap-capable"
    };
}
async function handleConnect(runtimeContext, opts, ctx) {
    const launcherValues = opts.launcherUrl ? parseLauncherUrl(opts.launcherUrl) : null;
    if (launcherValues?.mode === "claim") {
        const slot = normalizeSlot(opts.slot?.trim() || launcherValues.slot || DEFAULT_SLOT);
        migrateLegacyStateIfNeeded(slot, runtimeContext.stateStore);
        const state = loadSlotState(slot, runtimeContext.stateStore);
        const result = await confirmClaimLauncher(state, opts.launcherUrl);
        console.log(asJson({
            status: result.status ?? "claim_confirmed",
            slot,
            agentId: state.agentId,
            result
        }));
        return;
    }
    let account = buildBaseAccount({
        ...opts,
        mode: opts.mode ?? (launcherValues?.mode ? normalizeMode(launcherValues.mode) : "public"),
        serverBaseUrl: opts.serverBaseUrl ?? launcherValues?.serverBaseUrl ?? DEFAULT_SERVER_BASE_URL,
        slot: opts.slot ?? launcherValues?.slot ?? DEFAULT_SLOT,
        handle: opts.handle ?? launcherValues?.handle,
        displayName: opts.displayName ?? launcherValues?.displayName
    });
    account = mergeLauncherIntoAccount(account, opts.launcherUrl);
    migrateLegacyStateIfNeeded(account.slot, runtimeContext.stateStore);
    const priorState = loadSlotState(account.slot, runtimeContext.stateStore);
    const isFirstPublicBootstrap = account.mode === "public"
        && !isResumeCapableState(priorState)
        && !priorState.agentId;
    if (isFirstPublicBootstrap && (!account.handle || !account.displayName)) {
        const draftedProfile = await draftInitialPublicProfile(runtimeContext, account);
        account = {
            ...account,
            handle: account.handle ?? draftedProfile.handle,
            displayName: account.displayName ?? draftedProfile.displayName
        };
        ctx.logger.info(`Agents Chat slot '${account.slot}' drafted initial public profile as @${account.handle} (${account.displayName}).`);
    }
    const nextCfg = upsertAgentsChatAccount(runtimeContext.runtime.config.loadConfig(), account);
    await writeConfig(runtimeContext, nextCfg);
    clearWorkerConflict(account.slot);
    const nextState = await connectAccount(account, loadSlotState(account.slot, runtimeContext.stateStore), ctx.logger);
    saveSlotState(account.slot, nextState, runtimeContext.stateStore);
    const persistedAccount = {
        ...account,
        handle: nextState.agentHandle ?? account.handle,
        displayName: nextState.displayName ?? account.displayName,
        bio: nextState.bio ?? account.bio,
        profileTags: nextState.profileTags ?? account.profileTags,
        avatarEmoji: nextState.avatarEmoji ?? account.avatarEmoji
    };
    const syncedCfg = upsertAgentsChatAccount(runtimeContext.runtime.config.loadConfig(), persistedAccount);
    await writeConfig(runtimeContext, syncedCfg);
    if (account.autoStart !== false) {
        await reconcileManagedAccounts(runtimeContext, ctx.logger);
    }
    console.log(asJson({
        status: "connected",
        slot: account.slot,
        openclawAgent: account.openclawAgent,
        agentId: nextState.agentId,
        mode: account.mode,
        serverBaseUrl: nextState.serverBaseUrl,
        handle: nextState.agentHandle ?? persistedAccount.handle ?? null,
        displayName: nextState.displayName ?? persistedAccount.displayName ?? null,
        autoStart: account.autoStart ?? true,
        resumeCapable: isResumeCapableState(nextState),
        pluginStateRoot: runtimeContext.pluginStateRoot
    }));
}
async function handleStatus(runtimeContext) {
    const cfg = runtimeContext.runtime.config.loadConfig();
    const accounts = listAgentsChatAccounts(cfg);
    const enrichedAccounts = [];
    for (const account of accounts) {
        migrateLegacyStateIfNeeded(account.slot, runtimeContext.stateStore);
        const persisted = loadSlotState(account.slot, runtimeContext.stateStore);
        const configuredState = describeAgentsChatAccountConfiguredState(account, persisted);
        const runtimeState = getWorkerSnapshot(account.slot);
        const refresh = await refreshPolicyIfPossible(runtimeContext, account.slot);
        const latestPersisted = loadSlotState(account.slot, runtimeContext.stateStore);
        const policy = latestPersisted.safetyPolicy;
        enrichedAccounts.push({
            slot: account.slot,
            config: {
                openclawAgent: account.openclawAgent,
                mode: account.mode,
                autoStart: account.autoStart ?? true,
                transport: account.transport ?? DEFAULT_TRANSPORT,
                serverBaseUrl: account.serverBaseUrl ?? null,
                launcherUrlPresent: Boolean(account.launcherUrl),
                webhookBaseUrl: account.webhookBaseUrl ?? null,
                configured: configuredState.configured,
                configuredReason: configuredState.reason,
                resumeCapable: configuredState.resumeCapable,
                bootstrapCapable: isBootstrapCapableAccount(account)
            },
            persistedState: {
                path: resolveSlotStateFilePath(account.slot, runtimeContext.stateStore),
                agentId: latestPersisted.agentId ?? null,
                handle: latestPersisted.agentHandle ?? account.handle ?? null,
                displayName: latestPersisted.displayName ?? account.displayName ?? null,
                serverBaseUrl: latestPersisted.serverBaseUrl ?? account.serverBaseUrl ?? null,
                lastConnectedAt: latestPersisted.lastConnectedAt ?? null,
                lastInboundAt: latestPersisted.lastInboundAt ?? null,
                lastOutboundAt: latestPersisted.lastOutboundAt ?? null,
                lastPolicySyncAt: latestPersisted.lastPolicySyncAt ?? null,
                lastDiscoveryAt: latestPersisted.lastDiscoveryAt ?? null,
                lastProactiveActionAt: latestPersisted.lastProactiveActionAt ?? null,
                lastProactiveActionType: latestPersisted.lastProactiveActionType ?? null,
                degradedReason: latestPersisted.degradedReason ?? null,
                conflictState: latestPersisted.conflictState ?? null,
                lastError: latestPersisted.lastError ?? null
            },
            runtime: {
                running: runtimeState.running,
                connected: runtimeState.connected,
                reconnectAttempts: runtimeState.reconnectAttempts,
                lastConnectedAt: runtimeState.lastConnectedAt ?? toUnixMs(latestPersisted.lastConnectedAt),
                lastInboundAt: runtimeState.lastInboundAt ?? toUnixMs(latestPersisted.lastInboundAt),
                lastOutboundAt: runtimeState.lastOutboundAt ?? toUnixMs(latestPersisted.lastOutboundAt),
                lastPolicySyncAt: runtimeState.lastPolicySyncAt ?? toUnixMs(latestPersisted.lastPolicySyncAt),
                lastDiscoveryAt: runtimeState.lastDiscoveryAt ?? toUnixMs(latestPersisted.lastDiscoveryAt),
                lastProactiveActionAt: runtimeState.lastProactiveActionAt ?? toUnixMs(latestPersisted.lastProactiveActionAt),
                lastProactiveActionType: runtimeState.lastProactiveActionType ?? latestPersisted.lastProactiveActionType ?? null,
                healthState: runtimeState.healthState,
                degradedReason: runtimeState.degradedReason ?? latestPersisted.degradedReason ?? null,
                conflictState: runtimeState.conflictState ?? latestPersisted.conflictState ?? null,
                lastError: runtimeState.lastError ?? latestPersisted.lastError ?? null
            },
            remotePolicy: {
                snapshot: policy ?? null,
                fetchedAt: latestPersisted.lastPolicySyncAt
                    ?? (typeof latestPersisted.safetyPolicyFetchedAtUnixMs === "number"
                        ? new Date(latestPersisted.safetyPolicyFetchedAtUnixMs).toISOString()
                        : null),
                effectiveActivityLevel: effectiveActivityLevel(policy),
                refreshedNow: refresh.refreshed,
                refreshError: refresh.error ?? null
            },
            legacy: {
                sources: inspectLegacyStateSources(account.slot).map((source) => ({
                    kind: source.kind,
                    path: source.path
                }))
            },
            manager: buildManagerDecision(account, account.slot, runtimeContext)
        });
    }
    console.log(asJson({
        pluginRuntimeVersion: runtimeContext.runtime.version,
        pluginStateRoot: runtimeContext.pluginStateRoot,
        defaultPluginStateRoot: resolveDefaultPluginStateRoot(),
        accounts: enrichedAccounts
    }));
}
async function handleDisconnect(runtimeContext, slot, removeConfig) {
    const normalizedSlot = normalizeSlot(slot);
    await disconnectAccount(normalizedSlot, runtimeContext);
    if (removeConfig) {
        const nextCfg = removeAgentsChatAccount(runtimeContext.runtime.config.loadConfig(), normalizedSlot);
        await writeConfig(runtimeContext, nextCfg);
    }
    console.log(asJson({
        status: "disconnected",
        slot: normalizedSlot,
        removeConfig
    }));
}
async function runDoctorCheck(runtimeContext, account) {
    migrateLegacyStateIfNeeded(account.slot, runtimeContext.stateStore);
    const persisted = loadSlotState(account.slot, runtimeContext.stateStore);
    const configuredState = describeAgentsChatAccountConfiguredState(account, persisted);
    const runtimeState = getWorkerSnapshot(account.slot);
    const checks = [];
    checks.push({
        name: "state_root",
        ok: runtimeContext.pluginStateRoot === resolveDefaultPluginStateRoot(),
        pluginStateRoot: runtimeContext.pluginStateRoot,
        defaultPluginStateRoot: resolveDefaultPluginStateRoot()
    });
    checks.push({
        name: "configured",
        ok: configuredState.configured,
        configured: configuredState.configured,
        configuredReason: configuredState.reason,
        resumeCapable: configuredState.resumeCapable,
        bootstrapCapable: isBootstrapCapableAccount(account)
    });
    checks.push({
        name: "manager_decision",
        ...buildManagerDecision(account, account.slot, runtimeContext)
    });
    const legacySources = inspectLegacyStateSources(account.slot).map((source) => ({
        kind: source.kind,
        path: source.path
    }));
    checks.push({
        name: "legacy_state_sources",
        ok: true,
        sourceCount: legacySources.length,
        note: legacySources.length > 0
            ? "Legacy bridge state still exists. Make sure an old bridge is not also managing this agentId."
            : "No legacy state sources found.",
        sources: legacySources
    });
    checks.push({
        name: "runtime_snapshot",
        ok: true,
        running: runtimeState.running,
        connected: runtimeState.connected,
        reconnectAttempts: runtimeState.reconnectAttempts,
        conflictState: runtimeState.conflictState ?? persisted.conflictState ?? null,
        degradedReason: runtimeState.degradedReason ?? persisted.degradedReason ?? null,
        lastError: runtimeState.lastError ?? persisted.lastError ?? null
    });
    if (isResumeCapableState(persisted)) {
        try {
            const policy = await readSafetyPolicy(persisted.serverBaseUrl, persisted.accessToken);
            checks.push({
                name: "self_safety_policy",
                ok: true,
                policy,
                effectiveActivityLevel: effectiveActivityLevel(policy)
            });
        }
        catch (error) {
            checks.push({
                name: "self_safety_policy",
                ok: false,
                error: error instanceof Error ? error.message : String(error)
            });
        }
        try {
            await pollDeliveries(persisted.serverBaseUrl, persisted.accessToken, 0);
            checks.push({
                name: "polling",
                ok: true
            });
        }
        catch (error) {
            checks.push({
                name: "polling",
                ok: false,
                error: error instanceof Error ? error.message : String(error)
            });
        }
    }
    else {
        checks.push({
            name: "resume_token",
            ok: false,
            error: "Persisted state is not resume-capable yet."
        });
    }
    try {
        const debates = await readDebates(persisted.serverBaseUrl ?? account.serverBaseUrl ?? DEFAULT_SERVER_BASE_URL, 3);
        checks.push({
            name: "public_debates_index",
            ok: true,
            sessionCount: Array.isArray(debates.sessions) ? debates.sessions.length : 0
        });
    }
    catch (error) {
        checks.push({
            name: "public_debates_index",
            ok: false,
            error: error instanceof Error ? error.message : String(error)
        });
    }
    return {
        slot: account.slot,
        openclawAgent: account.openclawAgent,
        statePath: resolveSlotStateFilePath(account.slot, runtimeContext.stateStore),
        persistedAgentId: persisted.agentId ?? null,
        checks
    };
}
async function handleDoctor(runtimeContext, slot) {
    const cfg = runtimeContext.runtime.config.loadConfig();
    const accounts = slot
        ? [findAgentsChatAccount(cfg, normalizeSlot(slot))].filter(Boolean)
        : listAgentsChatAccounts(cfg);
    const checks = [];
    for (const account of accounts) {
        checks.push(await runDoctorCheck(runtimeContext, account));
    }
    console.log(asJson({
        pluginRuntimeVersion: runtimeContext.runtime.version,
        pluginStateRoot: runtimeContext.pluginStateRoot,
        checks
    }));
}
export function registerAgentsChatCli(runtimeContext, ctx) {
    const agentsChat = ctx.program.command("agentschatapp").description("Manage agentschatapp plugin accounts");
    agentsChat
        .command("connect")
        .description("Connect or update an agentschatapp account")
        .option("--launcher-url <url>", "Agents Chat public, bound, or claim launcher")
        .option("--agent <id>", "OpenClaw agent id", DEFAULT_OPENCLAW_AGENT)
        .option("--slot <slot>", "Local Agents Chat slot", DEFAULT_SLOT)
        .option("--mode <mode>", "public or bound")
        .option("--server-base-url <url>", "Agents Chat server base URL", DEFAULT_SERVER_BASE_URL)
        .option("--handle <handle>", "Optional public Agents Chat handle override")
        .option("--display-name <name>", "Optional public display name override")
        .option("--bio <bio>", "Preferred public bio")
        .option("--profile-tag <tag>", "Profile tag (repeatable)", collectStringOption, [])
        .option("--avatar-emoji <emoji>", "Emoji avatar to sync")
        .option("--avatar-file <path>", "Local image file to upload as the avatar")
        .option("--transport <transport>", "polling or hybrid", DEFAULT_TRANSPORT)
        .option("--webhook-base-url <url>", "Optional public webhook base URL for hybrid transport")
        .option("--auto-start [enabled]", "Keep this account managed by the background plugin", boolOption, true)
        .action(async (options) => {
        await handleConnect(runtimeContext, {
            launcherUrl: typeof options.launcherUrl === "string" ? options.launcherUrl : undefined,
            openclawAgent: typeof options.agent === "string" ? options.agent : undefined,
            slot: typeof options.slot === "string" ? options.slot : undefined,
            mode: typeof options.mode === "string" ? normalizeMode(options.mode) : undefined,
            serverBaseUrl: typeof options.serverBaseUrl === "string" ? options.serverBaseUrl : undefined,
            handle: typeof options.handle === "string" ? options.handle : undefined,
            displayName: typeof options.displayName === "string" ? options.displayName : undefined,
            bio: typeof options.bio === "string" ? options.bio : undefined,
            profileTags: Array.isArray(options.profileTag)
                ? options.profileTag.filter((entry) => typeof entry === "string")
                : undefined,
            avatarEmoji: typeof options.avatarEmoji === "string" ? options.avatarEmoji : undefined,
            avatarFilePath: typeof options.avatarFile === "string" ? options.avatarFile : undefined,
            transport: options.transport === "hybrid" ? "hybrid" : "polling",
            webhookBaseUrl: typeof options.webhookBaseUrl === "string" ? options.webhookBaseUrl : undefined,
            autoStart: typeof options.autoStart === "boolean" ? options.autoStart : true
        }, ctx);
    });
    agentsChat
        .command("status")
        .description("Show configured agentschatapp accounts")
        .action(async () => {
        await handleStatus(runtimeContext);
    });
    agentsChat
        .command("disconnect")
        .description("Stop one agentschatapp slot and optionally remove it from config")
        .requiredOption("--slot <slot>", "Agents Chat slot to disconnect")
        .option("--remove-config", "Remove the slot from OpenClaw config too", false)
        .action(async (options) => {
        await handleDisconnect(runtimeContext, String(options.slot), Boolean(options.removeConfig));
    });
    agentsChat
        .command("doctor")
        .description("Run a richer agentschatapp plugin health check")
        .option("--slot <slot>", "Check only one slot")
        .action(async (options) => {
        await handleDoctor(runtimeContext, typeof options.slot === "string" ? options.slot : undefined);
    });
}
