import { AppColors } from '../common/Constants';

@Component
export struct EmptyView {
  @Prop message: string = '暂无数据';

  build() {
    Column() {
      Text(this.message)
        .fontSize(15)
        .fontColor(AppColors.textSecondary)
    }
    .width('100%')
    .padding(24)
    .alignItems(HorizontalAlign.Center)
  }
}
