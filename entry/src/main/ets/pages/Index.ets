import Want from '@ohos.app.ability.Want';
import router from '@ohos.router';
import vpnExtension from '@ohos.net.vpnExtension';
import socket from '@ohos.net.socket';
import connection from '@ohos.net.connection';
import { MihomoApi } from '../api/MihomoApi';
import { CoreConfigStore, DEFAULT_MODE } from '../core/CoreConfigStore';
import { CoreDiagnostic } from '../core/CoreDiagnostic';
import { CoreStatsStore } from '../core/CoreStatsStore';
import { MihomoProfileStore } from '../core/MihomoProfileStore';
import { VpnStatusText } from '../core/VpnStatusStore';
import { AppLogger, LOG_STORAGE_KEY } from '../logger/AppLogger';
import { CachedSubscription, CoreRuntimeConfig, ProxyNode, SubscriptionItem, SubscriptionParseResult } from '../model/SubscriptionModel';
import { SubscriptionCacheStore } from '../subscription/SubscriptionCacheStore';
import { SubscriptionService } from '../subscription/SubscriptionService';
import { SubscriptionManager } from '../subscription/SubscriptionManager';

const BUNDLE_NAME: string = 'com.ccsh.app';
const VPN_ABILITY_NAME: string = 'VpnAbility';
const VPN_START_TIMEOUT_MS: number = 30000;
const LOCAL_MIHOMO_CONTROLLER: string = 'http://127.0.0.1:9090';

@Entry
@Component
struct Index {
  @State vpnStatus: string = VpnStatusText.STOPPED;
  @State logs: string[] = [];
  @State subscriptionUrl: string = '';
  @State subscriptionName: string = '';
  @State subscriptionContent: string = '';
  @State proxies: ProxyNode[] = [];
  @State selectedProxyName: string = '';
  @State proxyGroupCount: number = 0;
  @State ruleCount: number = 0;
  @State isLoadingSubscription: boolean = false;
  @State isTestingDelay: boolean = false;
  @State coreConfigSummary: string = '未生成 core 配置';
  @State nativeCoreStats: string = '未启动';
  @State nativeCoreDiagnosis: string = '尚未收到 native core 状态';
  @State proxyMode: string = 'rule';
  @State subscriptions: SubscriptionItem[] = [];
  @State activeSubscriptionId: string = '';
  @State showSubscriptionManager: boolean = false;
  @State showAddSubscription: boolean = false;
  @State editingSubscriptionId: string = '';
  @State editingSubscriptionName: string = '';
  @State editingSubscriptionUrl: string = '';
  private isStartPending: boolean = false;
  private lastStartError: string = '';
  private refreshTimer: number = -1;
  private startWatchdogTimer: number = -1;

  aboutToAppear(): void {
    AppLogger.init(getContext(this));
    this.loadCoreConfigSummary();
    this.loadNativeCoreStats();
    this.loadSubscriptions();
    this.refreshLogs();
    this.refreshTimer = setInterval(() => {
      this.refreshLogs();
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.refreshTimer !== -1) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
    }
    this.clearStartWatchdog();
  }

  private buildVpnWant(): Want {
    return {
      deviceId: '',
      bundleName: BUNDLE_NAME,
      abilityName: VPN_ABILITY_NAME
    };
  }

  private async refreshLogs(): Promise<void> {
    this.logs = await AppLogger.readLogs();
    this.vpnStatus = await this.readSystemVpnStatus();
  }

  private async readSystemVpnStatus(): Promise<string> {
    try {
      const nets = await connection.getAllNets();
      for (let index = 0; index < nets.length; index++) {
        const caps = await connection.getNetCapabilities(nets[index]);
        const bearerTypes = caps.bearerTypes || [];
        if (bearerTypes.indexOf(connection.NetBearType.BEARER_VPN) >= 0) {
          this.isStartPending = false;
          this.lastStartError = '';
          return VpnStatusText.STARTED;
        }
      }
    } catch (error) {
      await AppLogger.error(`读取系统 VPN 状态失败: ${AppLogger.formatError(error)}`);
      if (this.lastStartError.length > 0) {
        return VpnStatusText.FAILED;
      }
      return this.isStartPending ? VpnStatusText.STARTING : VpnStatusText.STOPPED;
    }

    if (this.lastStartError.length > 0) {
      return VpnStatusText.FAILED;
    }
    return this.isStartPending ? VpnStatusText.STARTING : VpnStatusText.STOPPED;
  }

  private async startVpn(): Promise<void> {
    try {
      this.isStartPending = true;
      this.lastStartError = '';
      this.vpnStatus = VpnStatusText.STARTING;
      await CoreStatsStore.clear(getContext(this));
      this.nativeCoreStats = '暂无 Core 状态，请先启动网络扩展';
      this.nativeCoreDiagnosis = CoreDiagnostic.summarize(this.nativeCoreStats);
      await AppLogger.info('点击启动');
      await AppLogger.info('启动 VpnExtensionAbility');
      await vpnExtension.startVpnExtensionAbility(this.buildVpnWant());
      await AppLogger.info('startVpnExtensionAbility success, 等待 VpnAbility 创建 VPN 和启动 core');
      this.scheduleStartWatchdog();
    } catch (error) {
      this.clearStartWatchdog();
      this.isStartPending = false;
      this.lastStartError = AppLogger.formatError(error);
      this.vpnStatus = VpnStatusText.FAILED;
      await AppLogger.error(`startVpnExtensionAbility fail: ${this.lastStartError}`);
    } finally {
      await this.refreshLogs();
    }
  }

  private async stopVpn(): Promise<void> {
    try {
      this.clearStartWatchdog();
      this.isStartPending = false;
      this.lastStartError = '';
      await AppLogger.info('点击停止');
      await AppLogger.info('stop vpn');
      await vpnExtension.stopVpnExtensionAbility(this.buildVpnWant());
      await AppLogger.info('stopVpnExtensionAbility success');
    } catch (error) {
      await AppLogger.error(`stopVpnExtensionAbility fail: ${AppLogger.formatError(error)}`);
    } finally {
      await this.refreshLogs();
    }
  }

