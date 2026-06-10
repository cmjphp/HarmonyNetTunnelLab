import { AppColors, CARD_RADIUS, PAGE_PADDING } from '../common/Constants';

@Component
export struct ProfilesPage {
  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text('配置')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
          .width('100%')

        Column({ space: 10 }) {
          Text('配置管理')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.textPrimary)
            .width('100%')
          Text('第一版先保留占位。后续支持订阅链接、配置文件导入和配置切换。')
            .fontSize(14)
            .fontColor(AppColors.textSecondary)
            .width('100%')
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
  }
}
