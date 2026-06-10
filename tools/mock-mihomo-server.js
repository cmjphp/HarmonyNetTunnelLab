#!/usr/bin/env node

const http = require('http');

const port = Number(process.env.PORT || 9090);

let selected = {
  GLOBAL: 'Proxy',
  Proxy: 'Hong Kong 01'
};

function createMockConnection() {
  return {
    id: 'mock-1',
    upload: 512,
    download: 2048,
    start: new Date().toISOString(),
    metadata: {
      network: 'tcp',
      type: 'HTTP',
      sourceIP: '192.168.1.23',
      destinationIP: '93.184.216.34',
      host: 'example.com',
      sourcePort: '54000',
      destinationPort: '443'
    },
    chains: ['Proxy', selected.Proxy],
    rule: 'DomainSuffix',
    rulePayload: 'example.com'
  };
}

let connections = [createMockConnection()];

function ensureMockConnection() {
  if (connections.length === 0) {
    connections = [createMockConnection()];
  }
}

function sendJson(res, status, body) {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET,PUT,DELETE,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization'
  });
  res.end(JSON.stringify(body));
}

function sendEmpty(res, status) {
  res.writeHead(status, {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET,PUT,DELETE,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization'
  });
  res.end();
}

function readBody(req) {
  return new Promise((resolve) => {
    let data = '';
    req.on('data', chunk => {
      data += chunk;
    });
    req.on('end', () => resolve(data));
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || '/', `http://${req.headers.host}`);

  if (req.method === 'OPTIONS') {
    sendEmpty(res, 204);
    return;
  }

  if (req.method === 'GET' && url.pathname === '/version') {
    ensureMockConnection();
    sendJson(res, 200, { version: 'mock-mihomo-1.0.0' });
    return;
  }

  if (req.method === 'GET' && url.pathname === '/configs') {
    ensureMockConnection();
    sendJson(res, 200, { port: 7890, 'socks-port': 7891, mode: 'rule' });
    return;
  }

  if (req.method === 'GET' && url.pathname === '/proxies') {
    sendJson(res, 200, {
      proxies: {
        DIRECT: { name: 'DIRECT', type: 'Direct', udp: true },
        REJECT: { name: 'REJECT', type: 'Reject', udp: false },
        'Hong Kong 01': { name: 'Hong Kong 01', type: 'Shadowsocks', udp: true },
        'Japan 01': { name: 'Japan 01', type: 'Trojan', udp: true },
        GLOBAL: {
          name: 'GLOBAL',
          type: 'Selector',
          now: selected.GLOBAL,
          all: ['Proxy', 'DIRECT', 'REJECT']
        },
        Proxy: {
          name: 'Proxy',
          type: 'Selector',
          now: selected.Proxy,
          all: ['Hong Kong 01', 'Japan 01', 'DIRECT']
        }
      }
    });
    return;
  }

  if (req.method === 'PUT' && url.pathname.startsWith('/proxies/')) {
    const groupName = decodeURIComponent(url.pathname.replace('/proxies/', ''));
    const body = await readBody(req);
    try {
      const parsed = JSON.parse(body || '{}');
      if (typeof parsed.name === 'string') {
        selected[groupName] = parsed.name;
      }
    } catch (error) {
      sendJson(res, 400, { error: 'invalid json' });
      return;
    }
    sendEmpty(res, 204);
    return;
  }

  if (req.method === 'GET' && url.pathname === '/connections') {
    connections = connections.map(connection => ({
      ...connection,
      chains: ['Proxy', selected.Proxy]
    }));
    sendJson(res, 200, {
      downloadTotal: 4096,
      uploadTotal: 1024,
      connections
    });
    return;
  }

  if (req.method === 'DELETE' && url.pathname === '/connections') {
    connections = [];
    sendEmpty(res, 204);
    return;
  }

  sendJson(res, 404, { error: 'not found' });
});

server.listen(port, '0.0.0.0', () => {
  console.log(`mock mihomo external-controller listening on http://127.0.0.1:${port}`);
});
