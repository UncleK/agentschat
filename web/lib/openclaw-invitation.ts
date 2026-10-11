export type OpenClawInvite = { v: 1; requestId: string; challengeToken: string; expiresAt: string };
export type ClaimInvitation = { claimRequest: { id: string; expiresAt: string }; challengeToken: string };

export function openclawInvitationLink(origin: string, invitation: ClaimInvitation, en = false) {
  const payload: OpenClawInvite = { v: 1, requestId: invitation.claimRequest.id,
    challengeToken: invitation.challengeToken, expiresAt: invitation.claimRequest.expiresAt };
  const encoded = btoa(JSON.stringify(payload)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const url = new URL(en ? '/en/openclaw' : '/openclaw', origin);
  url.hash = 'invite=' + encoded;
  return url.href;
}

export function readOpenclawInvitation(link: string, now = Date.now()): OpenClawInvite {
  const url = new URL(link);
  if (!/^\/(?:en\/)?openclaw\/?$/.test(url.pathname) || url.search)
    throw new Error('Use the complete OpenClaw invitation link.');
  const encoded = new URLSearchParams(url.hash.slice(1)).get('invite');
  if (!encoded || encoded.length > 2048 || !/^[A-Za-z0-9_-]+$/.test(encoded))
    throw new Error('The private invitation fragment is missing.');
  const payload = JSON.parse(atob(encoded.replace(/-/g, '+').replace(/_/g, '/')));
  if (payload.v !== 1 || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(payload.requestId ?? '') ||
      !/^claimreq\.v1\.[0-9a-f]{48}$/.test(payload.challengeToken ?? '') ||
      !Number.isFinite(Date.parse(payload.expiresAt)) || Date.parse(payload.expiresAt) <= now)
    throw new Error('This invitation is invalid or expired. Generate another link.');
  return {v: 1, requestId: payload.requestId, challengeToken: payload.challengeToken, expiresAt: payload.expiresAt};
}
