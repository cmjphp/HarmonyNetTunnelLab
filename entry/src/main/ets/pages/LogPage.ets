import router from '@ohos.router';
import { CoreDiagnostic } from '../core/CoreDiagnostic';
import { CoreStatsStore } from '../core/CoreStatsStore';
import { AppLogger } from '../logger/AppLogger';

@Entry
@Component
struct LogPage {
  @State logs: string[] = [];
  @State nativeCoreStats: string = '未启动';
  @State nativeCoreDiagnosis: string = '尚未收到 native core 状态';
  private refreshTimer: number = -1;

  aboutToAppear(): void {
    AppLogger.init(getContext(this));
    this.refreshLogs();
    this.loadNativeCoreStats();
    this.refreshTimer = setInterval(() => {
      this.refreshLogs();
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.refreshTimer !== -1) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
    }
  }

  private async refreshLogs(): Promise<void> {
    this.logs = await AppLogger.readLogs();
  }

  private async loadNativeCoreStats(): Promise<void> {
    try {
      this.nativeCoreStats = await CoreStatsStore.load(getContext(this));
      this.nativeCoreDiagnosis = CoreDiagnostic.summarize(this.nativeCoreStats);
    } catch (_) {
      this.nativeCoreStats = '暂无 Core 状态';
      this.nativeCoreDiagnosis = CoreDiagnostic.summarize(this.nativeCoreStats);
    }
  }

  private async refreshNativeCoreStats(): Promise<void> {
    try {
      this.nativeCoreStats = `${await CoreStatsStore.load(getContext(this))}; uiReadAt=${this.nowText()}`;
      this.nativeCoreDiagnosis = CoreDiagnostic.summarize(this.nativeCoreStats);
    } catch (error) {
      this.nativeCoreStats = `读取失败: ${AppLogger.formatError(error)}`;
    } finally {
      await this.refreshLogs();
    }
  }

  private async clearLogs(): Promise<void> {
    await AppLogger.clear();
    this.logs = [];
  }

  private async loadMihomoLog(): Promise<void> {
    try {
      const fileIo = await import('@ohos.file.fs');
      const context = getContext(this);
      const logPath = `${context.filesDir}/mihomo_runtime.yaml.log`;
      const content = fileIo.default.readTextSync(logPath);
      await AppLogger.info(`--- MIHOMO LOG ---\n${content}\n--- END MIHOMO LOG ---`);
    } catch (e) {
      await AppLogger.error('无法读取 Mihomo 日志文件: ' + JSON.stringify(e));
    }
  }

  private nowText(): string {
    const now = new Date();
    return `${this.pad(now.getHours())}:${this.pad(now.getMinutes())}:${this.pad(now.getSeconds())}`;
  }

  private pad(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
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
    Column({ space: 8 }) {
      // Header
      Row() {
        Text('< 返回')
          .fontSize(13)
          .fontColor('#3B82F6')
          .onClick(() => {
            router.back();
          })
        Blank()
        Text('运行日志')
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
        Blank()
        Button('清空')
          .height(24)
          .fontSize(10)
          .type(ButtonType.Normal)
        .borderRadius(6)
          .onClick(() => {
            this.clearLogs();
          })
      }
      .width('100%')

      // Native Core status
      Column({ space: 6 }) {
        Row() {
          Text('Adapter / Core 状态')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor('#111827')
          Blank()
          Button('刷新')
            .height(22)
            .fontSize(10)
            .type(ButtonType.Normal)
        .borderRadius(6)
            .onClick(() => {
              this.refreshNativeCoreStats();
            })
        }
        .width('100%')

        Text(this.nativeCoreStats)
          .fontSize(10)
          .fontColor('#6B7280')
          .width('100%')

        Text(this.nativeCoreDiagnosis)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.nativeCoreDiagnosisColor())
          .width('100%')
          .padding(6)
          .backgroundColor('#F8FAFC')
          .borderRadius(6)
      }
      .width('100%')
      .padding(8)
      .backgroundColor('#FFFFFF')
      .borderRadius(8)

      // Mihomo log button
      Button('读取 Core 运行日志')
        .height(24)
        .fontSize(10)
        .type(ButtonType.Normal)
        .borderRadius(6)
        .width('100%')
        .onClick(() => {
          this.loadMihomoLog();
        })

      // Log list
      List({ space: 2 }) {
        ForEach(this.logs, (log: string) => {
          ListItem() {
            Text(log)
              .fontSize(10)
              .fontColor('#6B7280')
              .width('100%')
          }
        }, (log: string) => log)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .padding(12)
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7FA')
  }
}