  private scheduleStartWatchdog(): void {
    this.clearStartWatchdog();
    this.startWatchdogTimer = setTimeout(() => {
      this.handleStartTimeout();
    }, VPN_START_TIMEOUT_MS);
  }

  private clearStartWatchdog(): void {
    if (this.startWatchdogTimer !== -1) {
      clearTimeout(this.startWatchdogTimer);
      this.startWatchdogTimer = -1;
    }
  }

  private async handleStartTimeout(): Promise<void> {
    this.startWatchdogTimer = -1;
    await this.refreshLogs();
    if (!this.isStartPending || this.vpnStatus !== VpnStatusText.STARTING) {
      return;
    }
    const stats = await CoreStatsStore.load(getContext(this));
    this.nativeCoreStats = stats;
    this.nativeCoreDiagnosis = CoreDiagnostic.summarize(stats);
    await AppLogger.error(`启动等待中: ${VPN_START_TIMEOUT_MS / 1000}s 内系统尚未报告 VPN 网络，当前 Core 状态: ${stats}`);
    await this.refreshLogs();
  }

  private async clearLogs(): Promise<void> {
    await AppLogger.clear();
    AppStorage.SetOrCreate<string[]>(LOG_STORAGE_KEY, []);
    this.logs = [];
  }

  // ===== Subscription Management =====

  private async loadSubscriptions(): Promise<void> {
    try {
      this.subscriptions = await SubscriptionManager.loadItems(getContext(this));
      this.activeSubscriptionId = await SubscriptionManager.getActiveId(getContext(this));
      // Load active subscription content
      if (this.activeSubscriptionId.length > 0) {
        const activeItem = this.subscriptions.find((item: SubscriptionItem) => item.id === this.activeSubscriptionId);
        if (activeItem) {
          this.subscriptionUrl = activeItem.url;
          this.subscriptionName = activeItem.name;
          this.subscriptionContent = activeItem.content;
          const result: SubscriptionParseResult = SubscriptionService.parse(activeItem.content);
          await this.applySubscriptionResult(result, false);
          await AppLogger.info(`已加载订阅: ${activeItem.name}, nodes=${this.proxies.length}`);
        }
      }
    } catch (error) {
      await AppLogger.error(`加载订阅列表失败: ${AppLogger.formatError(error)}`);
    } finally {
      await this.refreshLogs();
    }
  }

  private async addOrUpdateSubscription(): Promise<void> {
    const url = this.subscriptionUrl.trim();
    const name = this.subscriptionName.trim() || '未命名订阅';
    if (url.length === 0) {
      await AppLogger.error('配置源为空');
      await this.refreshLogs();
      return;
    }

    try {
      this.isLoadingSubscription = true;
      await AppLogger.info(`开始读取订阅: ${url}`);
      const content = await SubscriptionService.download(url);
      this.subscriptionContent = content;
      await AppLogger.info(`订阅读取成功: ${content.length} chars`);

      const result: SubscriptionParseResult = SubscriptionService.parse(content);
      await this.applySubscriptionResult(result, false);

      const id = this.editingSubscriptionId.length > 0 ? this.editingSubscriptionId : `sub_${Date.now()}`;
      const item: SubscriptionItem = {
        id: id,
        name: name,
        url: url,
        content: content,
        format: result.format,
        nodeCount: this.proxies.length,
        updatedAt: SubscriptionCacheStore.nowText()
      };

      if (this.editingSubscriptionId.length > 0) {
        await SubscriptionManager.updateItem(getContext(this), id, item);
        await AppLogger.info(`已更新订阅: ${name}`);
      } else {
        await SubscriptionManager.addItem(getContext(this), item);
        this.activeSubscriptionId = id;
        await SubscriptionManager.setActiveId(getContext(this), id);
        await AppLogger.info(`已添加订阅: ${name}`);
      }

      this.subscriptions = await SubscriptionManager.loadItems(getContext(this));
      this.editingSubscriptionId = '';
      this.editingSubscriptionName = '';
      this.editingSubscriptionUrl = '';

      if (this.proxies.length > 0) {
        await this.saveCoreConfigFromSelected();
      }
    } catch (error) {
      await AppLogger.error(`订阅操作失败: ${AppLogger.formatError(error)}`);
    } finally {
      this.isLoadingSubscription = false;
      await this.refreshLogs();
    }
  }

  private async deleteSubscription(id: string): Promise<void> {
    try {
      await SubscriptionManager.removeItem(getContext(this), id);
      this.subscriptions = await SubscriptionManager.loadItems(getContext(this));
      this.activeSubscriptionId = await SubscriptionManager.getActiveId(getContext(this));
      await AppLogger.info(`已删除订阅`);

      // Reload active subscription
      if (this.activeSubscriptionId.length > 0) {
        const activeItem = this.subscriptions.find((item: SubscriptionItem) => item.id === this.activeSubscriptionId);
        if (activeItem) {
          this.subscriptionUrl = activeItem.url;
          this.subscriptionName = activeItem.name;
          this.subscriptionContent = activeItem.content;
          const result: SubscriptionParseResult = SubscriptionService.parse(activeItem.content);
          await this.applySubscriptionResult(result, false);
        }
      } else {
        this.subscriptionUrl = '';
        this.subscriptionName = '';
        this.subscriptionContent = '';
        this.proxies = [];
        this.selectedProxyName = '';
      }
    } catch (error) {
      await AppLogger.error(`删除订阅失败: ${AppLogger.formatError(error)}`);
    } finally {
      await this.refreshLogs();
    }
  }

