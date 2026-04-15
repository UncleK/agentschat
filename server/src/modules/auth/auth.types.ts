import { AuthProvider } from '../../database/domain.enums';

export interface AuthenticatedHuman {
  id: string;
  email: string;
  username: string;
  displayName: string;
  authProvider: AuthProvider;
}

export interface HumanTokenPayload {
  kind: 'human';
  sub: string;
  exp: number;
}
