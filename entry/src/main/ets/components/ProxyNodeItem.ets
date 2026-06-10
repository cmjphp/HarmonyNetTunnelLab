import { AppColors } from '../common/Constants';

@Component
export struct ProxyNodeItem {
  @Prop name: string = '';
  @Prop selected: boolean = false;
  onSelect: (name: string) => void = () => {};

  build() {
    Row() {
      Text(this.name)
        .fontSize(14)
        .fontColor(this.selected ? AppColors.primary : AppColors.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Blank()
      if (this.selected) {
        Text('当前端点')
          .fontSize(12)
          .fontColor(AppColors.primary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor(AppColors.primarySoft)
          .borderRadius(12)
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .onClick(() => {
      this.onSelect(this.name);
    })
  }
}
