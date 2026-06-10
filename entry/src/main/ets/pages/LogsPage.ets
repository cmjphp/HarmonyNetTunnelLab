import { AppColors, CARD_RADIUS, PAGE_PADDING } from '../common/Constants';

@Component
export struct LogsPage {
  @State logText: string = '尚未加载运行日志';

  async loadLogs() {
    try {
      const fileIo = await import('@ohos.file.fs');
      const context = getContext(this);
      const logPath = `${context.filesDir}/mihomo_runtime.yaml.log`;
      const content = fileIo.default.readTextSync(logPath);
      this.logText = content || '运行日志为空';
    } catch (e) {
      this.logText = '加载运行日志失败: ' + JSON.stringify(e);
    }
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text('底层运行日志 (Core)')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
          .width('100%')

        Button('刷新运行日志')
          .onClick(() => {
            this.loadLogs();
          })

        Column({ space: 10 }) {
          Text(this.logText)
            .fontSize(12)
            .fontColor(AppColors.textSecondary)
            .width('100%')
            .copyOption(CopyOptions.LocalDevice)
        }
        .width('100%')
        .padding(18)
        .backgroundColor(AppColors.surface)
        .borderRadius(CARD_RADIUS)
        .border({ width: 1, color: AppColors.border })
      }
      .padding(PAGE_PADDING)
    }
    .backgroundColor(AppColors.background)
    .width('100%')
    .height('100%')
    .onAppear(() => {
      this.loadLogs();
    })
  }
}
