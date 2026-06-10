export interface ProxyNode {
  name: string;
  type: string;
  udp?: boolean;
  history?: Record<string, Object>[];
  extra?: Record<string, Object>;
}

export interface ProxyGroup {
  name: string;
  type: string;
  now: string;
  all: string[];
  udp?: boolean;
  hidden?: boolean;
  extra?: Record<string, Object>;
}

export interface MihomoProxiesResponse {
  proxies: Record<string, ProxyGroup | ProxyNode>;
}

export function isProxyGroup(value: ProxyGroup | ProxyNode): boolean {
  return Array.isArray((value as ProxyGroup).all);
}
