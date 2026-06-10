import vpnCoreDefault, * as vpnCoreModule from 'libvpn_core.so';

interface VpnCoreNativeModule {
  startCore(): number;
  stopCore(): number;
  setTunFd(fd: number): number;
  setConfig(configText: string): number;
  getStats(): string;
}

export class VpnCoreBridge {
  private static readonly BRIDGE_VERSION: string = 'v4-dual-import';

  private static nativeModule(): VpnCoreNativeModule {
    const named = vpnCoreModule as VpnCoreNativeModule;
    if (named !== undefined && typeof named.setConfig === 'function') {
      return named;
    }

    const namespaceDefault = vpnCoreModule.default as VpnCoreNativeModule;
    if (namespaceDefault !== undefined && typeof namespaceDefault.setConfig === 'function') {
      return namespaceDefault;
    }

    const directDefault = vpnCoreDefault as VpnCoreNativeModule;
    if (directDefault !== undefined && typeof directDefault.setConfig === 'function') {
      return directDefault;
    }

    throw new Error(`libvpn_core.so: native exports not available bridge=${VpnCoreBridge.BRIDGE_VERSION}; named.setConfig=${typeof named.setConfig}; namespaceDefault.setConfig=${namespaceDefault === undefined ? 'undefined' : typeof namespaceDefault.setConfig}; directDefault.setConfig=${directDefault === undefined ? 'undefined' : typeof directDefault.setConfig}`);
  }

  static async startCore(): Promise<number> {
    const vpnCore = VpnCoreBridge.nativeModule();
    if (typeof vpnCore.startCore !== 'function') {
      throw new Error('libvpn_core.so: startCore not available (native module not loaded)');
    }
    return vpnCore.startCore();
  }

  static async stopCore(): Promise<number> {
    const vpnCore = VpnCoreBridge.nativeModule();
    if (typeof vpnCore.stopCore !== 'function') {
      throw new Error('libvpn_core.so: stopCore not available (native module not loaded)');
    }
    return vpnCore.stopCore();
  }

  static async setTunFd(fd: number): Promise<number> {
    const vpnCore = VpnCoreBridge.nativeModule();
    if (typeof vpnCore.setTunFd !== 'function') {
      throw new Error('libvpn_core.so: setTunFd not available (native module not loaded)');
    }
    return vpnCore.setTunFd(fd);
  }

  static async setConfig(configText: string): Promise<number> {
    const vpnCore = VpnCoreBridge.nativeModule();
    if (typeof vpnCore.setConfig !== 'function') {
      throw new Error('libvpn_core.so: setConfig not available (native module not loaded)');
    }
    return vpnCore.setConfig(configText);
  }

  static async getStats(): Promise<string> {
    const vpnCore = VpnCoreBridge.nativeModule();
    if (typeof vpnCore.getStats !== 'function') {
      throw new Error('libvpn_core.so: getStats not available (native module not loaded)');
    }
    return vpnCore.getStats();
  }
}
