import Want from '@ohos.app.ability.Want';
import VpnExtensionAbility from '@ohos.app.ability.VpnExtensionAbility';
import vpnExtension from '@ohos.net.vpnExtension';
import { CoreConfigStore, DEFAULT_TUN_ADDRESS } from '../core/CoreConfigStore';
import { CoreDiagnostic } from '../core/CoreDiagnostic';
import { CoreStatsStore } from '../core/CoreStatsStore';
import { MihomoProfileStore } from '../core/MihomoProfileStore';
import { AppLogger } from '../logger/AppLogger';
import { CoreRuntimeConfig } from '../model/SubscriptionModel';
import { VpnCoreBridge } from '../native/VpnCoreBridge';

interface TunAddressConfig {
  address: string;
  prefixLength: number;
}

export default class VpnAbility extends VpnExtensionAbility {
  private vpnConnection?: vpnExtension.VpnConnection;
  private tunFd: number = -1;

  onCreate(want: Want): void {
    this.handleCreate().catch((error: Object) => {
      this.handleFatalError('onCreate async fail', error);
    });
  }

  onDestroy(): void {
    this.handleDestroy().catch((error: Object) => {
      this.handleFatalError('onDestroy async fail', error);
    });
  }

  private async handleFatalError(prefix: string, error: Object): Promise<void> {
    try {
      AppLogger.init(this.context);
      await AppLogger.error(`${prefix}: ${AppLogger.formatError(error)}`);
      await CoreStatsStore.save(this.context, `phase=fatalError; prefix=${prefix}; error=${AppLogger.formatError(error)}`);
    } catch (_) {
    }
  }

  private async handleCreate(): Promise<void> {
    AppLogger.init(this.context);
    await AppLogger.info('onCreate');
    await CoreStatsStore.save(this.context, 'phase=onCreate; message=VpnExtensionAbility entered');
    await this.createVpn();
  }

  private async handleDestroy(): Promise<void> {
    AppLogger.init(this.context);
    await AppLogger.info('onDestroy');
    await this.stopVpn();
  }

  private async createVpn(): Promise<void> {
    const coreConfig: CoreRuntimeConfig = await CoreConfigStore.load(this.context);
    const vpnAddress = this.parseTunAddress(coreConfig.tunAddress);
    try {
      await CoreStatsStore.save(this.context, 'phase=createVpnConnection; message=calling createVpnConnection');
      this.vpnConnection = vpnExtension.createVpnConnection(this.context);
      await AppLogger.info('createVpnConnection success');
      await CoreStatsStore.save(this.context, 'phase=createVpnConnectionSuccess');
      try {
        await this.vpnConnection.protectProcessNet();
        await AppLogger.info('protectProcessNet success');
        await CoreStatsStore.save(this.context, 'phase=protectProcessNetSuccess');
      } catch (protectError) {
        await AppLogger.error(`protectProcessNet fail: ${AppLogger.formatError(protectError)}`);
        await CoreStatsStore.save(this.context, `phase=protectProcessNetFail; error=${AppLogger.formatError(protectError)}`);
      }
    } catch (error) {
      await AppLogger.error(`createVpnConnection fail: ${AppLogger.formatError(error)}`);
      await CoreStatsStore.save(this.context, `phase=createVpnConnectionFail; error=${AppLogger.formatError(error)}`);
      return;
    }

    try {
      await CoreStatsStore.save(this.context, 'phase=createVpn; message=calling VpnConnection.create');
      const config: vpnExtension.VpnConfig = {
        addresses: [
          {
            address: {
              address: vpnAddress.address,
              family: 1
            },
            prefixLength: vpnAddress.prefixLength
          }
        ],
        routes: [
          {
            interface: 'vpn-tun',
            destination: {
              address: {
                address: '0.0.0.0',
                family: 1
              },
              prefixLength: 0
            },
            gateway: {
              address: '0.0.0.0',
              family: 1
            },
            hasGateway: false,
            isDefaultRoute: true
          }
        ],
        dnsAddresses: [
          '198.18.0.2'
        ],
        mtu: 1400,
        isIPv4Accepted: true,
        isIPv6Accepted: false,
        isBlocking: false
      };

      this.tunFd = await this.vpnConnection.create(config);
      await AppLogger.info(`create vpn success, tunFd=${this.tunFd}`);
      await CoreStatsStore.save(this.context, `phase=createVpnSuccess; tunFd=${this.tunFd}`);
      // Re-apply protectProcessNet after TUN creation to ensure outbound sockets
      // from this process (including mihomo's proxy connections) bypass the TUN.
      try {
        await this.vpnConnection.protectProcessNet();
        await AppLogger.info('protectProcessNet (post-create) success');
        await CoreStatsStore.save(this.context, 'phase=protectProcessNetPostCreateSuccess');
      } catch (protectError) {
        await AppLogger.error(`protectProcessNet (post-create) fail: ${AppLogger.formatError(protectError)}`);
      }
      await AppLogger.info(`core config: ${CoreConfigStore.toSummary(coreConfig)}`);
      await AppLogger.info(`vpn address=${vpnAddress.address}/${vpnAddress.prefixLength}, systemDns=198.18.0.2`);
      await this.startNativeCore(this.tunFd);
    } catch (error) {
      await AppLogger.error(`create vpn fail: ${AppLogger.formatError(error)}`);
      await CoreStatsStore.save(this.context, `phase=createVpnFail; error=${AppLogger.formatError(error)}`);
      await this.destroyVpnAfterCoreFailure();
    }
  }

