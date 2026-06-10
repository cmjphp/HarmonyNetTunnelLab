export interface MihomoConnectionMetadata {
  network?: string;
  type?: string;
  sourceIP?: string;
  destinationIP?: string;
  sourcePort?: string;
  destinationPort?: string;
  host?: string;
  dnsMode?: string;
  process?: string;
}

export interface MihomoConnection {
  id: string;
  upload: number;
  download: number;
  start: string;
  metadata: MihomoConnectionMetadata;
  chains: string[];
  rule: string;
  rulePayload: string;
}

export interface MihomoConnectionsResponse {
  downloadTotal: number;
  uploadTotal: number;
  connections: MihomoConnection[];
}
