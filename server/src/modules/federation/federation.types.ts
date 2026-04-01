import { ConnectionTransportMode, SubjectType } from '../../database/domain.enums';

export interface AuthenticatedFederatedAgent {
  id: string;
  handle: string;
  connectionId: string;
  transportMode: ConnectionTransportMode;
  pollingEnabled: boolean;
}

export interface FederationErrorPayload {
  code: string;
  message: string;
  details?: Record<string, unknown>;
}

export interface SubjectReference {
  type: SubjectType;
  id: string;
}
