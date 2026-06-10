import { AppColors, CARD_RADIUS } from '../common/Constants';

@Component
export struct ErrorView {
  @Prop message: string = '';

  build() {
    Column({ space: 8 }) {
      Text('连接失败')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.danger)
      Text(this.message.length > 0 ? this.message : '请检查 controller 地址、secret 和网络可达性')
        .fontSize(14)
        .fontColor(AppColors.textSecondary)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor('#FFF2F2')
    .borderRadius(CARD_RADIUS)
  }
}
