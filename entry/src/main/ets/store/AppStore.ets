import { DEFAULT_CONTROLLER_URL } from '../common/Constants';
import { toErrorMessage } from '../common/Utils';
import { MihomoApi } from '../api/MihomoApi';
import { AppConfig } from '../model/AppConfigModel';

export type ConnectionStatus = '未连接' | '控制器可用' | '连接失败';

export const STORAGE_CONTROLLER_URL: string = 'controllerUrl';
export const STORAGE_SECRET: string = 'secret';
export const STORAGE_CONNECTION_STATUS: string = 'connectionStatus';
export const STORAGE_ERROR_MESSAGE: string = 'errorMessage';
export const STORAGE_ACTIVE_CONNECTION_COUNT: string = 'activeConnectionCount';

@Observed
export class AppStore {
  controllerUrl: string = DEFAULT_CONTROLLER_URL;
  secret: string = '';
  autoConnect: boolean = false;
  darkMode: boolean = false;
  connectionStatus: ConnectionStatus = '未连接';
  activeConnectionCount: number = 0;
  errorMessage: string = '';

  private static instance: AppStore = new AppStore();

  constructor() {
    this.syncAppStorage();
  }

  static getInstance(): AppStore {
    return AppStore.instance;
  }

  async loadConfig(): Promise<AppConfig> {
    // MVP keeps configuration in memory. TODO: persist with Preferences once SDK setup is confirmed.
    return this.toConfig();
  }

  async saveConfig(): Promise<AppConfig> {
    // MVP keeps configuration in memory. TODO: persist with Preferences once SDK setup is confirmed.
    this.errorMessage = '';
    this.syncAppStorage();
    return this.toConfig();
  }

  updateControllerUrl(controllerUrl: string): void {
    const nextControllerUrl: string = controllerUrl.trim();
    if (this.controllerUrl === nextControllerUrl) {
      this.errorMessage = '';
      this.syncAppStorage();
      return;
    }
    this.controllerUrl = nextControllerUrl;
    this.connectionStatus = '未连接';
    this.errorMessage = '';
    this.syncAppStorage();
  }

  updateSecret(secret: string): void {
    const nextSecret: string = secret.trim();
    if (this.secret === nextSecret) {
      this.errorMessage = '';
      this.syncAppStorage();
      return;
    }
    this.secret = nextSecret;
    this.connectionStatus = '未连接';
    this.errorMessage = '';
    this.syncAppStorage();
  }

  async testConnection(): Promise<boolean> {
    this.errorMessage = '';
    try {
      const api = this.createApi();
      const ok = await api.testConnection();
      this.connectionStatus = ok ? '控制器可用' : '连接失败';
      this.syncAppStorage();
      return ok;
    } catch (error) {
      this.connectionStatus = '连接失败';
      this.errorMessage = toErrorMessage(error);
      this.syncAppStorage();
      return false;
    }
  }

  createApi(): MihomoApi {
    return new MihomoApi(this.controllerUrl, this.secret);
  }

  updateActiveConnectionCount(count: number): void {
    this.activeConnectionCount = count < 0 ? 0 : count;
    this.syncAppStorage();
  }

  toConfig(): AppConfig {
    return {
      controllerUrl: this.controllerUrl,
      secret: this.secret,
      autoConnect: this.autoConnect,
      darkMode: this.darkMode
    };
  }

  private syncAppStorage(): void {
    AppStorage.SetOrCreate<string>(STORAGE_CONTROLLER_URL, this.controllerUrl);
    AppStorage.SetOrCreate<string>(STORAGE_SECRET, this.secret);
    AppStorage.SetOrCreate<string>(STORAGE_CONNECTION_STATUS, this.connectionStatus);
    AppStorage.SetOrCreate<string>(STORAGE_ERROR_MESSAGE, this.errorMessage);
    AppStorage.SetOrCreate<number>(STORAGE_ACTIVE_CONNECTION_COUNT, this.activeConnectionCount);
  }
}