  private parseTunAddress(value: string): TunAddressConfig {
    const normalized = value.length > 0 && value !== '10.0.0.2/32' && value !== '198.19.0.1/30' ? value : DEFAULT_TUN_ADDRESS;
    const parts = normalized.split('/');
    const address = parts[0].length > 0 ? parts[0] : '198.18.0.1';
    const prefix = parts.length > 1 ? Number(parts[1]) : 30;
    return {
      address,
      prefixLength: Number.isFinite(prefix) && prefix > 0 && prefix <= 32 ? prefix : 30
    };
  }

  private async startNativeCore(fd: number): Promise<void> {
    try {
      const coreConfig: CoreRuntimeConfig = await CoreConfigStore.load(this.context);
      await CoreStatsStore.clear(this.context);
      await CoreStatsStore.save(this.context, 'phase=startNativeCore; message=prepare mihomo runtime config');
      const mihomoConfigPath = await MihomoProfileStore.writeRuntimeConfig(this.context, coreConfig);
      await AppLogger.info(`mihomo runtime config: ${mihomoConfigPath}`);
      const configText = [
        CoreConfigStore.toNativeConfigText(coreConfig),
        `mihomoConfigPath=${mihomoConfigPath}`,
        `statsFile=${CoreStatsStore.statsFilePath(this.context)}`,
        `nativeLibraryDir=${this.context.bundleCodeDir}/libs/arm64`
      ].join('\n');
      await CoreStatsStore.save(this.context, 'phase=loadNativeBridge; message=loading vpn_core napi module');
      const configResult = await VpnCoreBridge.setConfig(configText);
      await AppLogger.info(`native setConfig result=${configResult}`);
      await CoreStatsStore.save(this.context, `phase=nativeSetConfig; result=${configResult}`);
      const setResult = await VpnCoreBridge.setTunFd(fd);
      await AppLogger.info(`native setTunFd result=${setResult}`);
      await CoreStatsStore.save(this.context, `phase=nativeSetTunFd; result=${setResult}; tunFd=${fd}`);
      const startResult = await VpnCoreBridge.startCore();
      await AppLogger.info(`native startCore result=${startResult}`);
      const stats = await VpnCoreBridge.getStats();
      await AppLogger.info(`native stats: ${stats}`);
      await AppLogger.info(`core diagnosis: ${CoreDiagnostic.summarize(stats)}`);
      if (startResult !== 0 && startResult !== 1) {
        await AppLogger.error('mihomo core 未启动: 请检查 libmihomo_adapter.so 是否已随包提供并导出约定 C ABI');
        await CoreStatsStore.save(this.context, `phase=nativeStartReturnedFailure; result=${startResult}; stats=${stats}`);
      } else {
        // Delayed protectProcessNet: mihomo creates sockets after start, so we need to
        // re-protect after a delay to ensure DNS and proxy sockets bypass TUN.
        try {
          await new Promise<void>((resolve) => setTimeout(resolve, 2000));
          if (this.vpnConnection) {
            await this.vpnConnection.protectProcessNet();
            await AppLogger.info('protectProcessNet (post-start delay 2s) success');
            await CoreStatsStore.save(this.context, 'phase=protectProcessNetPostStartSuccess');
          }
        } catch (protectError) {
          await AppLogger.error(`protectProcessNet (post-start delay) fail: ${AppLogger.formatError(protectError)}`);
        }
      }
    } catch (error) {
      const message = `native startCore fail: ${AppLogger.formatError(error)}`;
      await AppLogger.error(message);
      await CoreStatsStore.save(this.context, `phase=nativeStartException; error=${message}`);
    }
  }

  private async destroyVpnAfterCoreFailure(): Promise<void> {
    if (this.vpnConnection === undefined) {
      return;
    }
    try {
      await this.vpnConnection.destroy();
      await AppLogger.info('destroy vpn after core failure success');
    } catch (error) {
      await AppLogger.error(`destroy vpn after core failure fail: ${AppLogger.formatError(error)}`);
    } finally {
      this.tunFd = -1;
      this.vpnConnection = undefined;
    }
  }

  private async stopVpn(): Promise<void> {
    await AppLogger.info('stop vpn');
    if (this.vpnConnection === undefined) {
      await AppLogger.info('stop vpn skipped: VpnConnection is empty');
      return;
    }

    try {
      try {
        const stopResult = await VpnCoreBridge.stopCore();
        await AppLogger.info(`native stopCore result=${stopResult}`);
        await AppLogger.info(`native stats: ${await VpnCoreBridge.getStats()}`);
      } catch (error) {
        await AppLogger.error(`native stopCore fail: ${AppLogger.formatError(error)}`);
      }
      await this.vpnConnection.destroy();
      await AppLogger.info('destroy vpn success');
    } catch (error) {
      await AppLogger.error(`destroy vpn fail: ${AppLogger.formatError(error)}`);
    } finally {
      this.tunFd = -1;
      this.vpnConnection = undefined;
    }
  }
}
