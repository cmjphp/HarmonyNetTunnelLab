import http from '@ohos.net.http';
import { trimTrailingSlash } from '../common/Utils';
import { MihomoConnectionsResponse } from '../model/ConnectionModel';
import { MihomoProxiesResponse } from '../model/ProxyModel';

export interface MihomoVersion {
  version: string;
  meta?: boolean;
  premium?: boolean;
}

export interface MihomoConfigs {
  port?: number;
  socksPort?: number;
  redirPort?: number;
  tproxyPort?: number;
  mixedPort?: number;
  mode?: string;
  logLevel?: string;
  ipv6?: boolean;
  extra?: Record<string, Object>;
}

interface UpdateConfigsRequest {
  mode?: string;
}

export interface MihomoRequestOptions {
  method: string;
  headers: Record<string, string>;
  body?: string;
}

export interface MihomoHttpResponse {
  statusCode: number;
  body: string;
}

export interface MihomoHttpTransport {
  request(url: string, options: MihomoRequestOptions): Promise<MihomoHttpResponse>;
}

interface SelectProxyRequest {
  name: string;
}

export class MihomoApiError extends Error {
  statusCode?: number;

  constructor(message: string, statusCode?: number) {
    super(message);
    this.name = 'MihomoApiError';
    this.statusCode = statusCode;
  }
}

class HarmonyHttpTransport implements MihomoHttpTransport {
  async request(url: string, options: MihomoRequestOptions): Promise<MihomoHttpResponse> {
    const client = http.createHttp();
    try {
      const response = await client.request(url, {
        method: this.toHarmonyMethod(options.method),
        header: options.headers,
        extraData: options.body
      });
      return {
        statusCode: response.responseCode,
        body: this.toBodyString(response.result)
      };
    } catch (error) {
      throw new MihomoApiError(`网络请求失败：${this.errorMessage(error)}`);
    } finally {
      client.destroy();
    }
  }

  private toHarmonyMethod(method: string): http.RequestMethod {
    if (method === 'PATCH') {
      return 'PATCH' as http.RequestMethod;
    }
    if (method === 'PUT') {
      return http.RequestMethod.PUT;
    }
    if (method === 'DELETE') {
      return http.RequestMethod.DELETE;
    }
    if (method === 'POST') {
      return http.RequestMethod.POST;
    }
    return http.RequestMethod.GET;
  }

  private toBodyString(result: string | Object | ArrayBuffer): string {
    if (typeof result === 'string') {
      return result;
    }
    if (result instanceof ArrayBuffer) {
      return '';
    }
    return JSON.stringify(result);
  }

  private errorMessage(error: Error | Object | string): string {
    if (error instanceof Error) {
      return error.message;
    }
    return String(error);
  }
}

export class MihomoApi {
  private readonly baseUrl: string;
  private readonly secret: string;
  private readonly transport: MihomoHttpTransport;

  constructor(baseUrl: string, secret?: string, transport?: MihomoHttpTransport) {
    this.baseUrl = trimTrailingSlash(baseUrl);
    this.secret = secret ? secret.trim() : '';
    this.transport = transport ? transport : new HarmonyHttpTransport();
  }

  async testConnection(): Promise<boolean> {
    try {
      await this.getVersion();
      return true;
    } catch (versionError) {
      try {
        await this.getConfigs();
        return true;
      } catch (configsError) {
        throw new MihomoApiError(`连接失败：${this.errorMessage(configsError)}`);
      }
    }
  }

  async getVersion(): Promise<MihomoVersion> {
    return this.requestJson<MihomoVersion>('/version', 'GET');
  }

  async getConfigs(): Promise<MihomoConfigs> {
    return this.requestJson<MihomoConfigs>('/configs', 'GET');
  }

  async updateMode(mode: string): Promise<boolean> {
    if (mode !== 'rule' && mode !== 'global' && mode !== 'direct') {
      throw new MihomoApiError(`不支持的代理模式：${mode}`);
    }
    const body: UpdateConfigsRequest = {
      mode
    };
    await this.requestEmpty('/configs', 'PATCH', JSON.stringify(body));
    return true;
  }

  async getProxies(): Promise<MihomoProxiesResponse> {
    return this.requestJson<MihomoProxiesResponse>('/proxies', 'GET');
  }

  async selectProxy(groupName: string, proxyName: string): Promise<boolean> {
    if (groupName.trim().length === 0 || proxyName.trim().length === 0) {
      throw new MihomoApiError('代理组或节点名称不能为空');
    }
    const body: SelectProxyRequest = {
      name: proxyName
    };
    await this.requestEmpty(`/proxies/${encodeURIComponent(groupName)}`, 'PUT', JSON.stringify(body));
    return true;
  }

  async getConnections(): Promise<MihomoConnectionsResponse> {
    return this.requestJson<MihomoConnectionsResponse>('/connections', 'GET');
  }

  async closeAllConnections(): Promise<boolean> {
    await this.requestEmpty('/connections', 'DELETE');
    return true;
  }

  private buildUrl(path: string): string {
    if (this.baseUrl.length === 0) {
      throw new MihomoApiError('controller 地址不能为空');
    }
    if (!this.baseUrl.startsWith('http://') && !this.baseUrl.startsWith('https://')) {
      throw new MihomoApiError('controller 地址必须以 http:// 或 https:// 开头');
    }
    return `${this.baseUrl}${path}`;
  }

  private buildHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json'
    };
    if (this.secret.length > 0) {
      headers['Authorization'] = `Bearer ${this.secret}`;
    }
    return headers;
  }

  private async requestJson<T>(path: string, method: string): Promise<T> {
    const response = await this.send(path, method);
    if (response.body.trim().length === 0) {
      throw new MihomoApiError('服务端返回为空', response.statusCode);
    }
    try {
      return JSON.parse(response.body) as T;
    } catch (parseError) {
      throw new MihomoApiError(`JSON 解析失败：${this.errorMessage(parseError)}`, response.statusCode);
    }
  }

  private async requestEmpty(path: string, method: string, body?: string): Promise<void> {
    await this.send(path, method, body);
  }

  private async send(path: string, method: string, body?: string): Promise<MihomoHttpResponse> {
    const response = await this.transport.request(this.buildUrl(path), {
      method,
      headers: this.buildHeaders(),
      body: body
    });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode === 401 || response.statusCode === 403) {
        throw new MihomoApiError('secret 错误或无权限访问', response.statusCode);
      }
      throw new MihomoApiError(`HTTP ${response.statusCode}`, response.statusCode);
    }
    return response;
  }

  private errorMessage(error: Error | Object | string): string {
    if (error instanceof Error) {
      return error.message;
    }
    return String(error);
  }
}
