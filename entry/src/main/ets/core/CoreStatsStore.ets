import common from '@ohos.app.ability.common';
import preferences from '@ohos.data.preferences';
import fileIo from '@ohos.file.fs';

const STATS_PREF_NAME: string = 'vpn_poc_core_stats';
const KEY_STATS: string = 'stats';
const KEY_UPDATED_AT: string = 'updatedAt';

export class CoreStatsStore {
  static statsFilePath(context: common.Context): string {
    return `${context.filesDir}/vpn_core_stats.txt`;
  }

  static async save(context: common.Context, stats: string): Promise<void> {
    const updatedAt = CoreStatsStore.nowText();
    const store = await preferences.getPreferences(context, STATS_PREF_NAME);
    await store.put(KEY_STATS, stats);
    await store.put(KEY_UPDATED_AT, updatedAt);
    await store.flush();
    try {
      const file = fileIo.openSync(
        CoreStatsStore.statsFilePath(context),
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
      );
      try {
        fileIo.writeSync(file.fd, `${stats}; updatedAt=${updatedAt}`);
      } finally {
        fileIo.closeSync(file);
      }
    } catch (_) {
    }
  }

  static async load(context: common.Context): Promise<string> {
    // Try to load from mihomo runtime stats file first
    const mihomoStatsPath = `${context.filesDir}/mihomo_runtime.yaml.stats`;
    try {
      const mihomoStats = await fileIo.readText(mihomoStatsPath);
      if (mihomoStats.trim().length > 0) {
        return mihomoStats.trim();
      }
    } catch (_) {
    }

    const fileStats = await CoreStatsStore.loadFromFile(context);
    if (fileStats.length > 0) {
      return fileStats;
    }

    const store = await preferences.getPreferences(context, STATS_PREF_NAME);
    const statsValue = await store.get(KEY_STATS, '');
    const updatedAtValue = await store.get(KEY_UPDATED_AT, '');
    const stats = typeof statsValue === 'string' ? statsValue : '';
    const updatedAt = typeof updatedAtValue === 'string' ? updatedAtValue : '';
    if (stats.length === 0) {
      return '暂无 Core 状态，请先启动网络扩展';
    }
    return updatedAt.length > 0 ? `${stats}; updatedAt=${updatedAt}` : stats;
  }

  static async clear(context: common.Context): Promise<void> {
    const store = await preferences.getPreferences(context, STATS_PREF_NAME);
    await store.put(KEY_STATS, '');
    await store.put(KEY_UPDATED_AT, '');
    await store.flush();
    try {
      fileIo.unlinkSync(CoreStatsStore.statsFilePath(context));
    } catch (_) {
    }
  }

  private static async loadFromFile(context: common.Context): Promise<string> {
    const path = CoreStatsStore.statsFilePath(context);
    try {
      const stats = await fileIo.readText(path);
      return stats.trim();
    } catch (_) {
      return '';
    }
  }

  private static nowText(): string {
    const now = new Date();
    const hour = CoreStatsStore.pad(now.getHours());
    const minute = CoreStatsStore.pad(now.getMinutes());
    const second = CoreStatsStore.pad(now.getSeconds());
    return `${hour}:${minute}:${second}`;
  }

  private static pad(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }
}
