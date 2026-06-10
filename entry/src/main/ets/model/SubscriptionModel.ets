export interface ProxyNode {
  name: string;
  type: string;
  server: string;
  port: string;
  raw?: string;
  password?: string;
  sni?: string;
  skipCertVerify?: string;
  alpn?: string;
  obfs?: string;
  obfsPassword?: string;
  fp?: string; // Reality fingerprint
  delay?: number; // Latency in ms, -1 means failed
}

export interface SubscriptionItem {
  id: string;
  name: string;
  url: string;
  content: string;
  format: string;
  nodeCount: number;
  updatedAt: string;
}

export interface SubscriptionParseResult {
  proxies: ProxyNode[];
  proxyGroupCount: number;
  ruleCount: number;
  format: string;
  normalizedContent: string;
}

export interface CachedSubscription {
  url: string;
  content: string;
  format: string;
  nodeCount: number;
  updatedAt: string;
}

export interface CoreRuntimeConfig {
  selectedName: string;
  type: string;
  server: string;
  port: string;
  tunAddress: string;
  dnsPrimary: string;
  dnsSecondary: string;
  rawUri: string;
  password: string;
  sni: string;
  skipCertVerify: string;
  alpn: string;
  obfs: string;
  obfsPassword: string;
  fp: string; // Reality fingerprint
  mode: string; // 'rule' or 'global'
}