  private async switchSubscription(id: string): Promise<void> {
    try {
      this.activeSubscriptionId = id;
      await SubscriptionManager.setActiveId(getContext(this), id);
      const item = this.subscriptions.find((item: SubscriptionItem) => item.id === id);
      if (item) {
        this.subscriptionUrl = item.url;
        this.subscriptionName = item.name;
        this.subscriptionContent = item.content;
        const result: SubscriptionParseResult = SubscriptionService.parse(item.content);
        await this.applySubscriptionResult(result, false);
        await AppLogger.info(`切换订阅: ${item.name}`);
        if (this.proxies.length > 0) {
          await this.saveCoreConfigFromSelected();
        }
      }
    } catch (error) {
      await AppLogger.error(`切换订阅失败: ${AppLogger.formatError(error)}`);
    } finally {
      await this.refreshLogs();
    }
  }

  private async refreshSubscription(id: string): Promise<void> {
    try {
      const item = this.subscriptions.find((item: SubscriptionItem) => item.id === id);
      if (!item) return;

      await AppLogger.info(`刷新订阅: ${item.name}`);
      const content = await SubscriptionService.download(item.url);
      const result: SubscriptionParseResult = SubscriptionService.parse(content);

      await SubscriptionManager.updateItem(getContext(this), id, {
        content: content,
        format: result.format,
        nodeCount: result.proxies.length,
        updatedAt: SubscriptionCacheStore.nowText()
      });

      // If this is the active subscription, reload it
      if (id === this.activeSubscriptionId) {
        this.subscriptionContent = content;
        await this.applySubscriptionResult(result, false);
        if (this.proxies.length > 0) {
          await this.saveCoreConfigFromSelected();
        }
      }

      this.subscriptions = await SubscriptionManager.loadItems(getContext(this));
      await AppLogger.info(`订阅刷新成功: ${item.name}`);
    } catch (error) {
      await AppLogger.error(`刷新订阅失败: ${AppLogger.formatError(error)}`);
    } finally {
      await this.refreshLogs();
    }
  }

  private startEditSubscription(item: SubscriptionItem): void {
    this.editingSubscriptionId = item.id;
    this.editingSubscriptionName = item.name;
    this.editingSubscriptionUrl = item.url;
    this.subscriptionUrl = item.url;
    this.subscriptionName = item.name;
    this.showSubscriptionManager = false;
    this.showAddSubscription = true;
  }

  private cancelEdit(): void {
    this.editingSubscriptionId = '';
    this.editingSubscriptionName = '';
    this.editingSubscriptionUrl = '';
  }

  // ===== Proxy Mode Toggle =====

  private async toggleProxyMode(): Promise<void> {
    const newMode = this.proxyMode === 'rule' ? 'global' : 'rule';
    try {
      const config: CoreRuntimeConfig = await CoreConfigStore.load(getContext(this));
      config.mode = newMode;
      await CoreConfigStore.save(getContext(this), config);
      this.proxyMode = newMode;

      if (this.proxies.length > 0) {
        await MihomoProfileStore.writeRuntimeConfig(getContext(this), config);
      }
      await AppLogger.info(`通道模式切换为: ${this.proxyModeLabel(newMode)}`);
      await this.applyModeToRunningCore(newMode);
    } catch (error) {
      await AppLogger.error(`切换通道模式失败: ${AppLogger.formatError(error)}`);
    } finally {
      await this.refreshLogs();
    }
  }

  private proxyModeLabel(mode: string): string {
    return mode === 'global' ? '全局通道' : '路由策略';
  }

  private async applyModeToRunningCore(mode: string): Promise<void> {
    const api = new MihomoApi(LOCAL_MIHOMO_CONTROLLER);
    const runtimeMode = this.effectiveControllerMode(mode);
    try {
      await api.updateMode(runtimeMode);
      await AppLogger.info(`mihomo controller 已切换模式: ${runtimeMode}${runtimeMode !== mode ? '（规则为空，规则代理使用 direct）' : ''}`);
      await this.applySelectedProxyToRunningCore(api, runtimeMode);
      try {
        await api.closeAllConnections();
        await AppLogger.info('已关闭旧连接，新连接将使用新模式');
      } catch (closeError) {
        await AppLogger.error(`关闭旧连接失败: ${AppLogger.formatError(closeError)}`);
      }
    } catch (error) {
      await AppLogger.error(`实时切换 mihomo 模式失败: ${AppLogger.formatError(error)}；已保存配置，重启网络扩展后生效`);
    }
  }

  private effectiveControllerMode(mode: string): string {
    if (mode === 'global') {
      return 'global';
    }
    return this.ruleCount > 0 ? 'rule' : 'direct';
  }

  private async applySelectedProxyToRunningCore(api: MihomoApi, mode: string): Promise<void> {
    if (this.selectedProxyName.length === 0) {
      return;
    }
    if (mode === 'direct') {
      await AppLogger.info('当前为 direct 模式，跳过策略组端点切换');
      return;
    }
    const groupNames = mode === 'global' ? ['GLOBAL', 'SELECT'] : ['SELECT', 'GLOBAL'];
    for (let index = 0; index < groupNames.length; index++) {
      const groupName = groupNames[index];
      try {
        await api.selectProxy(groupName, this.selectedProxyName);
        await AppLogger.info(`mihomo ${groupName} 已选择: ${this.selectedProxyName}`);
      } catch (error) {
        await AppLogger.info(`mihomo ${groupName} 选择跳过: ${AppLogger.formatError(error)}`);
      }
    }
  }

  private async loadProxyMode(): Promise<void> {
    try {
      const config: CoreRuntimeConfig = await CoreConfigStore.load(getContext(this));
      this.proxyMode = config.mode || DEFAULT_MODE;
    } catch (_) {
      this.proxyMode = DEFAULT_MODE;
    }
  }

  // ===== Delay Testing =====

