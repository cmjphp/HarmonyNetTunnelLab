import common from '@ohos.app.ability.common';
import preferences from '@ohos.data.preferences';
import { CoreRuntimeConfig, ProxyNode } from '../model/SubscriptionModel';

const CORE_PREF_NAME: string = 'vpn_poc_core_config';
const KEY_SELECTED_NAME: string = 'selectedName';
const KEY_TYPE: string = 'type';
const KEY_SERVER: string = 'server';
const KEY_PORT: string = 'port';
const KEY_TUN_ADDRESS: string = 'tunAddress';
const KEY_DNS_PRIMARY: string = 'dnsPrimary';
const KEY_DNS_SECONDARY: string = 'dnsSecondary';
const KEY_RAW_URI: string = 'rawUri';
const KEY_PASSWORD: string = 'password';
const KEY_SNI: string = 'sni';
const KEY_SKIP_CERT_VERIFY: string = 'skipCertVerify';
const KEY_ALPN: string = 'alpn';
const KEY_OBFS: string = 'obfs';
const KEY_OBFS_PASSWORD: string = 'obfsPassword';
const KEY_FP: string = 'fp';
const KEY_MODE: string = 'mode';
export const DEFAULT_TUN_ADDRESS: string = '198.18.0.1/30';
export const DEFAULT_DNS_PRIMARY: string = '223.5.5.5';
export const DEFAULT_DNS_SECONDARY: string = '119.29.29.29';
export const DEFAULT_MODE: string = 'rule';

export class CoreConfigStore {
  static buildConfig(node: ProxyNode): CoreRuntimeConfig {
    return {
      selectedName: node.name,
      type: node.type,
      server: node.server,
      port: node.port,
      tunAddress: DEFAULT_TUN_ADDRESS,
      dnsPrimary: DEFAULT_DNS_PRIMARY,
      dnsSecondary: DEFAULT_DNS_SECONDARY,
      rawUri: node.raw ?? '',
      password: node.password ?? '',
      sni: node.sni ?? '',
      skipCertVerify: node.skipCertVerify ?? '',
      alpn: node.alpn ?? '',
      obfs: node.obfs ?? '',
      obfsPassword: node.obfsPassword ?? '',
      fp: node.fp ?? '',
      mode: DEFAULT_MODE
    };
  }

  static emptyConfig(): CoreRuntimeConfig {
    return {
      selectedName: '',
      type: '',
      server: '',
      port: '',
      tunAddress: DEFAULT_TUN_ADDRESS,
      dnsPrimary: DEFAULT_DNS_PRIMARY,
      dnsSecondary: DEFAULT_DNS_SECONDARY,
      rawUri: '',
      password: '',
      sni: '',
      skipCertVerify: '',
      alpn: '',
      obfs: '',
      obfsPassword: '',
      fp: '',
      mode: DEFAULT_MODE
    };
  }

  static async save(context: common.Context, config: CoreRuntimeConfig): Promise<void> {
    const store = await preferences.getPreferences(context, CORE_PREF_NAME);
    await store.put(KEY_SELECTED_NAME, config.selectedName);
    await store.put(KEY_TYPE, config.type);
    await store.put(KEY_SERVER, config.server);
    await store.put(KEY_PORT, config.port);
    await store.put(KEY_TUN_ADDRESS, config.tunAddress);
    await store.put(KEY_DNS_PRIMARY, config.dnsPrimary);
    await store.put(KEY_DNS_SECONDARY, config.dnsSecondary);
    await store.put(KEY_RAW_URI, config.rawUri);
    await store.put(KEY_PASSWORD, config.password);
    await store.put(KEY_SNI, config.sni);
    await store.put(KEY_SKIP_CERT_VERIFY, config.skipCertVerify);
    await store.put(KEY_ALPN, config.alpn);
    await store.put(KEY_OBFS, config.obfs);
    await store.put(KEY_OBFS_PASSWORD, config.obfsPassword);
    await store.put(KEY_FP, config.fp);
    await store.put(KEY_MODE, config.mode);
    await store.flush();
  }

  static async load(context: common.Context): Promise<CoreRuntimeConfig> {
    const store = await preferences.getPreferences(context, CORE_PREF_NAME);
    return {
      selectedName: await CoreConfigStore.readString(store, KEY_SELECTED_NAME),
      type: await CoreConfigStore.readString(store, KEY_TYPE),
      server: await CoreConfigStore.readString(store, KEY_SERVER),
      port: await CoreConfigStore.readString(store, KEY_PORT),
      tunAddress: CoreConfigStore.normalizeTunAddress(await CoreConfigStore.readString(store, KEY_TUN_ADDRESS, DEFAULT_TUN_ADDRESS)),
      dnsPrimary: await CoreConfigStore.readString(store, KEY_DNS_PRIMARY, DEFAULT_DNS_PRIMARY),
      dnsSecondary: await CoreConfigStore.readString(store, KEY_DNS_SECONDARY, DEFAULT_DNS_SECONDARY),
      rawUri: await CoreConfigStore.readString(store, KEY_RAW_URI),
      password: await CoreConfigStore.readString(store, KEY_PASSWORD),
      sni: await CoreConfigStore.readString(store, KEY_SNI),
      skipCertVerify: await CoreConfigStore.readString(store, KEY_SKIP_CERT_VERIFY),
      alpn: await CoreConfigStore.readString(store, KEY_ALPN),
      obfs: await CoreConfigStore.readString(store, KEY_OBFS),
      obfsPassword: await CoreConfigStore.readString(store, KEY_OBFS_PASSWORD),
      fp: await CoreConfigStore.readString(store, KEY_FP),
      mode: await CoreConfigStore.readString(store, KEY_MODE, DEFAULT_MODE)
    };
  }

  static toSummary(config: CoreRuntimeConfig): string {
    if (config.selectedName.length === 0) {
      return '未生成 core 配置';
    }
    return `${config.selectedName} / ${config.type || 'unknown'} / ${config.server || '-'}:${config.port || '-'}`;
  }

  static toNativeConfigText(config: CoreRuntimeConfig): string {
    return [
      `selectedName=${config.selectedName}`,
      `type=${config.type}`,
      `server=${config.server}`,
      `port=${config.port}`,
      `tunAddress=${config.tunAddress}`,
      `dnsPrimary=${config.dnsPrimary}`,
      `dnsSecondary=${config.dnsSecondary}`,
      `sni=${config.sni}`,
      `alpn=${config.alpn}`,
      `obfs=${config.obfs}`,
      'coreMode=mihomo',
      'packetInspector=false'
    ].join('\n');
  }

  private static async readString(store: preferences.Preferences, key: string, defaultValue: string = ''): Promise<string> {
    const value = await store.get(key, defaultValue);
    return typeof value === 'string' ? value : defaultValue;
  }

  private static normalizeTunAddress(value: string): string {
    if (value.length === 0 || value === '10.0.0.2/32' || value === '198.19.0.1/30') {
      return DEFAULT_TUN_ADDRESS;
    }
    return value;
  }
}
