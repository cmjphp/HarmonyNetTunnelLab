import http from '@ohos.net.http';
import util from '@ohos.util';
import { ProxyNode, SubscriptionParseResult } from '../model/SubscriptionModel';

export class SubscriptionService {
  private static readonly CLASH_HEADERS: Record<string, string>[] = [
    {
      'User-Agent': 'Clash.Meta/1.19.0 mihomo/1.19.0',
      'Accept': 'text/yaml, application/yaml, text/plain, */*'
    },
    {
      'User-Agent': 'ClashforAndroid/2.5.12',
      'Accept': 'text/yaml, application/yaml, text/plain, */*'
    },
    {
      'User-Agent': 'clash-verge-rev/2.0.0 Mihomo/1.19.0',
      'Accept': 'text/yaml, application/yaml, text/plain, */*'
    }
  ];

  static async download(url: string): Promise<string> {
    let bestContent = '';
    let bestScore = -1;
    let lastError: Error | undefined = undefined;

    for (let index = 0; index < SubscriptionService.CLASH_HEADERS.length; index++) {
      try {
        const content = await SubscriptionService.downloadWithHeaders(url, SubscriptionService.CLASH_HEADERS[index]);
        const result = SubscriptionService.parse(content);
        const score = result.ruleCount * 10000 + result.proxyGroupCount * 100 + result.proxies.length;
        if (score > bestScore) {
          bestContent = content;
          bestScore = score;
        }
        if (result.ruleCount > 0) {
          return content;
        }
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(`${error}`);
      }
    }

    if (bestContent.length > 0) {
      return bestContent;
    }
    throw lastError ?? new Error('订阅读取失败');
  }

