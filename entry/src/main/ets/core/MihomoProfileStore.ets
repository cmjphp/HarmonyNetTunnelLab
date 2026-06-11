import common from '@ohos.app.ability.common';
import fileIo from '@ohos.file.fs';
import { CoreRuntimeConfig } from '../model/SubscriptionModel';

export class MihomoProfileStore {
  static rawProfilePath(context: common.Context): string {
    return `${context.filesDir}/mihomo_profile_raw.yaml`;
  }

  static runtimeConfigPath(context: common.Context): string {
    return `${context.filesDir}/mihomo_runtime.yaml`;
  }

  static async saveRawProfile(context: common.Context, content: string): Promise<void> {
    MihomoProfileStore.writeTextFile(MihomoProfileStore.rawProfilePath(context), content);
  }

  static async writeRuntimeConfig(context: common.Context, config: CoreRuntimeConfig): Promise<string> {
    let rawProfile = '';
    try {
      rawProfile = await fileIo.readText(MihomoProfileStore.rawProfilePath(context));
    } catch (_) {
      rawProfile = '';
    }

    let runtimeConfig: string;
    if (MihomoProfileStore.canUseRawYaml(rawProfile)) {
      runtimeConfig = MihomoProfileStore.mergeRawWithLocalSettings(rawProfile, config);
    } else {
      runtimeConfig = MihomoProfileStore.buildSelectedNodeConfig(config);
    }
    const path = MihomoProfileStore.runtimeConfigPath(context);
    MihomoProfileStore.writeTextFile(path, runtimeConfig);
    return path;
  }

