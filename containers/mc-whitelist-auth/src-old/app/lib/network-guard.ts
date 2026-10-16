const stripPort = (host: string): string => {
  const value = host.trim().toLowerCase();
  if (!value) {
    return '';
  }

  if (value.startsWith('[')) {
    const end = value.indexOf(']');
    if (end > 0) {
      return value.slice(1, end);
    }
  }

  const lastColon = value.lastIndexOf(':');
  if (lastColon > -1 && value.indexOf(':') === lastColon) {
    return value.slice(0, lastColon);
  }

  return value;
};

const hostFromRequest = (request: Request): string => {
  const forwardedHost = request.headers.get('x-forwarded-host');
  if (forwardedHost) {
    return stripPort(forwardedHost.split(',')[0] ?? '');
  }

  const host = request.headers.get('host');
  return stripPort(host ?? '');
};

export const isTailscaleRequest = (request: Request): boolean => {
  const host = hostFromRequest(request);
  return host.endsWith('.ts.home.arpa');
};