  private static async downloadWithHeaders(url: string, headers: Record<string, string>): Promise<string> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        readTimeout: 15000,
        connectTimeout: 15000
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`HTTP ${response.responseCode}`);
      }
      if (typeof response.result === 'string') {
        return response.result;
      }
      return `${response.result}`;
    } finally {
      request.destroy();
    }
  }

  static parse(content: string): SubscriptionParseResult {
    const normalizedContent = SubscriptionService.normalizeContent(content);
    const lines = normalizedContent.replace(/\r\n/g, '\n').split('\n');
    let proxies = SubscriptionService.parseProxies(lines);
    const uriProxies = SubscriptionService.parseUriNodes(lines);
    if (proxies.length === 0 && uriProxies.length > 0) {
      proxies = uriProxies;
    }
    return {
      proxies: proxies,
      proxyGroupCount: SubscriptionService.countSectionItems(lines, 'proxy-groups'),
      ruleCount: SubscriptionService.countSectionItems(lines, 'rules'),
      format: uriProxies.length > 0 && proxies.length === uriProxies.length ? 'uri-list' : 'yaml',
      normalizedContent: normalizedContent
    };
  }

  static sampleConfig(): string {
    return [
      'proxies:',
      '  - { name: "Demo HK", type: ss, server: 203.0.113.10, port: 8388, cipher: aes-128-gcm, password: demo }',
      '  - name: "Demo US"',
      '    type: vmess',
      '    server: 203.0.113.20',
      '    port: 443',
      'proxy-groups:',
      '  - name: "Auto"',
      '    type: select',
      '    proxies:',
      '      - "Demo HK"',
      '      - "Demo US"',
      'rules:',
      '  - MATCH,Auto'
    ].join('\n');
  }

  private static parseProxies(lines: string[]): ProxyNode[] {
    const proxies: ProxyNode[] = [];
    let inProxies = false;
    let current: ProxyNode | undefined = undefined;
    let proxiesIndent = 0;

    for (let index = 0; index < lines.length; index++) {
      const original = lines[index];
      const trimmed = original.trim();
      if (trimmed.length === 0 || trimmed.startsWith('#')) {
        continue;
      }

      if (SubscriptionService.isSection(original, 'proxies')) {
        inProxies = true;
        proxiesIndent = SubscriptionService.indentOf(original);
        current = undefined;
        continue;
      }

      if (inProxies && SubscriptionService.isOtherSectionAtSameOrParentIndent(original, proxiesIndent)) {
        if (current !== undefined) {
          proxies.push(current);
          current = undefined;
        }
        inProxies = false;
      }

      if (!inProxies) {
        continue;
      }

      if (trimmed.startsWith('- {') || trimmed.startsWith('-{')) {
        if (current !== undefined) {
          proxies.push(current);
          current = undefined;
        }
        const node = SubscriptionService.parseInlineProxy(trimmed);
        if (node.name.length > 0) {
          proxies.push(node);
        }
        continue;
      }

      if (trimmed.startsWith('- ')) {
        if (current !== undefined) {
          proxies.push(current);
        }
        current = SubscriptionService.emptyProxy();
        const afterDash = trimmed.substring(2).trim();
        if (afterDash.indexOf(':') > 0) {
          SubscriptionService.applyKeyValue(current, afterDash);
        }
        continue;
      }

      if (current !== undefined && trimmed.indexOf(':') > 0) {
        SubscriptionService.applyKeyValue(current, trimmed);
      }
    }

    if (current !== undefined) {
      proxies.push(current);
    }

    return proxies.filter((node: ProxyNode) => node.name.length > 0);
  }

  private static parseUriNodes(lines: string[]): ProxyNode[] {
    const proxies: ProxyNode[] = [];
    for (let index = 0; index < lines.length; index++) {
      const line = lines[index].trim();
      if (line.length === 0 || line.startsWith('#')) {
        continue;
      }
      const node = SubscriptionService.parseUriNode(line);
      if (node.name.length > 0) {
        proxies.push(node);
      }
    }
    return proxies;
  }

  private static parseUriNode(line: string): ProxyNode {
    if (line.startsWith('vmess://')) {
      return SubscriptionService.parseVmessUri(line);
    }
    if (line.startsWith('ss://')) {
      return SubscriptionService.parseGenericUri(line, 'ss');
    }
    if (line.startsWith('trojan://')) {
      return SubscriptionService.parseGenericUri(line, 'trojan');
    }
    if (line.startsWith('vless://')) {
      return SubscriptionService.parseGenericUri(line, 'vless');
    }
    if (line.startsWith('hysteria2://')) {
      return SubscriptionService.parseGenericUri(line, 'hysteria2');
    }
    if (line.startsWith('hy2://')) {
      return SubscriptionService.parseGenericUri(line, 'hysteria2');
    }
    if (line.startsWith('tuic://')) {
      return SubscriptionService.parseGenericUri(line, 'tuic');
    }
    return SubscriptionService.emptyProxy();
  }

  private static parseVmessUri(line: string): ProxyNode {
    const node = SubscriptionService.emptyProxy();
    node.type = 'vmess';
    const encoded = line.substring('vmess://'.length).trim();
    const decoded = SubscriptionService.tryDecodeBase64(encoded);
    if (decoded.length === 0) {
      node.name = 'vmess';
      return node;
    }
    node.name = SubscriptionService.extractJsonLikeValue(decoded, 'ps');
    node.server = SubscriptionService.extractJsonLikeValue(decoded, 'add');
    node.port = SubscriptionService.extractJsonLikeValue(decoded, 'port');
    if (node.name.length === 0) {
      node.name = node.server.length > 0 ? node.server : 'vmess';
    }
    return node;
  }

  private static parseGenericUri(line: string, type: string): ProxyNode {
    const node = SubscriptionService.emptyProxy();
    node.type = type;
    node.raw = line;
    const scheme = `${line.substring(0, line.indexOf('://'))}://`;
    let body = line.substring(scheme.length);
    const hashIndex = body.indexOf('#');
    if (hashIndex >= 0) {
      node.name = SubscriptionService.safeDecodeUri(body.substring(hashIndex + 1));
      body = body.substring(0, hashIndex);
    }
    const queryIndex = body.indexOf('?');
    if (queryIndex >= 0) {
      SubscriptionService.applyQueryValues(node, body.substring(queryIndex + 1));
      body = body.substring(0, queryIndex);
    }

    if (type === 'ss' && body.indexOf('@') < 0) {
      const decoded = SubscriptionService.tryDecodeBase64(body);
      if (decoded.length > 0) {
        body = decoded;
      }
    }

    const atIndex = body.lastIndexOf('@');
    if (atIndex > 0) {
      const userInfo = SubscriptionService.safeDecodeUri(body.substring(0, atIndex));
      node.password = userInfo.indexOf(':') >= 0 ? userInfo.substring(userInfo.lastIndexOf(':') + 1) : userInfo;
    }
    const hostPort = atIndex >= 0 ? body.substring(atIndex + 1) : body;
    const hostPortParts = SubscriptionService.splitHostPort(hostPort);
    node.server = hostPortParts[0];
    node.port = hostPortParts[1];
    if (node.name.length === 0) {
      node.name = node.server.length > 0 ? `${type}-${node.server}` : type;
    }
    return node;
  }

  private static applyQueryValues(node: ProxyNode, queryText: string): void {
    const pairs = queryText.split('&');
    for (let index = 0; index < pairs.length; index++) {
      const pair = pairs[index];
      if (pair.length === 0) {
        continue;
      }
      const splitIndex = pair.indexOf('=');
      const key = SubscriptionService.safeDecodeUri(splitIndex >= 0 ? pair.substring(0, splitIndex) : pair);
      const value = SubscriptionService.safeDecodeUri(splitIndex >= 0 ? pair.substring(splitIndex + 1) : '');
      if (key === 'sni' || key === 'peer') {
        node.sni = value;
      } else if (key === 'insecure' || key === 'skip-cert-verify' || key === 'allowInsecure') {
        node.skipCertVerify = value;
      } else if (key === 'alpn') {
        node.alpn = value;
      } else if (key === 'obfs') {
        node.obfs = value;
      } else if (key === 'obfs-password' || key === 'obfsPassword') {
        node.obfsPassword = value;
      } else if (key === 'fp') {
        node.fp = value; // Reality fingerprint
      }
    }
  }

  private static parseInlineProxy(line: string): ProxyNode {
    const node = SubscriptionService.emptyProxy();
    const start = line.indexOf('{');
    const end = line.lastIndexOf('}');
    if (start < 0 || end <= start) {
      return node;
    }

    const body = line.substring(start + 1, end);
    const parts = SubscriptionService.splitInlineBody(body);
    for (let index = 0; index < parts.length; index++) {
      SubscriptionService.applyKeyValue(node, parts[index]);
    }
    return node;
  }

  private static splitInlineBody(body: string): string[] {
    const parts: string[] = [];
    let quote = '';
    let current = '';
    for (let index = 0; index < body.length; index++) {
      const char = body.charAt(index);
      if ((char === '"' || char === "'") && (index === 0 || body.charAt(index - 1) !== '\\')) {
        quote = quote.length === 0 ? char : quote === char ? '' : quote;
      }
      if (char === ',' && quote.length === 0) {
        parts.push(current.trim());
        current = '';
      } else {
        current += char;
      }
    }
    if (current.trim().length > 0) {
      parts.push(current.trim());
    }
    return parts;
  }

  private static applyKeyValue(node: ProxyNode, text: string): void {
    const splitIndex = text.indexOf(':');
    if (splitIndex <= 0) {
      return;
    }
    const key = text.substring(0, splitIndex).trim();
    const value = SubscriptionService.cleanValue(text.substring(splitIndex + 1).trim());
    if (key === 'name') {
      node.name = value;
    } else if (key === 'type') {
      node.type = value;
    } else if (key === 'server') {
      node.server = value;
    } else if (key === 'port') {
      node.port = value;
    }
  }

  private static cleanValue(value: string): string {
    let result = value;
    if (result.endsWith(',')) {
      result = result.substring(0, result.length - 1);
    }
    if ((result.startsWith('"') && result.endsWith('"')) || (result.startsWith("'") && result.endsWith("'"))) {
      result = result.substring(1, result.length - 1);
    }
    return result;
  }

  private static countSectionItems(lines: string[], sectionName: string): number {
    let inSection = false;
    let count = 0;
    let sectionIndent = 0;
    for (let index = 0; index < lines.length; index++) {
      const original = lines[index];
      const trimmed = original.trim();
      if (trimmed.length === 0 || trimmed.startsWith('#')) {
        continue;
      }
      if (SubscriptionService.isSection(original, sectionName)) {
        inSection = true;
        sectionIndent = SubscriptionService.indentOf(original);
        continue;
      }
      if (inSection && SubscriptionService.isOtherSectionAtSameOrParentIndent(original, sectionIndent)) {
        break;
      }
      if (inSection && trimmed.startsWith('- ')) {
        count++;
      }
    }
    return count;
  }

  private static normalizeContent(content: string): string {
    const trimmed = content.trim();
    if (trimmed.length === 0) {
      return '';
    }
    if (SubscriptionService.looksLikeConfig(trimmed)) {
      return trimmed;
    }
    const decoded = SubscriptionService.tryDecodeBase64(trimmed);
    if (decoded.length > 0 && SubscriptionService.looksLikeConfig(decoded)) {
      return decoded.trim();
    }
    return trimmed;
  }

  private static looksLikeConfig(text: string): boolean {
    return text.indexOf('proxies:') >= 0 ||
      text.indexOf('proxy-groups:') >= 0 ||
      text.indexOf('ss://') >= 0 ||
      text.indexOf('vmess://') >= 0 ||
      text.indexOf('trojan://') >= 0 ||
      text.indexOf('vless://') >= 0 ||
      text.indexOf('hysteria2://') >= 0 ||
      text.indexOf('hy2://') >= 0 ||
      text.indexOf('tuic://') >= 0;
  }

  private static tryDecodeBase64(text: string): string {
    const cleaned = text.replace(/\r/g, '').replace(/\n/g, '').trim();
    if (cleaned.length < 8) {
      return '';
    }
    const helper = new util.Base64Helper();
    const decoder = util.TextDecoder.create('utf-8');
    try {
      return decoder.decodeToString(helper.decodeSync(cleaned, util.Type.BASIC));
    } catch (_) {
      try {
        return decoder.decodeToString(helper.decodeSync(cleaned, util.Type.MIME));
      } catch (_) {
        try {
          return decoder.decodeToString(helper.decodeSync(cleaned, util.Type.BASIC_URL_SAFE));
        } catch (_) {
          return '';
        }
      }
    }
  }

  private static extractJsonLikeValue(text: string, key: string): string {
    const quotedKey = `"${key}"`;
    const keyIndex = text.indexOf(quotedKey);
    if (keyIndex < 0) {
      return '';
    }
    const colonIndex = text.indexOf(':', keyIndex + quotedKey.length);
    if (colonIndex < 0) {
      return '';
    }
    let cursor = colonIndex + 1;
    while (cursor < text.length && text.charAt(cursor) === ' ') {
      cursor++;
    }
    if (cursor >= text.length) {
      return '';
    }
    if (text.charAt(cursor) === '"') {
      const end = text.indexOf('"', cursor + 1);
      return end > cursor ? text.substring(cursor + 1, end) : '';
    }
    let end = cursor;
    while (end < text.length && text.charAt(end) !== ',' && text.charAt(end) !== '}') {
      end++;
    }
    return SubscriptionService.cleanValue(text.substring(cursor, end).trim());
  }

  private static splitHostPort(hostPort: string): string[] {
    let text = hostPort;
    while (text.endsWith('/')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.startsWith('[')) {
      const closeIndex = text.indexOf(']');
      if (closeIndex > 0) {
        const host = text.substring(1, closeIndex);
        const port = text.length > closeIndex + 2 && text.charAt(closeIndex + 1) === ':' ? text.substring(closeIndex + 2) : '';
        return [host, port];
      }
    }
    const colonIndex = text.lastIndexOf(':');
    if (colonIndex <= 0) {
      return [text, ''];
    }
    return [text.substring(0, colonIndex), text.substring(colonIndex + 1)];
  }

  private static safeDecodeUri(value: string): string {
    try {
      return decodeURIComponent(value);
    } catch (_) {
      return value;
    }
  }

  private static isSection(line: string, sectionName: string): boolean {
    return line.trim() === `${sectionName}:`;
  }

  private static isOtherSectionAtSameOrParentIndent(line: string, sectionIndent: number): boolean {
    const trimmed = line.trim();
    return trimmed.endsWith(':') && SubscriptionService.indentOf(line) <= sectionIndent;
  }

  private static indentOf(line: string): number {
    let count = 0;
    while (count < line.length && line.charAt(count) === ' ') {
      count++;
    }
    return count;
  }

  private static emptyProxy(): ProxyNode {
    return {
      name: '',
      type: '',
      server: '',
      port: '',
      raw: '',
      password: '',
      sni: '',
      skipCertVerify: '',
      alpn: '',
      obfs: '',
      obfsPassword: '',
      fp: ''
    };
  }
}