  private static writeTextFile(path: string, content: string): void {
    const file = fileIo.openSync(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, content);
    } finally {
      fileIo.closeSync(file);
    }
  }

  private static canUseRawYaml(content: string): boolean {
    const text = content.trim();
    return text.indexOf('proxies:') >= 0 && text.indexOf('proxy-groups:') >= 0 && text.indexOf('rules:') >= 0;
  }

  private static mergeRawWithLocalSettings(rawProfile: string, config: CoreRuntimeConfig): string {
    const lines = rawProfile.replace(/\r\n/g, '\n').split('\n');
    const result: string[] = [];
    const fakeIpFilter = MihomoProfileStore.buildFakeIpFilter(config);
    const runtimeMode = MihomoProfileStore.effectiveRuntimeMode(config, MihomoProfileStore.hasUsableRules(rawProfile));
    let skipUntilNextKey = false;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const trimmed = line.trim();

      // Skip empty lines and comments at top level during replacement
      if (skipUntilNextKey) {
        // Check if this is a new top-level key (no indent, contains ':')
        if (trimmed.length > 0 && !trimmed.startsWith('#') && !trimmed.startsWith('- ') &&
          line === trimmed && trimmed.indexOf(':') > 0) {
          skipUntilNextKey = false;
        } else if (trimmed.length === 0 || trimmed.startsWith('#')) {
          continue;
        } else {
          continue;
        }
      }

      // Replace top-level keys we want to override
      if (line === trimmed && trimmed.indexOf(':') > 0 && !trimmed.startsWith('- ')) {
        const key = trimmed.split(':')[0].trim();
        if (key === 'mixed-port' || key === 'allow-lan' || key === 'mode' ||
          key === 'log-level' || key === 'ipv6' || key === 'tcp-concurrent' ||
          key === 'interface-name' || key === 'bind-address' || key === 'external-controller' ||
          key === 'external-ui' || key === 'external-ui-name' || key === 'external-ui-url' ||
          key === 'secret' || key === 'unified-delay' || key === 'profile') {
          // Skip these, we'll add our own
          skipUntilNextKey = true;
          continue;
        }
        if (key === 'tun' || key === 'dns' || key === 'sniffer') {
          // Skip entire section until next top-level key
          skipUntilNextKey = true;
          continue;
        }
      }

      result.push(line);
    }

    // Build the local settings header
    const header: string[] = [
      'mixed-port: 7890',
      'allow-lan: false',
      `mode: ${runtimeMode}`,
      'log-level: debug',
      'ipv6: false',
      'tcp-concurrent: true',
      'external-controller: 127.0.0.1:9090',
      'tun:',
      '  enable: true',
      '  stack: system',
      '  auto-route: false',
      '  auto-detect-interface: false',
      '  mtu: 1400',
      '  dns-hijack:',
      '    - 0.0.0.0:53',
      'sniffer:',
      '  enable: true',
      '  force-dns-mapping: true',
      '  parse-pure-ip: true',
      '  override-destination: true',
      '  sniff:',
      '    HTTP:',
      '      ports:',
      '        - 80',
      '        - 8080-8880',
      '      override-destination: true',
      '    TLS:',
      '      ports:',
      '        - 443',
      '        - 8443',
      '    QUIC:',
      '      ports:',
      '        - 443',
      '        - 8443',
      'dns:',
      '  enable: true',
      '  listen: 127.0.0.1:1053',
      '  enhanced-mode: fake-ip',
      '  fake-ip-range: 198.18.0.1/16',
      ...fakeIpFilter,
      '  fallback-filter:',
      '    geoip: false',
      '  nameserver:',
      `    - ${MihomoProfileStore.yamlQuote(config.dnsPrimary)}`,
      `    - ${MihomoProfileStore.yamlQuote(config.dnsSecondary)}`
    ];

    return [...header, ...result].join('\n');
  }

  private static buildSelectedNodeConfig(config: CoreRuntimeConfig): string {
    const proxyYaml = MihomoProfileStore.buildProxyYaml(config);
    const selectedName = MihomoProfileStore.yamlQuote(config.selectedName.length > 0 ? config.selectedName : 'Selected');
    const fakeIpFilter = MihomoProfileStore.buildFakeIpFilter(config);
    const runtimeMode = MihomoProfileStore.effectiveRuntimeMode(config, false);
    const fallbackRule = runtimeMode === 'direct' ? '  - MATCH,DIRECT' : '  - MATCH,SELECT';
    return [
      'mixed-port: 7890',
      'allow-lan: false',
      `mode: ${runtimeMode}`,
      'log-level: debug',
      'ipv6: false',
      'tcp-concurrent: true',
      'external-controller: 127.0.0.1:9090',
      'tun:',
      '  enable: true',
      '  stack: system',
      '  auto-route: false',
      '  auto-detect-interface: false',
      '  mtu: 1400',
      '  dns-hijack:',
      '    - 0.0.0.0:53',
      'sniffer:',
      '  enable: true',
      '  force-dns-mapping: true',
      '  parse-pure-ip: true',
      '  override-destination: true',
      '  sniff:',
      '    HTTP:',
      '      ports:',
      '        - 80',
      '        - 8080-8880',
      '      override-destination: true',
      '    TLS:',
      '      ports:',
      '        - 443',
      '        - 8443',
      '    QUIC:',
      '      ports:',
      '        - 443',
      '        - 8443',
      'dns:',
      '  enable: true',
      '  listen: 127.0.0.1:1053',
      '  enhanced-mode: fake-ip',
      '  fake-ip-range: 198.18.0.1/16',
      ...fakeIpFilter,
      '  fallback-filter:',
      '    geoip: false',
      '  nameserver:',
      `    - ${MihomoProfileStore.yamlQuote(config.dnsPrimary)}`,
      `    - ${MihomoProfileStore.yamlQuote(config.dnsSecondary)}`,
      'proxies:',
      proxyYaml,
      'proxy-groups:',
      '  - name: SELECT',
      '    type: select',
      '    disable-udp: false',
      '    proxies:',
      `      - ${selectedName}`,
      '  - name: GLOBAL',
      '    type: select',
      '    disable-udp: false',
      '    proxies:',
      `      - ${selectedName}`,
      'rules:',
      fallbackRule
    ].join('\n');
  }

  private static effectiveRuntimeMode(config: CoreRuntimeConfig, hasRules: boolean): string {
    if (config.mode === 'global') {
      return 'global';
    }
    return hasRules ? 'rule' : 'direct';
  }

  private static hasUsableRules(content: string): boolean {
    const lines = content.replace(/\r\n/g, '\n').split('\n');
    let inRules = false;
    let rulesIndent = 0;
    for (let index = 0; index < lines.length; index++) {
      const line = lines[index];
      const trimmed = line.trim();
      if (trimmed.length === 0 || trimmed.startsWith('#')) {
        continue;
      }
      if (!inRules && line === trimmed && trimmed === 'rules:') {
        inRules = true;
        rulesIndent = MihomoProfileStore.indentOf(line);
        continue;
      }
      if (inRules && line === trimmed && trimmed.indexOf(':') > 0 && !trimmed.startsWith('- ')) {
        break;
      }
      if (inRules && MihomoProfileStore.indentOf(line) > rulesIndent && trimmed.startsWith('- ')) {
        return true;
      }
    }
    return false;
  }

  private static indentOf(line: string): number {
    let count = 0;
    while (count < line.length && line.charAt(count) === ' ') {
      count++;
    }
    return count;
  }

  private static isIpAddress(host: string): boolean {
    if (host.length === 0) {
      return false;
    }
    const parts = host.split('.');
    if (parts.length !== 4) {
      return false;
    }
    for (let i = 0; i < parts.length; i++) {
      const num = Number(parts[i]);
      if (!Number.isFinite(num) || num < 0 || num > 255 || parts[i].length === 0) {
        return false;
      }
    }
    return true;
  }

  private static buildFakeIpFilter(config: CoreRuntimeConfig): string[] {
    const filters: string[] = [
      '*.apple.com',
      '*.icloud.com',
      '*.cdn-apple.com',
      'dns.msftncsi.com',
      'www.msftncsi.com',
      'www.msftconnecttest.com',
      'localhost.ptlogin2.qq.com',
      'localhost.sec.qq.com',
      '+.ntp.org.cn',
      'time.*.com',
      'time.*.gov',
      'time.*.edu.cn',
      'localhost'
    ];
    // Add DNS servers to fake-ip-filter to prevent DNS query loop through TUN
    if (config.dnsPrimary.length > 0) {
      filters.push(config.dnsPrimary);
    }
    if (config.dnsSecondary.length > 0 && config.dnsSecondary !== config.dnsPrimary) {
      filters.push(config.dnsSecondary);
    }
    if (config.server.length > 0 && !MihomoProfileStore.isIpAddress(config.server)) {
      filters.push(config.server);
    }
    const lines: string[] = ['  fake-ip-filter:'];
    for (let i = 0; i < filters.length; i++) {
      lines.push(`    - ${MihomoProfileStore.yamlQuote(filters[i])}`);
    }
    return lines;
  }

  private static getQueryParam(rawUri: string, key: string): string {
    const queryStart = rawUri.indexOf('?');
    if (queryStart < 0) {
      return '';
    }
    const hashStart = rawUri.indexOf('#');
    const queryEnd = hashStart >= 0 ? hashStart : rawUri.length;
    const queryStr = rawUri.substring(queryStart + 1, queryEnd);
    const pairs = queryStr.split('&');
    for (let index = 0; index < pairs.length; index++) {
      const pair = pairs[index];
      const eqIdx = pair.indexOf('=');
      if (eqIdx > 0) {
        let k = '';
        let v = '';
        try {
          k = decodeURIComponent(pair.substring(0, eqIdx));
          v = decodeURIComponent(pair.substring(eqIdx + 1));
        } catch (_) {
          k = pair.substring(0, eqIdx);
          v = pair.substring(eqIdx + 1);
        }
        if (k === key) {
          return v;
        }
      }
    }
    return '';
  }

  private static buildVlessProxy(config: CoreRuntimeConfig): string[] {
    const uuid = config.password;
    const network = MihomoProfileStore.getQueryParam(config.rawUri, 'type') || 'tcp';
    const security = MihomoProfileStore.getQueryParam(config.rawUri, 'security') || 'none';
    const tls = security === 'tls' || security === 'reality';
    const sni = MihomoProfileStore.getQueryParam(config.rawUri, 'sni') || config.sni;
    const fingerprint = MihomoProfileStore.getQueryParam(config.rawUri, 'fp') || config.fp;
    const flow = MihomoProfileStore.getQueryParam(config.rawUri, 'flow');
    const pbk = MihomoProfileStore.getQueryParam(config.rawUri, 'pbk');
    const sid = MihomoProfileStore.getQueryParam(config.rawUri, 'sid');
    const alpnRaw = MihomoProfileStore.getQueryParam(config.rawUri, 'alpn') || config.alpn;

    const lines: string[] = [
      `  - name: ${MihomoProfileStore.yamlQuote(config.selectedName)}`,
      '    type: vless',
      `    server: ${MihomoProfileStore.yamlQuote(config.server)}`,
      `    port: ${MihomoProfileStore.yamlNumber(config.port)}`,
      `    uuid: ${MihomoProfileStore.yamlQuote(uuid)}`,
      `    tls: ${tls ? 'true' : 'false'}`,
      `    network: ${MihomoProfileStore.yamlQuote(network)}`,
    ];

    if (flow.length > 0) {
      lines.push(`    flow: ${MihomoProfileStore.yamlQuote(flow)}`);
    }

    if (sni.length > 0) {
      lines.push(`    servername: ${MihomoProfileStore.yamlQuote(sni)}`);
    }
    if (fingerprint.length > 0) {
      lines.push(`    client-fingerprint: ${MihomoProfileStore.yamlQuote(fingerprint)}`);
    }

    if (alpnRaw.length > 0) {
      const alpns = alpnRaw.split(',').map((a: string) => a.trim()).filter((a: string) => a.length > 0);
      if (alpns.length > 0) {
        lines.push('    alpn:');
        for (let index = 0; index < alpns.length; index++) {
          lines.push(`      - ${MihomoProfileStore.yamlQuote(alpns[index])}`);
        }
      }
    }

    if (security === 'reality' && (pbk.length > 0 || sid.length > 0)) {
      lines.push('    reality-opts:');
      if (pbk.length > 0) {
        lines.push(`      public-key: ${MihomoProfileStore.yamlQuote(pbk)}`);
      }
      if (sid.length > 0) {
        lines.push(`      short-id: ${MihomoProfileStore.yamlQuote(sid)}`);
      }
    }

    if (network === 'ws') {
      const path = MihomoProfileStore.getQueryParam(config.rawUri, 'path') || '/';
      const host = MihomoProfileStore.getQueryParam(config.rawUri, 'host') || config.server;
      lines.push('    ws-opts:');
      lines.push(`      path: ${MihomoProfileStore.yamlQuote(path)}`);
      if (host.length > 0) {
        lines.push('      headers:');
        lines.push(`        Host: ${MihomoProfileStore.yamlQuote(host)}`);
      }
    } else if (network === 'grpc') {
      const serviceName = MihomoProfileStore.getQueryParam(config.rawUri, 'serviceName');
      if (serviceName.length > 0) {
        lines.push('    grpc-opts:');
        lines.push(`      grpc-service-name: ${MihomoProfileStore.yamlQuote(serviceName)}`);
      }
    }

    const skipCertVerify = config.skipCertVerify;
    if (skipCertVerify === 'true' || skipCertVerify === '1' || skipCertVerify === 'yes') {
      lines.push('    skip-cert-verify: true');
    }

    return lines;
  }

  private static buildTrojanProxy(config: CoreRuntimeConfig): string[] {
    const sni = MihomoProfileStore.getQueryParam(config.rawUri, 'sni') || config.sni || config.server;
    const network = MihomoProfileStore.getQueryParam(config.rawUri, 'type') || 'tcp';
    const lines: string[] = [
      `  - name: ${MihomoProfileStore.yamlQuote(config.selectedName)}`,
      '    type: trojan',
      `    server: ${MihomoProfileStore.yamlQuote(config.server)}`,
      `    port: ${MihomoProfileStore.yamlNumber(config.port)}`,
      `    password: ${MihomoProfileStore.yamlQuote(config.password)}`,
    ];
    if (sni.length > 0) {
      lines.push(`    sni: ${MihomoProfileStore.yamlQuote(sni)}`);
    }
    if (network === 'ws') {
      const path = MihomoProfileStore.getQueryParam(config.rawUri, 'path') || '/';
      const host = MihomoProfileStore.getQueryParam(config.rawUri, 'host') || config.server;
      lines.push('    network: ws');
      lines.push('    ws-opts:');
      lines.push(`      path: ${MihomoProfileStore.yamlQuote(path)}`);
      if (host.length > 0) {
        lines.push('      headers:');
        lines.push(`        Host: ${MihomoProfileStore.yamlQuote(host)}`);
      }
    }
    const skipCertVerify = config.skipCertVerify;
    if (skipCertVerify === 'true' || skipCertVerify === '1' || skipCertVerify === 'yes') {
      lines.push('    skip-cert-verify: true');
    }
    return lines;
  }

  private static buildProxyYaml(config: CoreRuntimeConfig): string {
    if (config.type === 'hysteria2') {
      const lines: string[] = [
        `  - name: ${MihomoProfileStore.yamlQuote(config.selectedName)}`,
        '    type: hysteria2',
        `    server: ${MihomoProfileStore.yamlQuote(config.server)}`,
        `    port: ${MihomoProfileStore.yamlNumber(config.port)}`,
        `    password: ${MihomoProfileStore.yamlQuote(config.password)}`,
        '    udp: true',
        `    skip-cert-verify: ${MihomoProfileStore.toBooleanText(config.skipCertVerify)}`
      ];
      MihomoProfileStore.pushOptional(lines, 'sni', config.sni);
      MihomoProfileStore.pushOptional(lines, 'obfs', config.obfs);
      MihomoProfileStore.pushOptional(lines, 'obfs-password', config.obfsPassword);
      if (config.alpn.length > 0) {
        lines.push('    alpn:');
        const values = config.alpn.split(',').map((item: string) => item.trim()).filter((item: string) => item.length > 0);
        for (let index = 0; index < values.length; index++) {
          lines.push(`      - ${MihomoProfileStore.yamlQuote(values[index])}`);
        }
      }
      return lines.join('\n');
    }

    if (config.type === 'vless') {
      return MihomoProfileStore.buildVlessProxy(config).join('\n');
    }

    if (config.type === 'trojan') {
      return MihomoProfileStore.buildTrojanProxy(config).join('\n');
    }

    return [
      `  - name: ${MihomoProfileStore.yamlQuote(config.selectedName)}`,
      `    type: ${MihomoProfileStore.yamlQuote(config.type)}`,
      `    server: ${MihomoProfileStore.yamlQuote(config.server)}`,
      `    port: ${MihomoProfileStore.yamlNumber(config.port)}`,
      '    # Unsupported protocol - please use a full Mihomo YAML subscription'
    ].join('\n');
  }

  private static pushOptional(lines: string[], key: string, value: string): void {
    if (value.length > 0) {
      lines.push(`    ${key}: ${MihomoProfileStore.yamlQuote(value)}`);
    }
  }

  private static toBooleanText(value: string): string {
    const normalized = value.toLowerCase();
    return normalized === 'true' || normalized === '1' || normalized === 'yes' ? 'true' : 'false';
  }

  private static yamlNumber(value: string): string {
    const numMatch = value.match(/^(\d+)/);
    if (numMatch) {
      return numMatch[1];
    }
    return MihomoProfileStore.yamlQuote(value);
  }

  private static yamlQuote(value: string): string {
    return `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
  }
}