  private async testNodeDelay(node: ProxyNode): Promise<void> {
    try {
      const portNum = parseInt(node.port);
      if (isNaN(portNum) || portNum <= 0 || portNum > 65535) {
        node.delay = -1;
        await AppLogger.info(`${node.name} 端口无效,跳过`);
        return;
      }

      const startTime = Date.now();
      const tcp = socket.constructTCPSocketInstance();

      try {
        await new Promise<void>((resolve, reject) => {
          const timer = setTimeout(() => {
            tcp.close();
            reject(new Error('connect timeout'));
          }, 5000);

          tcp.connect({
            address: { address: node.server, port: portNum, family: 1 },
            timeout: 5000
          }, (err: Object) => {
            clearTimeout(timer);
            tcp.close();
            if (err) {
              reject(err);
            } else {
              resolve();
            }
          });
        });

        const delay = Date.now() - startTime;
        node.delay = delay;
        await AppLogger.info(`${node.name} = ${delay}ms`);
      } catch (_error) {
        node.delay = -1;
        await AppLogger.info(`${node.name} 超时/不可达`);
      }
    } catch (error) {
      node.delay = -1;
      await AppLogger.error(`测试异常: ${AppLogger.formatError(error)}`);
    }
  }

  private cloneProxyNode(p: ProxyNode): ProxyNode {
    const n: ProxyNode = {
      name: p.name,
      type: p.type,
      server: p.server,
      port: p.port,
      delay: p.delay
    };
    if (p.raw) n.raw = p.raw;
    if (p.password) n.password = p.password;
    if (p.sni) n.sni = p.sni;
    if (p.skipCertVerify) n.skipCertVerify = p.skipCertVerify;
    if (p.alpn) n.alpn = p.alpn;
    if (p.obfs) n.obfs = p.obfs;
    if (p.obfsPassword) n.obfsPassword = p.obfsPassword;
    if (p.fp) n.fp = p.fp;
    return n;
  }

  private async testAllDelays(): Promise<void> {
    if (this.proxies.length === 0) return;

    this.isTestingDelay = true;
    await AppLogger.info(`开始测试 ${this.proxies.length} 个端点的连通性`);

    // Test nodes in batches to avoid overwhelming
    const batchSize = 5;
    for (let i = 0; i < this.proxies.length; i += batchSize) {
      const batch = this.proxies.slice(i, i + batchSize);
      const promises = batch.map((node: ProxyNode) => this.testNodeDelay(node));
      await Promise.all(promises);
      // Replace tested objects with new copies so that @State + ForEach picks up the delay change
      const updated: ProxyNode[] = [];
      for (let j = 0; j < this.proxies.length; j++) {
        updated[j] = this.cloneProxyNode(this.proxies[j]);
      }
      this.proxies = updated;
    }

    this.isTestingDelay = false;
    await AppLogger.info('连通性检测完成');
    await this.refreshLogs();
  }

  private getDelayText(delay: number | undefined): string {
    if (delay === undefined) return '-';
    if (delay === -1) return '超时';
    if (delay < 100) return `${delay}ms`;
    if (delay < 300) return `${delay}ms`;
    return `${delay}ms`;
  }

  private getDelayColor(delay: number | undefined): string {
    if (delay === undefined) return '#59636E';
    if (delay === -1) return '#B42318';
    if (delay < 100) return '#0B7A53';
    if (delay < 300) return '#B76E00';
    return '#B42318';
  }

