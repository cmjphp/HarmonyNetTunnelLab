import { AppColors, CARD_RADIUS } from '../common/Constants';
import { ProxyGroup } from '../model/ProxyModel';
import { ProxyNodeItem } from './ProxyNodeItem';

@Component
export struct ProxyGroupCard {
  @Prop group: ProxyGroup = {
    name: '',
    type: '',
    now: '',
    all: []
  };
  onSelectProxy: (groupName: string, proxyName: string) => void = () => {};

  build() {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 4 }) {
          Text(this.group.name)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.textPrimary)
          Text(`${this.group.type} · 当前端点：${this.group.now}`)
            .fontSize(13)
            .fontColor(AppColors.textSecondary)
            .maxLines(2)
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
      }
      .width('100%')

      ForEach(this.group.all, (nodeName: string) => {
        ProxyNodeItem({
          name: nodeName,
          selected: nodeName === this.group.now,
          onSelect: (selectedName: string) => {
            this.onSelectProxy(this.group.name, selectedName);
          }
        })
      }, (nodeName: string) => `${this.group.name}-${nodeName}`)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(AppColors.surface)
    .borderRadius(CARD_RADIUS)
    .border({ width: 1, color: AppColors.border })
  }
}
