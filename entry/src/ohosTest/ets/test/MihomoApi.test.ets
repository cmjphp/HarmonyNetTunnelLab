import { describe, it, expect } from '@ohos/hypium';
import { MihomoApi, MihomoHttpResponse, MihomoHttpTransport, MihomoRequestOptions } from '../../../main/ets/api/MihomoApi';

class RecordedRequest {
  url: string = '';
  options: MihomoRequestOptions = {
    method: 'GET',
    headers: {}
  };
}

class MockTransport implements MihomoHttpTransport {
  requests: RecordedRequest[] = [];
  statusCode: number = 200;
  body: string = '{"version":"mock-mihomo-1.0.0"}';

  async request(url: string, options: MihomoRequestOptions): Promise<MihomoHttpResponse> {
    this.requests.push({
      url,
      options
    });
    return {
      statusCode: this.statusCode,
      body: this.body
    };
  }
}

export default function mihomoApiTest() {
  describe('MihomoApi', () => {
    it('throws clear error when baseUrl is empty', async () => {
      const api = new MihomoApi('', '', new MockTransport());
      let message = '';
      try {
        await api.testConnection();
      } catch (error) {
        message = error instanceof Error ? error.message : String(error);
      }
      expect(message.length > 0).assertTrue();
    });

    it('does not send Authorization when secret is empty', async () => {
      const transport = new MockTransport();
      const api = new MihomoApi('http://127.0.0.1:9090', '', transport);
      await api.getVersion();
      expect(transport.requests[0].options.headers['Authorization'] === undefined).assertTrue();
    });

    it('sends Authorization when secret is set', async () => {
      const transport = new MockTransport();
      const api = new MihomoApi('http://127.0.0.1:9090', 'abc', transport);
      await api.getVersion();
      expect(transport.requests[0].options.headers['Authorization']).assertEqual('Bearer abc');
    });

    it('constructs PUT /proxies/{groupName} for selectProxy', async () => {
      const transport = new MockTransport();
      transport.statusCode = 204;
      transport.body = '';
      const api = new MihomoApi('http://127.0.0.1:9090', '', transport);
      await api.selectProxy('GLOBAL', 'Proxy');
      expect(transport.requests[0].url).assertEqual('http://127.0.0.1:9090/proxies/GLOBAL');
      expect(transport.requests[0].options.method).assertEqual('PUT');
      expect(transport.requests[0].options.body).assertEqual('{"name":"Proxy"}');
    });

    it('uses DELETE /connections for closeAllConnections', async () => {
      const transport = new MockTransport();
      transport.statusCode = 204;
      transport.body = '';
      const api = new MihomoApi('http://127.0.0.1:9090', '', transport);
      await api.closeAllConnections();
      expect(transport.requests[0].url).assertEqual('http://127.0.0.1:9090/connections');
      expect(transport.requests[0].options.method).assertEqual('DELETE');
    });
  });
}
