import common from '@ohos.app.ability.common';
import fileIo from '@ohos.file.fs';
import preferences from '@ohos.data.preferences';

const VPN_STATUS_PREF_NAME: string = 'vpn_poc_status';
const KEY_STATUS: string = 'status';

export class VpnStatusText {
  static readonly STOPPED: string = '未启动';
  static readonly STARTING: string = '启动中';
  static readonly STARTED: string = '已启动';
  static readonly TUN_CREATED: string = 'VPN已创建';
  static readonly CORE_FAILED: string = 'VPN已创建/Core失败';
  static readonly FAILED: string = '启动失败';
}

export class VpnStatusStore {
  // Use a file for cross-process status sharing.
  // VpnExtensionAbility runs in a separate process; preferences instances are
  // cached per-process and do NOT automatically reflect writes from another
  // process.  A plain file under filesDir is visible to all processes in the
  // same HAP (same as CoreStatsStore / vpn_core_stats.txt).
  private static statusFilePath(context: common.Context): string {
    return `${context.filesDir}/vpn_status.txt`;
  }

  static async save(context: common.Context, status: string): Promise<void> {
    // 1. Write to file (cross-process readable)
    try {
      const path = VpnStatusStore.statusFilePath(context);
      const file = fileIo.openSync(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, status);
      } finally {
        fileIo.closeSync(file);
      }
    } catch (_) {
    }
    // 2. Also write to AppStorage for same-process observers
    AppStorage.SetOrCreate<string>('vpnStatus', status);
    // 3. Persist to preferences as fallback
    try {
      const store = await preferences.getPreferences(context, VPN_STATUS_PREF_NAME);
      await store.put(KEY_STATUS, status);
      await store.flush();
    } catch (_) {
    }
  }

  static async load(context: common.Context): Promise<string> {
    // Try file first (always fresh, cross-process safe)
    try {
      const path = VpnStatusStore.statusFilePath(context);
      const content = fileIo.readTextSync(path);
      if (content && content.length > 0) {
        AppStorage.SetOrCreate<string>('vpnStatus', content);
        return content;
      }
    } catch (_) {
    }
    // Fall back to preferences
    try {
      const store = await preferences.getPreferences(context, VPN_STATUS_PREF_NAME);
      const value = await store.get(KEY_STATUS, VpnStatusText.STOPPED);
      const status = typeof value === 'string' ? value : VpnStatusText.STOPPED;
      AppStorage.SetOrCreate<string>('vpnStatus', status);
      return status;
    } catch (_) {
    }
    return VpnStatusText.STOPPED;
  }
}
