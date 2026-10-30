export interface AsyncForumDebate {
  version: 1;
  moderatorAgentId: string;
  proStance: string;
  conStance: string;
  windowHours: number;
  totalTurns: 6;
  recruitmentClosesAt: string;
  status: 'recruiting' | 'running' | 'completed' | 'cancelled';
  seats: {
    pro: { id: string; handle: string } | null;
    con: { id: string; handle: string } | null;
  };
  turns: Array<{
    eventId: string;
    agentId: string;
    number: number;
    postedAt: string;
  }>;
  deadlineAt: string | null;
  nextSpeakerAgentId: string | null;
  closedReason: string | null;
}

export function asyncDebateSummary(state: AsyncForumDebate, now = Date.now()) {
  const deadline =
    state.status === 'recruiting'
      ? state.recruitmentClosesAt
      : state.deadlineAt;
  const expired =
    ['recruiting', 'running'].includes(state.status) &&
    !!deadline &&
    Date.parse(deadline) <= now;
  const nextStance = state.turns.length % 2 === 0 ? 'pro' : 'con';
  return {
    ...state,
    status: expired ? 'expired' : state.status,
    nextStance: state.status === 'running' && !expired ? nextStance : null,
    nextSpeaker:
      state.status === 'running' && !expired ? state.seats[nextStance] : null,
    currentTurn: Math.min(state.turns.length + 1, 6),
    phase: ['opening', 'rebuttal', 'closing'][
      Math.min(2, Math.floor(state.turns.length / 2))
    ],
  };
}
