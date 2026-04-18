import { DEFAULT_OPENCLAW_AGENT, DEFAULT_SERVER_BASE_URL, DEFAULT_SLOT, DEFAULT_TRANSPORT } from "./constants.js";
function asRecord(value) {
    return value != null && typeof value === "object" ? value : {};
}
function normalizeOptionalString(value) {
    if (typeof value !== "string") {
        return undefined;
    }
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : undefined;
}
function normalizeMode(value) {
    return value === "bound" ? "bound" : "public";
}
function normalizeTransport(value) {
    return value === "hybrid" ? "hybrid" : "polling";
}
function normalizeBoolean(value, fallback) {
    return typeof value === "boolean" ? value : fallback;
}
export function getAgentsChatChannelSection(cfg) {
    const channels = asRecord(cfg.channels);
    return asRecord(channels.agentschat);
}
export function listAgentsChatAccounts(cfg) {
    const section = getAgentsChatChannelSection(cfg);
    if (!Array.isArray(section.accounts)) {
        return [];
    }
    const accounts = [];
    for (const raw of section.accounts) {
        const record = asRecord(raw);
        const slot = normalizeOptionalString(record.slot);
        if (!slot) {
            continue;
        }
        accounts.push({
            openclawAgent: normalizeOptionalString(record.openclawAgent) ?? DEFAULT_OPENCLAW_AGENT,
            slot,
            mode: normalizeMode(record.mode),
            launcherUrl: normalizeOptionalString(record.launcherUrl),
            serverBaseUrl: normalizeOptionalString(record.serverBaseUrl),
            handle: normalizeOptionalString(record.handle),
            displayName: normalizeOptionalString(record.displayName),
            autoStart: normalizeBoolean(record.autoStart, true),
            transport: normalizeTransport(record.transport),
            webhookBaseUrl: normalizeOptionalString(record.webhookBaseUrl)
        });
    }
    return accounts;
}
export function resolveAgentsChatAccount(cfg, accountId) {
    const accounts = listAgentsChatAccounts(cfg);
    const requestedId = normalizeOptionalString(accountId) ?? accounts[0]?.slot ?? DEFAULT_SLOT;
    return accounts.find((account) => account.slot === requestedId) ?? {
        openclawAgent: DEFAULT_OPENCLAW_AGENT,
        slot: requestedId,
        mode: "public",
        serverBaseUrl: DEFAULT_SERVER_BASE_URL,
        autoStart: true,
        transport: DEFAULT_TRANSPORT
    };
}
export function findAgentsChatAccount(cfg, slot) {
    return listAgentsChatAccounts(cfg).find((account) => account.slot === slot);
}
export function isConfiguredAgentsChatAccount(account) {
    if (account.mode === "bound") {
        return typeof account.launcherUrl === "string" && account.launcherUrl.length > 0;
    }
    return typeof account.serverBaseUrl === "string" && account.serverBaseUrl.length > 0;
}
export function hasAgentsChatConfiguredState(cfg) {
    return listAgentsChatAccounts(cfg).some(isConfiguredAgentsChatAccount);
}
export function upsertAgentsChatAccount(cfg, account) {
    const nextCfg = structuredClone(cfg);
    if (nextCfg.channels == null || typeof nextCfg.channels !== "object") {
        nextCfg.channels = {};
    }
    const channels = nextCfg.channels;
    const section = asRecord(channels.agentschat);
    const nextAccounts = Array.isArray(section.accounts) ? [...section.accounts] : [];
    const serialized = {
        openclawAgent: account.openclawAgent,
        slot: account.slot,
        mode: account.mode,
        launcherUrl: account.launcherUrl,
        serverBaseUrl: account.serverBaseUrl,
        handle: account.handle,
        displayName: account.displayName,
        autoStart: account.autoStart ?? true,
        transport: account.transport ?? DEFAULT_TRANSPORT,
        webhookBaseUrl: account.webhookBaseUrl
    };
    const existingIndex = nextAccounts.findIndex((entry) => asRecord(entry).slot === account.slot);
    if (existingIndex >= 0) {
        nextAccounts[existingIndex] = serialized;
    }
    else {
        nextAccounts.push(serialized);
    }
    channels.agentschat = {
        ...section,
        accounts: nextAccounts
    };
    return nextCfg;
}
export function removeAgentsChatAccount(cfg, slot) {
    const nextCfg = structuredClone(cfg);
    if (nextCfg.channels == null || typeof nextCfg.channels !== "object") {
        return nextCfg;
    }
    const channels = nextCfg.channels;
    const section = asRecord(channels.agentschat);
    const accounts = Array.isArray(section.accounts) ? section.accounts : [];
    channels.agentschat = {
        ...section,
        accounts: accounts.filter((entry) => asRecord(entry).slot !== slot)
    };
    return nextCfg;
}
export function setAgentsChatAccountEnabled(cfg, slot, enabled) {
    const account = resolveAgentsChatAccount(cfg, slot);
    return upsertAgentsChatAccount(cfg, {
        ...account,
        autoStart: enabled
    });
}
export function accountFingerprint(account) {
    return JSON.stringify({
        openclawAgent: account.openclawAgent,
        slot: account.slot,
        mode: account.mode,
        launcherUrl: account.launcherUrl,
        serverBaseUrl: account.serverBaseUrl,
        handle: account.handle,
        displayName: account.displayName,
        autoStart: account.autoStart ?? true,
        transport: account.transport ?? DEFAULT_TRANSPORT,
        webhookBaseUrl: account.webhookBaseUrl
    });
}
function validateAccount(value, index) {
    const issues = [];
    const record = asRecord(value);
    const slot = normalizeOptionalString(record.slot);
    const openclawAgent = normalizeOptionalString(record.openclawAgent);
    if (!slot) {
        issues.push({
            path: ["accounts", index, "slot"],
            message: "slot is required"
        });
    }
    if (!openclawAgent) {
        issues.push({
            path: ["accounts", index, "openclawAgent"],
            message: "openclawAgent is required"
        });
    }
    if (record.mode !== "public" && record.mode !== "bound") {
        issues.push({
            path: ["accounts", index, "mode"],
            message: "mode must be public or bound"
        });
    }
    if (record.transport != null && record.transport !== "polling" && record.transport !== "hybrid") {
        issues.push({
            path: ["accounts", index, "transport"],
            message: "transport must be polling or hybrid"
        });
    }
    return issues;
}
function validateSection(value) {
    const record = asRecord(value);
    const issues = [];
    const accounts = record.accounts;
    if (accounts != null && !Array.isArray(accounts)) {
        issues.push({
            path: ["accounts"],
            message: "accounts must be an array"
        });
    }
    if (Array.isArray(accounts)) {
        const seenSlots = new Set();
        accounts.forEach((account, index) => {
            issues.push(...validateAccount(account, index));
            const slot = normalizeOptionalString(asRecord(account).slot);
            if (slot) {
                if (seenSlots.has(slot)) {
                    issues.push({
                        path: ["accounts", index, "slot"],
                        message: "slot must be unique"
                    });
                }
                seenSlots.add(slot);
            }
        });
    }
    if (issues.length > 0) {
        return {
            success: false,
            issues
        };
    }
    return {
        success: true,
        data: value
    };
}
const configSchemaJson = {
    type: "object",
    additionalProperties: false,
    properties: {
        accounts: {
            type: "array",
            items: {
                type: "object",
                additionalProperties: false,
                required: ["openclawAgent", "slot", "mode"],
                properties: {
                    openclawAgent: { type: "string", minLength: 1 },
                    slot: { type: "string", minLength: 1 },
                    mode: { type: "string", enum: ["public", "bound"] },
                    launcherUrl: { type: "string" },
                    serverBaseUrl: { type: "string" },
                    handle: { type: "string" },
                    displayName: { type: "string" },
                    autoStart: { type: "boolean", default: true },
                    transport: { type: "string", enum: ["polling", "hybrid"], default: "polling" },
                    webhookBaseUrl: { type: "string" }
                }
            }
        }
    }
};
export const agentsChatChannelConfigSchema = {
    schema: configSchemaJson,
    runtime: {
        safeParse: validateSection
    }
};
export const agentsChatConfigAdapter = {
    listAccountIds: (cfg) => listAgentsChatAccounts(cfg).map((account) => account.slot),
    resolveAccount: (cfg, accountId) => resolveAgentsChatAccount(cfg, accountId),
    inspectAccount: (cfg, accountId) => resolveAgentsChatAccount(cfg, accountId),
    defaultAccountId: (cfg) => listAgentsChatAccounts(cfg)[0]?.slot ?? DEFAULT_SLOT,
    setAccountEnabled: ({ cfg, accountId, enabled }) => setAgentsChatAccountEnabled(cfg, accountId, enabled),
    deleteAccount: ({ cfg, accountId }) => removeAgentsChatAccount(cfg, accountId),
    isEnabled: (account) => account.autoStart !== false,
    disabledReason: () => "autoStart is disabled",
    isConfigured: (account) => isConfiguredAgentsChatAccount(account),
    unconfiguredReason: (account) => {
        return account.mode === "bound"
            ? "bound mode requires launcherUrl"
            : "public mode requires serverBaseUrl";
    },
    describeAccount: (account) => {
        const snapshot = {
            accountId: account.slot,
            name: account.displayName ?? account.slot,
            enabled: account.autoStart !== false,
            configured: isConfiguredAgentsChatAccount(account),
            mode: account.mode,
            baseUrl: account.serverBaseUrl ?? DEFAULT_SERVER_BASE_URL
        };
        return snapshot;
    },
    hasConfiguredState: ({ cfg }) => hasAgentsChatConfiguredState(cfg)
};
export const agentsChatSetupAdapter = {
    resolveAccountId: ({ accountId, input }) => {
        const requested = normalizeOptionalString(accountId) ?? normalizeOptionalString(asRecord(input).slot);
        return requested ?? DEFAULT_SLOT;
    },
    applyAccountConfig: ({ cfg, accountId, input }) => {
        const record = asRecord(input);
        return upsertAgentsChatAccount(cfg, {
            openclawAgent: normalizeOptionalString(record.openclawAgent) ?? DEFAULT_OPENCLAW_AGENT,
            slot: accountId,
            mode: normalizeMode(record.mode),
            launcherUrl: normalizeOptionalString(record.launcherUrl),
            serverBaseUrl: normalizeOptionalString(record.serverBaseUrl) ?? DEFAULT_SERVER_BASE_URL,
            handle: normalizeOptionalString(record.handle),
            displayName: normalizeOptionalString(record.displayName),
            autoStart: normalizeBoolean(record.autoStart, true),
            transport: normalizeTransport(record.transport),
            webhookBaseUrl: normalizeOptionalString(record.webhookBaseUrl)
        });
    },
    validateInput: ({ accountId }) => {
        return accountId.trim().length > 0 ? null : "slot is required";
    }
};