  private getFlagEmoji(node: ProxyNode): string {
    const name = node.name.toUpperCase();
    const nameMap: Record<string, string> = {
      'HK': '🇭🇰', 'HONGKONG': '🇭🇰', 'HONG KONG': '🇭🇰',
      'US': '🇺🇸', 'USA': '🇺🇸', 'UNITED STATES': '🇺🇸',
      'JP': '🇯🇵', 'JAPAN': '🇯🇵', 'TOKYO': '🇯🇵', 'OSAKA': '🇯🇵',
      'SG': '🇸🇬', 'SINGAPORE': '🇸🇬',
      'KR': '🇰🇷', 'KOREA': '🇰🇷', 'SEOUL': '🇰🇷',
      'TW': '🇹🇼', 'TAIWAN': '🇹🇼', 'TAIPEI': '🇹🇼',
      'UK': '🇬🇧', 'GB': '🇬🇧', 'LONDON': '🇬🇧',
      'DE': '🇩🇪', 'GERMANY': '🇩🇪', 'FRANKFURT': '🇩🇪',
      'FR': '🇫🇷', 'FRANCE': '🇫🇷', 'PARIS': '🇫🇷',
      'AU': '🇦🇺', 'AUSTRALIA': '🇦🇺', 'SYDNEY': '🇦🇺',
      'CA': '🇨🇦', 'CANADA': '🇨🇦', 'TORONTO': '🇨🇦',
      'IN': '🇮🇳', 'INDIA': '🇮🇳', 'MUMBAI': '🇮🇳',
      'RU': '🇷🇺', 'RUSSIA': '🇷🇺', 'MOSCOW': '🇷🇺',
      'BR': '🇧🇷', 'BRAZIL': '🇧🇷', 'SAOPAULO': '🇧🇷',
      'NL': '🇳🇱', 'NETHERLANDS': '🇳🇱',
      'IE': '🇮🇪', 'IRELAND': '🇮🇪',
      'TR': '🇹🇷', 'TURKEY': '🇹🇷',
      'AR': '🇦🇷', 'ARGENTINA': '🇦🇷',
      'PH': '🇵🇭', 'PHILIPPINES': '🇵🇭',
      'TH': '🇹🇭', 'THAILAND': '🇹🇭',
      'VN': '🇻🇳', 'VIETNAM': '🇻🇳',
      'MY': '🇲🇾', 'MALAYSIA': '🇲🇾',
      'ID': '🇮🇩', 'INDONESIA': '🇮🇩',
      'MX': '🇲🇽', 'MEXICO': '🇲🇽',
      'IL': '🇮🇱', 'ISRAEL': '🇮🇱',
      'ZA': '🇿🇦', 'SOUTH AFRICA': '🇿🇦',
      'SE': '🇸🇪', 'SWEDEN': '🇸🇪',
      'CH': '🇨🇭', 'SWITZERLAND': '🇨🇭',
      'IT': '🇮🇹', 'ITALY': '🇮🇹',
      'ES': '🇪🇸', 'SPAIN': '🇪🇸',
      'FI': '🇫🇮', 'FINLAND': '🇫🇮',
      'PL': '🇵🇱', 'POLAND': '🇵🇱',
      'UA': '🇺🇦', 'UKRAINE': '🇺🇦',
      'CL': '🇨🇱', 'CHILE': '🇨🇱',
      'CO': '🇨🇴', 'COLOMBIA': '🇨🇴',
      'EG': '🇪🇬', 'EGYPT': '🇪🇬',
      'PK': '🇵🇰', 'PAKISTAN': '🇵🇰',
      'BD': '🇧🇩', 'BANGLADESH': '🇧🇩',
      'KP': '🇰🇵', 'PYONGYANG': '🇰🇵',
      'LA': '🇱🇦', 'LAOS': '🇱🇦',
      'KH': '🇰🇭', 'CAMBODIA': '🇰🇭',
      'MM': '🇲🇲', 'MYANMAR': '🇲🇲',
      'NP': '🇳🇵', 'NEPAL': '🇳🇵',
      'LK': '🇱🇰', 'SRILANKA': '🇱🇰',
      'KZ': '🇰🇿', 'KAZAKHSTAN': '🇰🇿',
      'MO': '🇲🇴', 'MACAU': '🇲🇴', 'MACAO': '🇲🇴'
    };
    const keys = Object.keys(nameMap);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      if (name.indexOf(key) >= 0) {
        return nameMap[key];
      }
    }
    return '🌐';
  }

  // ===== Core Config =====

  private async parseSubscription(): Promise<void> {
    try {
      const result: SubscriptionParseResult = SubscriptionService.parse(this.subscriptionContent);
      await this.applySubscriptionResult(result, true);
      if (this.proxies.length === 0) {
        await AppLogger.error('未解析到端点: 当前只识别 Clash/Mihomo YAML 的 proxies 段，或 ss/vmess/trojan/vless/hysteria2/tuic URI 列表');
      } else {
        await this.saveCoreConfigFromSelected();
      }
    } catch (error) {
      await AppLogger.error(`订阅解析失败: ${AppLogger.formatError(error)}`);
    } finally {
      await this.refreshLogs();
    }
  }

  private async applySubscriptionResult(result: SubscriptionParseResult, saveCache: boolean): Promise<void> {
    if (result.normalizedContent.length > 0 && result.normalizedContent !== this.subscriptionContent.trim()) {
      this.subscriptionContent = result.normalizedContent;
      await AppLogger.info('订阅内容已自动 base64 解码');
    } else {
      this.subscriptionContent = result.normalizedContent;
    }

    this.proxies = result.proxies;
    this.proxyGroupCount = result.proxyGroupCount;
    this.ruleCount = result.ruleCount;
    this.selectedProxyName = await this.resolveSelectedProxyName(this.proxies);
    await AppLogger.info(`订阅解析完成: format=${result.format}, nodes=${this.proxies.length}, groups=${this.proxyGroupCount}, rules=${this.ruleCount}`);

    if (result.normalizedContent.length > 0 && this.proxies.length > 0) {
      await MihomoProfileStore.saveRawProfile(getContext(this), result.normalizedContent);
      await AppLogger.info(`已保存 mihomo 原始订阅: ${MihomoProfileStore.rawProfilePath(getContext(this))}`);
      if (saveCache) {
        await SubscriptionCacheStore.save(getContext(this), {
          url: this.subscriptionUrl.trim(),
          content: result.normalizedContent,
          format: result.format,
          nodeCount: this.proxies.length,
          updatedAt: SubscriptionCacheStore.nowText()
        });
        await AppLogger.info(`已保存订阅缓存: nodes=${this.proxies.length}`);
      }
    }
  }

  private async resolveSelectedProxyName(proxies: ProxyNode[]): Promise<string> {
    if (proxies.length === 0) {
      return '';
    }

    try {
      const config: CoreRuntimeConfig = await CoreConfigStore.load(getContext(this));
      for (let index = 0; index < proxies.length; index++) {
        if (proxies[index].name === config.selectedName) {
          return config.selectedName;
        }
      }
    } catch (_) {
    }

    return proxies[0].name;
  }

  private async loadSampleSubscription(): Promise<void> {
    try {
      this.subscriptionContent = SubscriptionService.sampleConfig();
      await AppLogger.info('载入示例订阅');
      const result: SubscriptionParseResult = SubscriptionService.parse(this.subscriptionContent);
      await this.applySubscriptionResult(result, false);
      if (this.proxies.length > 0) {
        await this.saveCoreConfigFromSelected();
      }
    } catch (error) {
      await AppLogger.error(`示例订阅解析失败: ${AppLogger.formatError(error)}`);
    } finally {
      await this.refreshLogs();
    }
  }

  private findSelectedProxy(): ProxyNode | undefined {
    for (let index = 0; index < this.proxies.length; index++) {
      if (this.proxies[index].name === this.selectedProxyName) {
        return this.proxies[index];
      }
    }
    return undefined;
  }

  private async saveCoreConfigFromSelected(): Promise<void> {
    const node = this.findSelectedProxy();
    if (node === undefined) {
      await AppLogger.error('生成 core 配置失败: 未选择端点');
      await this.refreshLogs();
      return;
    }

    try {
      const config: CoreRuntimeConfig = CoreConfigStore.buildConfig(node);
      config.mode = this.proxyMode;
      await CoreConfigStore.save(getContext(this), config);
      this.coreConfigSummary = CoreConfigStore.toSummary(config);
      await AppLogger.info(`生成 core 配置: ${this.coreConfigSummary}`);
    } catch (error) {
      await AppLogger.error(`生成 core 配置失败: ${AppLogger.formatError(error)}`);
    } finally {
      await this.refreshLogs();
    }
  }

  private async selectProxyNode(node: ProxyNode): Promise<void> {
    this.selectedProxyName = node.name;
    await AppLogger.info(`选择端点: ${node.name}`);
    await this.saveCoreConfigFromSelected();
    try {
      const api = new MihomoApi(LOCAL_MIHOMO_CONTROLLER);
      await this.applySelectedProxyToRunningCore(api, this.proxyMode);
      try {
        await api.closeAllConnections();
        await AppLogger.info('端点切换后已关闭旧会话');
      } catch (closeError) {
        await AppLogger.error(`节点切换后关闭旧连接失败: ${AppLogger.formatError(closeError)}`);
      }
    } catch (error) {
      await AppLogger.error(`实时切换端点失败: ${AppLogger.formatError(error)}；已保存配置，重启网络扩展后生效`);
    } finally {
      await this.refreshLogs();
    }
  }

  private async loadCoreConfigSummary(): Promise<void> {
    try {
      const config: CoreRuntimeConfig = await CoreConfigStore.load(getContext(this));
      this.coreConfigSummary = CoreConfigStore.toSummary(config);
      this.proxyMode = config.mode || DEFAULT_MODE;
    } catch (_) {
      this.coreConfigSummary = '未生成 core 配置';
      this.proxyMode = DEFAULT_MODE;
    }
  }

  private async refreshNativeCoreStats(): Promise<void> {
    try {
      this.nativeCoreStats = `${await CoreStatsStore.load(getContext(this))}; uiReadAt=${this.nowText()}`;
      this.nativeCoreDiagnosis = CoreDiagnostic.summarize(this.nativeCoreStats);
      await AppLogger.info(`shared native stats: ${this.nativeCoreStats}`);
      await AppLogger.info(`shared core diagnosis: ${this.nativeCoreDiagnosis}`);
      if (this.vpnStatus === VpnStatusText.STARTING && this.nativeCoreStats.indexOf('暂无 Core 状态') >= 0) {
        await AppLogger.error('Core 状态仍为空: VpnAbility 可能未进入 native startCore，或 Extension 启动过程中卡住');
      }
    } catch (error) {
      this.nativeCoreStats = `读取失败: ${AppLogger.formatError(error)}`;
      await AppLogger.error(`读取 shared native stats 失败: ${AppLogger.formatError(error)}`);
    } finally {
      await this.refreshLogs();
    }
  }

  private async loadNativeCoreStats(): Promise<void> {
    try {
      this.nativeCoreStats = await CoreStatsStore.load(getContext(this));
      this.nativeCoreDiagnosis = CoreDiagnostic.summarize(this.nativeCoreStats);
    } catch (_) {
      this.nativeCoreStats = '暂无 Core 状态，请先启动网络扩展';
      this.nativeCoreDiagnosis = CoreDiagnostic.summarize(this.nativeCoreStats);
    }
  }

  private nowText(): string {
    const now = new Date();
    const hour = this.pad(now.getHours());
    const minute = this.pad(now.getMinutes());
    const second = this.pad(now.getSeconds());
    return `${hour}:${minute}:${second}`;
  }

  private pad(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  @Builder
  AddSubscriptionDialog() {
    Column({ space: 10 }) {
      Row() {
        Text(this.editingSubscriptionId.length > 0 ? '编辑配置' : '添加配置')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
        Blank()
        Button('关闭')
          .height(24)
          .fontSize(10)
          .type(ButtonType.Normal)
          .borderRadius(6)
          .onClick(() => {
            this.showAddSubscription = false;
            this.cancelEdit();
          })
      }
      .width('100%')

      if (this.editingSubscriptionId.length > 0) {
        Row() {
          Text(`编辑: ${this.editingSubscriptionName}`)
            .fontSize(11)
            .fontColor('#1F5EFF')
          Blank()
          Button('取消编辑')
            .height(24)
            .fontSize(10)
            .type(ButtonType.Normal)
            .onClick(() => {
              this.cancelEdit();
            })
        }
        .width('100%')
      }

      TextInput({ placeholder: '配置名称（可选）', text: this.subscriptionName })
        .height(28)
        .fontSize(10)
        .placeholderFont({ size: 10 })
        .borderRadius(4)
        .onChange((value: string) => {
          this.subscriptionName = value;
        })

      TextInput({ placeholder: '配置源（Clash/Mihomo YAML）', text: this.subscriptionUrl })
        .height(28)
        .fontSize(10)
        .placeholderFont({ size: 10 })
        .borderRadius(4)
        .onChange((value: string) => {
          this.subscriptionUrl = value;
        })

      Row({ space: 4 }) {
        Button(this.editingSubscriptionId.length > 0 ? '更新' : '添加')
          .height(20)
          .fontSize(10)
          .type(ButtonType.Normal)
          .borderRadius(4)
          .enabled(!this.isLoadingSubscription)
          .onClick(() => {
            this.addOrUpdateSubscription();
            if (this.editingSubscriptionId.length === 0) {
              this.showAddSubscription = false;
            }
          })

        Button('解析')
          .height(20)
          .fontSize(10)
          .type(ButtonType.Normal)
          .borderRadius(4)
          .onClick(() => {
            this.parseSubscription();
          })

        Button('示例')
          .height(20)
          .fontSize(10)
          .type(ButtonType.Normal)
          .borderRadius(4)
          .onClick(() => {
            this.loadSampleSubscription();
          })
      }
      .width('100%')

      TextArea({ placeholder: '粘贴配置 YAML 后点"解析"', text: this.subscriptionContent })
        .height(80)
        .fontSize(10)
        .placeholderFont({ size: 10 })
        .borderRadius(4)
        .onChange((value: string) => {
          this.subscriptionContent = value;
        })
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#F3F4F6')
    .borderRadius(12)
    .shadow({ radius: 16, color: '#00000020', offsetY: 2 })
  }

  @Builder
  SubscriptionManagerDialog() {
    Column({ space: 10 }) {
      Row() {
        Text('配置管理')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
        Blank()
        Button('关闭')
          .height(24)
          .type(ButtonType.Normal)
          .borderRadius(6)
          .fontSize(11)
          .onClick(() => {
            this.showSubscriptionManager = false;
            this.cancelEdit();
          })
      }
      .width('100%')

      List({ space: 8 }) {
        ForEach(this.subscriptions, (item: SubscriptionItem) => {
          ListItem() {
            Column({ space: 8 }) {
              // Header row
              Row() {
                Column({ space: 2 }) {
                  Text(item.name)
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#111827')
                  Text(`同步: ${item.updatedAt}`)
                    .fontSize(10)
                    .fontColor('#6B7280')
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                if (item.id === this.activeSubscriptionId) {
                  Text('已同步')
                    .fontSize(10)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#60A5FA')
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .backgroundColor('#EFF6FF')
                    .borderRadius(8)
                }
              }
              .width('100%')

              // Node count
              Row() {
                Text(`${item.nodeCount} 端点`)
                  .fontSize(11)
                  .fontColor('#6B7280')
                Blank()
                Text(item.format === 'uri-list' ? 'URI' : 'YAML')
                  .fontSize(10)
                  .fontColor('#9CA3AF')
              }
              .width('100%')

              // Action buttons
              Row({ space: 6 }) {
                if (item.id !== this.activeSubscriptionId) {
                  Button('切换')
                    .height(24)
                    .fontSize(10)
                    .onClick(() => {
                      this.switchSubscription(item.id);
                      this.showSubscriptionManager = false;
                    })
                }

                Button('刷新')
                  .height(24)
                  .type(ButtonType.Normal)
          .borderRadius(6)
                  .fontSize(10)
                  .onClick(() => {
                    this.refreshSubscription(item.id);
                  })

                Button('编辑')
                  .height(24)
                  .type(ButtonType.Normal)
          .borderRadius(6)
                  .fontSize(10)
                  .onClick(() => {
                    this.startEditSubscription(item);
                  })

                Button('删除')
                  .height(24)
                  .type(ButtonType.Normal)
          .borderRadius(6)
                  .fontSize(10)
                  .fontColor('#EF4444')
                  .onClick(() => {
                    this.deleteSubscription(item.id);
                  })
              }
              .width('100%')
              .justifyContent(FlexAlign.End)
            }
            .width('100%')
            .padding(10)
            .backgroundColor(item.id === this.activeSubscriptionId ? '#F0F9FF' : '#FFFFFF')
            .borderRadius(10)
            .border({ width: 1, color: item.id === this.activeSubscriptionId ? '#60A5FA' : '#E5E7EB' })
          }
        }, (item: SubscriptionItem) => item.id)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('70%')
    .padding(10)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .shadow({ radius: 16, color: '#00000020', offsetY: 2 })
  }

  @Builder
  SubscriptionPanel() {
    Column() {
      // Header section with tinted background
      Column({ space: 8 }) {
        Row() {
          Text('配置管理')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#111827')
          Blank()
          Row({ space: 8 }) {
            Button('添加')
              .height(24)
              .fontSize(10)
              .type(ButtonType.Normal)
            .borderRadius(6)
              .onClick(() => {
                this.cancelEdit();
                this.subscriptionName = '';
                this.subscriptionUrl = '';
                this.subscriptionContent = '';
                this.showAddSubscription = true;
              })
            Button('列表')
              .height(24)
              .fontSize(10)
              .type(ButtonType.Normal)
            .borderRadius(6)
              .onClick(() => {
                this.showSubscriptionManager = true;
              })
          }
        }
        .width('100%')

        Row() {
          Text(`端点 ${this.proxies.length}`)
            .fontSize(11)
            .fontColor('#6B7280')
          Blank()
          Text(`组 ${this.proxyGroupCount} / 路由策略 ${this.ruleCount}`)
            .fontSize(11)
            .fontColor('#6B7280')
        }
        .width('100%')

        if (this.selectedProxyName.length > 0) {
          Text(`当前选择: ${this.selectedProxyName}`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#0B7A53')
            .width('100%')
        }

        // Proxy mode toggle
        Row({ space: 6 }) {
          Text('模式:')
            .fontSize(11)
            .fontColor('#6B7280')
          Text(this.proxyMode === 'rule' ? '路由策略' : '全局通道')
            .fontSize(11)
            .fontColor(this.proxyMode === 'rule' ? '#0B7A53' : '#D97706')
            .fontWeight(FontWeight.Medium)
          Button('切换')
            .height(24)
            .fontSize(10)
            .type(ButtonType.Normal)
            .borderRadius(6)
            .onClick(() => {
              this.toggleProxyMode();
            })
          Blank()
          Button(this.isTestingDelay ? '测试中...' : '检测')
            .height(24)
            .fontSize(10)
            .type(ButtonType.Normal)
            .borderRadius(6)
            .enabled(!this.isTestingDelay && this.proxies.length > 0)
            .onClick(() => {
              this.testAllDelays();
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding(10)
      .backgroundColor('#F0F4FF')
      .borderRadius({ topLeft: 10, topRight: 10 })

      // Endpoint list section
      List({ space: 0 }) {
        ForEach(this.proxies, (node: ProxyNode) => {
          ListItem() {
            Row({ space: 8 }) {
              // Flag icon
              Text(this.getFlagEmoji(node))
                .fontSize(14)
                .width(22)
                .textAlign(TextAlign.Center)

              // Node info
              Column({ space: 1 }) {
                Text(node.name)
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#111827')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${node.type || 'unknown'} / ${node.server || '-'}:${node.port || '-'}`)
                  .fontSize(10)
                  .fontColor('#6B7280')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              // Delay status
              Text(this.getDelayText(node.delay))
                .fontSize(11)
                .fontColor(this.getDelayColor(node.delay))
                .width(48)
                .textAlign(TextAlign.End)

              // Select indicator
              Circle()
                .width(6)
                .height(6)
                .fill(this.selectedProxyName === node.name ? '#3B82F6' : 'transparent')
                .stroke('#3B82F6')
                .strokeWidth(0.5)
                .onClick(() => {
                  this.selectProxyNode(node);
                })
            }
            .width('100%')
            .padding({ left: 8, right: 8, top: 7, bottom: 7 })
            .backgroundColor(this.selectedProxyName === node.name ? '#EFF6FF' : '#FFFFFF')
          }
          .onClick(() => {
            this.selectProxyNode(node);
          })
        }, (node: ProxyNode) => `${node.name}-${node.server}-${node.port}-${node.delay}`)
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor('#FFFFFF')
      .borderRadius({ bottomLeft: 10, bottomRight: 10 })
      .divider({ strokeWidth: 0.5, color: '#F3F4F6', startMargin: 8, endMargin: 8 })
    }
    .width('100%')
    .borderRadius(10)
    .layoutWeight(1)
  }

  @Builder
  StatusPanel() {
    Row() {
      Column({ space: 4 }) {
        Text('VPN 状态')
          .fontSize(11)
          .fontColor('#6B7280')
        Text(this.vpnStatus)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.statusColor())
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Blank()
      Text('运行日志')
        .fontSize(12)
        .fontColor('#3B82F6')
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor('#EFF6FF')
        .borderRadius(10)
        .onClick(() => {
          router.pushUrl({ url: 'pages/LogPage' });
        })
    }
    .width('100%')
    .padding(10)
    .backgroundColor('#FFFFFF')
    .borderRadius(10)
  }

  @Builder
  NativeCorePanel() {
    Column({ space: 10 }) {
      Row() {
        Text('Adapter / Core')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
        Blank()
        Button('刷新状态')
          .height(36)
          .type(ButtonType.Normal)
          .borderRadius(6)
          .onClick(() => {
            this.refreshNativeCoreStats();
          })
      }
      .width('100%')

      Text(this.nativeCoreStats)
        .fontSize(12)
        .fontColor('#59636E')
        .width('100%')

      Text(this.nativeCoreDiagnosis)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.nativeCoreDiagnosisColor())
        .width('100%')
        .padding(10)
        .backgroundColor('#F8FAFC')
        .borderRadius(6)
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({ width: 1, color: '#D9E1EA' })
  }

  private statusColor(): string {
    if (this.vpnStatus === VpnStatusText.STARTED) {
      return '#0B7A53';
    }
    if (this.vpnStatus === VpnStatusText.TUN_CREATED) {
      return '#0B7A53';
    }
    if (this.vpnStatus === VpnStatusText.CORE_FAILED) {
      return '#B76E00';
    }
    if (this.vpnStatus === VpnStatusText.FAILED) {
      return '#B42318';
    }
    if (this.vpnStatus === VpnStatusText.STARTING) {
      return '#1F5EFF';
    }
    return '#1F2933';
  }

  private nativeCoreDiagnosisColor(): string {
    if (this.nativeCoreDiagnosis.indexOf('已运行') >= 0) {
      return '#0B7A53';
    }
    if (this.nativeCoreDiagnosis.indexOf('已创建') >= 0 ||
      this.nativeCoreDiagnosis.indexOf('正在') >= 0) {
      return '#B76E00';
    }
    if (this.nativeCoreDiagnosis.indexOf('占位') >= 0 ||
      this.nativeCoreDiagnosis.indexOf('未加载') >= 0 ||
      this.nativeCoreDiagnosis.indexOf('失败') >= 0 ||
      this.nativeCoreDiagnosis.indexOf('异常') >= 0 ||
      this.nativeCoreDiagnosis.indexOf('无效') >= 0 ||
      this.nativeCoreDiagnosis.indexOf('不完整') >= 0) {
      return '#B42318';
    }
    return '#59636E';
  }

  build() {
    Stack() {
      Column({ space: 10 }) {
        this.StatusPanel()

        // VPN buttons
        Row({ space: 6 }) {
          Button('启动网络扩展')
            .height(28)
            .fontSize(12)
            .type(ButtonType.Normal)
            .borderRadius(6)
            .enabled(this.vpnStatus === VpnStatusText.STOPPED || this.vpnStatus === VpnStatusText.FAILED || this.vpnStatus === VpnStatusText.CORE_FAILED)
            .onClick(() => {
              this.startVpn();
            })

          Button('停止网络扩展')
            .height(28)
            .fontSize(12)
            .type(ButtonType.Normal)
            .borderRadius(6)
            .enabled(this.vpnStatus === VpnStatusText.STARTED || this.vpnStatus === VpnStatusText.TUN_CREATED || this.vpnStatus === VpnStatusText.CORE_FAILED)
            .onClick(() => {
              this.stopVpn();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)

        this.SubscriptionPanel()
      }
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .width('100%')
      .height('100%')

      // Subscription Manager Dialog Overlay
      if (this.showSubscriptionManager) {
        Column() {
          Blank()
          Column() {
            this.SubscriptionManagerDialog()
          }
          .width('90%')
          .backgroundColor('#FFFFFF')
          .borderRadius(12)
          .border({ width: 1, color: '#E5E7EB' })
          .shadow({ radius: 24, color: '#00000040', offsetY: 6 })
          .onClick(() => {})
          Blank()
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#00000066')
        .backdropBlur(3)
        .onClick(() => {
          this.showSubscriptionManager = false;
          this.cancelEdit();
        })
      }

      // Add Subscription Dialog Overlay
      if (this.showAddSubscription) {
        Column() {
          Blank()
          Column() {
            this.AddSubscriptionDialog()
          }
          .width('90%')
          .backgroundColor('#F3F4F6')
          .borderRadius(12)
          .border({ width: 1, color: '#D1D5DB' })
          .shadow({ radius: 24, color: '#00000040', offsetY: 6 })
          .onClick(() => {})
          Blank()
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#00000066')
        .backdropBlur(3)
        .onClick(() => {
          this.showAddSubscription = false;
          this.cancelEdit();
          this.subscriptionName = '';
          this.subscriptionUrl = '';
          this.subscriptionContent = '';
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7FA')
  }
}
