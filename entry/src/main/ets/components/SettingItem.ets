import { AppColors } from '../common/Constants';

@Component
export struct SettingItem {
  @Prop title: string = '';
  @Prop value: string = '';

  build() {
    Row() {
      Text(this.title)
        .fontSize(15)
        .fontColor(AppColors.textPrimary)
      Blank()
      Text(this.value)
        .fontSize(14)
        .fontColor(AppColors.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }
}
