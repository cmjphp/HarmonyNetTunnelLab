import { AppColors, CARD_RADIUS, PAGE_PADDING } from '../common/Constants';
import { formatChains } from '../common/Utils';
import { AppStore } from '../store/AppStore';
import { MihomoConnection } from '../model/ConnectionModel';
import { EmptyView } from '../components/EmptyView';
import { ErrorView } from '../components/ErrorView';

@Component
export struct ConnectionsPage {
  @State store: AppStore = AppStore.getInstance();
  @State connections: MihomoConnection[] = [];
  @State loading: boolean = false;
  @State closing: boolean = false;
  @State errorMessage: string = '';
  @State resultMessage: string = '';

  async loadConnections(): Promise<void> {
    this.loading = true;
    this.errorMessage = '';
    this.resultMessage = '';
    try {
      const response = await this.store.createApi().getConnections();
      this.connections = response.connections;
      this.store.updateActiveConnectionCount(this.connections.length);
    } catch (error) {
      this.errorMessage = error instanceof Error ? error.message : String(error);
    }
    this.loading = false;
  }

  async closeAll(): Promise<void> {
    this.closing = true;
    this.errorMessage = '';
    this.resultMessage = '';
    try {
      await this.store.createApi().closeAllConnections();
      await this.loadConnections();
      this.store.updateActiveConnectionCount(0);
      this.resultMessage = '已关闭全部连接';
    } catch (error) {
      this.errorMessage = error instanceof Error ? error.message : String(error);
    }
    this.closing = false;
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Row() {
          Column({ space: 4 }) {
            Text('连接')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary)
            Text(`当前连接数：${this.connections.length}`)
              .fontSize(14)
              .fontColor(AppColors.textSecondary)
          }
          .alignItems(HorizontalAlign.Start)
          Blank()
          Button('刷新')
            .height(40)
            .enabled(!this.loading)
            .onClick(() => {
              this.loadConnections();
            })
        }
        .width('100%')

        Button(this.closing ? '关闭中' : '关闭全部连接')
          .height(42)
          .width('100%')
          .backgroundColor(AppColors.danger)
          .enabled(!this.closing && !this.loading)
          .onClick(() => {
            this.closeAll();
          })

        if (this.resultMessage.length > 0) {
          Text(this.resultMessage)
            .fontSize(14)
            .fontColor(AppColors.success)
            .width('100%')
        }

        if (this.errorMessage.length > 0) {
          ErrorView({ message: this.errorMessage })
        }

        if (!this.loading && this.connections.length === 0 && this.errorMessage.length === 0) {
          EmptyView({ message: '暂无连接，点击刷新获取 /connections 数据' })
        }

        ForEach(this.connections, (connection: MihomoConnection) => {
          Column({ space: 8 }) {
            Text(connection.metadata.host ? connection.metadata.host : connection.metadata.destinationIP ? connection.metadata.destinationIP : connection.id)
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.textPrimary)
              .width('100%')
              .maxLines(2)
            Text(`network：${connection.metadata.network ? connection.metadata.network : '未知'}`)
              .fontSize(13)
              .fontColor(AppColors.textSecondary)
              .width('100%')
            Text(`rule：${connection.rule}`)
              .fontSize(13)
              .fontColor(AppColors.textSecondary)
              .width('100%')
            Text(`rulePayload：${connection.rulePayload}`)
              .fontSize(13)
              .fontColor(AppColors.textSecondary)
              .width('100%')
            Text(`chains：${formatChains(connection.chains)}`)
              .fontSize(13)
              .fontColor(AppColors.textSecondary)
              .width('100%')
              .maxLines(2)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(AppColors.surface)
          .borderRadius(CARD_RADIUS)
          .border({ width: 1, color: AppColors.border })
        }, (connection: MihomoConnection) => connection.id)
      }
      .padding(PAGE_PADDING)
    }
    .backgroundColor(AppColors.background)
    .width('100%')
    .height('100%')
  }
}
