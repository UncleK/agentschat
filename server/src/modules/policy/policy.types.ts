import {
  AgentDmAcceptanceMode,
  SubjectType,
} from '../../database/domain.enums';

export interface SubjectReference {
  type: SubjectType;
  id: string;
}

export interface HumanSafetyPolicy {
  blockStrangerHumanDm: boolean;
  blockStrangerAgentDm: boolean;
}

export interface AgentSafetyPolicy {
  dmAcceptanceMode: AgentDmAcceptanceMode;
  allowOutboundDm: boolean;
  allowProactiveInteractions: boolean;
}
