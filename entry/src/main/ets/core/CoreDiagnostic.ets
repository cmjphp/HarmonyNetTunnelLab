export class CoreDiagnostic {
  static summarize(stats: string): string {
    if (stats.length === 0 || stats.indexOf('暂无 Core 状态') >= 0) {
      return '尚未收到 native core 状态';
    }

    if (stats.indexOf('phase=onCreate') >= 0) {
      return 'VpnExtensionAbility 已进入 onCreate，正在创建 VpnConnection';
    }

    if (stats.indexOf('phase=createVpnConnectionFail') >= 0 || stats.indexOf('phase=createVpnFail') >= 0) {
      return 'VpnConnection 创建失败，请看 error= 后面的系统错误';
    }

    if (stats.indexOf('phase=createVpnSuccess') >= 0) {
      return 'VPN/TUN 已创建，正在启动 native core';
    }

    if (stats.indexOf('adapterKind=stub') >= 0 || stats.indexOf('startError=-100') >= 0) {
      return '当前 HAP 内仍是占位 adapter，不会产生真实代理流量';
    }

    if (stats.indexOf('dlopen libmihomo_adapter.so failed') >= 0 || stats.indexOf('mihomoAdapterLoaded=false') >= 0) {
      if (stats.indexOf('initial-exec TLS') >= 0) {
        return '当前 GOOS=linux Go adapter 与真机动态加载/TLS 模型不兼容，需要 OHOS-capable Go 工具链或调整 adapter 形态';
      }
      return '未加载到 libmihomo_adapter.so，请确认真实 adapter 已打进 HAP';
    }

    if (stats.indexOf('phase=loadNativeBridge') >= 0) {
      return '已创建 VPN，正在加载 native NAPI；若长时间停在这里，请查看运行日志里的 nativeStartException';
    }

    if (stats.indexOf('phase=nativeStartException') >= 0) {
      if (stats.indexOf('native module not loaded') >= 0 || stats.indexOf('symbol is not a function') >= 0) {
        return 'libvpn_core.so NAPI 符号未注册：VpnExtensionAbility 进程中 native module 未加载，请确认 HAP 正确打包了 libvpn_core.so 并重新安装';
      }
      return 'native core 启动异常，错误已写入 Core 状态，请看 error= 后面的具体原因';
    }

    if (stats.indexOf('missing required C ABI symbols') >= 0) {
      return 'adapter ABI 不完整，请确认导出 5 个 Mihomo* C 符号';
    }

    if (stats.indexOf('mihomoRunning=true') >= 0 || stats.indexOf('started=true') >= 0 || stats.indexOf('running=true') >= 0) {
      return 'native core 显示已运行，下一步检查 mihomo 内部日志和外网连通性';
    }

    if (stats.indexOf('mihomo config path is empty') >= 0 || stats.indexOf('configPath=') < 0) {
      return 'mihomo 运行配置路径为空，请先读取订阅并生成 Core 配置';
    }

    if (stats.indexOf('MihomoStart failed') >= 0 || stats.indexOf('mihomo adapter start failed') >= 0) {
      return '真实 adapter 已进入启动流程但返回失败，请查看 MihomoGetStats 的 adapter 内部错误';
    }

    return '已收到 native core 状态，请结合 lastError 和 mihomoStats 判断';
  }
}
