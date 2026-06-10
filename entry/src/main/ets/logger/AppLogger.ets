import common from '@ohos.app.ability.common';
import preferences from '@ohos.data.preferences';
import hilog from '@ohos.hilog';

export const LOG_STORAGE_KEY: string = 'vpnPocLogs';

const LOG_PREF_NAME: string = 'vpn_poc_logs';
const LOG_PREF_KEY: string = 'entries';
const MAX_LOG_COUNT: number = 200;
const HILOG_DOMAIN: number = 0x0001;
const HILOG_TAG: string = 'HarmonyVpnPoc';

export class AppLogger {
  private static context?: common.Context;

  static init(context: common.Context): void {
    AppLogger.context = context;
    AppStorage.SetOrCreate<string[]>(LOG_STORAGE_KEY, []);
  }

  static async info(message: string): Promise<void> {
    hilog.info(HILOG_DOMAIN, HILOG_TAG, '%{public}s', message);
    await AppLogger.append(message);
  }

  static async error(message: string): Promise<void> {
    hilog.error(HILOG_DOMAIN, HILOG_TAG, '%{public}s', message);
    await AppLogger.append(message);
  }

  static async clear(): Promise<void> {
    if (AppLogger.context !== undefined) {
      const store = await preferences.getPreferences(AppLogger.context, LOG_PREF_NAME);
      await store.put(LOG_PREF_KEY, '');
      await store.flush();
    }
    AppStorage.SetOrCreate<string[]>(LOG_STORAGE_KEY, []);
  }

  static async readLogs(): Promise<string[]> {
    if (AppLogger.context === undefined) {
      return AppStorage.Get<string[]>(LOG_STORAGE_KEY) ?? [];
    }
    try {
      const store = await preferences.getPreferences(AppLogger.context, LOG_PREF_NAME);
      const value = await store.get(LOG_PREF_KEY, '');
      const text = typeof value === 'string' ? value : '';
      const logs = AppLogger.decode(text);
      AppStorage.SetOrCreate<string[]>(LOG_STORAGE_KEY, logs);
      return logs;
    } catch (error) {
      const fallback = AppStorage.Get<string[]>(LOG_STORAGE_KEY) ?? [];
      fallback.push(AppLogger.decorate(`read logs fail: ${AppLogger.formatError(error)}`));
      return fallback;
    }
  }

  static formatError(error: Object): string {
    if (error instanceof Error) {
      return `${error.name}: ${error.message}`;
    }
    try {
      return JSON.stringify(error);
    } catch (_) {
      return `${error}`;
    }
  }

  private static async append(message: string): Promise<void> {
    const line = AppLogger.decorate(message);
    const current = await AppLogger.readLogs();
    current.push(line);
    const trimmed = current.slice(Math.max(0, current.length - MAX_LOG_COUNT));
    AppStorage.SetOrCreate<string[]>(LOG_STORAGE_KEY, trimmed);

    if (AppLogger.context !== undefined) {
      const store = await preferences.getPreferences(AppLogger.context, LOG_PREF_NAME);
      await store.put(LOG_PREF_KEY, AppLogger.encode(trimmed));
      await store.flush();
    }
  }

  private static decorate(message: string): string {
    return `${AppLogger.nowText()} ${message}`;
  }

  private static nowText(): string {
    const now = new Date();
    const hour = AppLogger.pad(now.getHours());
    const minute = AppLogger.pad(now.getMinutes());
    const second = AppLogger.pad(now.getSeconds());
    return `[${hour}:${minute}:${second}]`;
  }

  private static pad(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  private static encode(logs: string[]): string {
    return logs.join('\n');
  }

  private static decode(text: string): string[] {
    if (text.length === 0) {
      return [];
    }
    return text.split('\n').filter((item: string) => item.length > 0);
  }
}
