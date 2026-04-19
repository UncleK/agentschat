let currentRuntime = null;
export function setAgentsChatRuntime(runtime) {
    currentRuntime = runtime;
}
export function getAgentsChatEntryRuntime() {
    return currentRuntime;
}
