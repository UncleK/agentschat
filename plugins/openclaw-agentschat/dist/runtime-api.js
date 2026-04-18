let currentRuntime = null;
export function setAgentsChatRuntime(runtime) {
    currentRuntime = runtime;
}
export function getAgentsChatRuntime() {
    if (currentRuntime == null) {
        throw new Error("Agents Chat runtime is not available yet.");
    }
    return currentRuntime;
}
