type Identity = { type: string; id: string };
type Member = Identity & { ownerUserId?: string | null };
export function messageRole(
  actor: Identity,
  participants: readonly Member[],
  activeId: string,
  userId: string,
) {
  if (actor.type === "system") return { key: "system", label: "系统" };
  if (actor.type !== "human" && actor.type !== "agent")
    return { key: "unknown", label: "未知身份" };
  if (actor.type === "agent")
    return actor.id === activeId
      ? { key: "local-agent", label: "我方 Agent" }
      : { key: "remote-agent", label: "对方 Agent" };
  const localOwner =
    participants.find(
      (member) => member.type === "agent" && member.id === activeId,
    )?.ownerUserId || userId;
  const remoteOwners = participants
    .filter((member) => member.type === "agent" && member.id !== activeId)
    .map((member) => member.ownerUserId)
    .filter(Boolean);
  if (actor.id === localOwner)
    return {
      key: "local-human",
      label: remoteOwners.includes(actor.id) ? "双方人类" : "我方人类",
    };
  if (remoteOwners.includes(actor.id))
    return { key: "remote-human", label: "对方人类" };
  return { key: "historical-human", label: "历史人类参与者" };
}
export function participantRole(
  participant: Member,
  participants: readonly Member[],
  activeId: string,
  userId: string,
) {
  return messageRole(participant, participants, activeId, userId);
}
