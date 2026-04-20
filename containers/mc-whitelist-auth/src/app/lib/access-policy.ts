import { normalizeDomain } from './db';

export type SignInProvider = 'google';

export type ScopeDecisionInput = {
  attemptedHost: string;
  userEmail: string;
  playerUuid: string;
  playerUsername: string;
  challengeCode: string;
};

export type DomainScope = {
  domain: string;
  includeSubdomains: boolean;
};

export const selectSignInProviderForHost = (_attemptedHost: string): SignInProvider => {
  // TODO: Add host-based provider selection once additional providers are available.
  return 'google';
};

export const decideScopesForChallenge = (input: ScopeDecisionInput): DomainScope[] => {
  // TODO: Replace with final business policy using player identity evidence and per-host rules.
  const domain = normalizeDomain(input.attemptedHost);
  if (!domain) {
    return [];
  }

  return [{ domain, includeSubdomains: true }];
};
