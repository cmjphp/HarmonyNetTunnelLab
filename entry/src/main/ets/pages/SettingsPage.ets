import { AppColors, CARD_RADIUS, PAGE_PADDING } from '../common/Constants';
import {
  AppStore,
  STORAGE_ACTIVE_CONNECTION_COUNT,
  STORAGE_CONNECTION_STATUS,
  STORAGE_CONTROLLER_URL,
  STORAGE_ERROR_MESSAGE,
  STORAGE_SECRET
} from '../store/AppStore';
import { ErrorView } from '../components/ErrorView';

@Component
export struct SettingsPage {
  @State store: AppStore = AppStore.getInstance();
  @StorageLink(STORAGE_CONTROLLER_URL) storedControllerUrl: string = AppStore.getInstance().controllerUrl;
  @StorageLink(STORAGE_SECRET) storedSecret: string = AppStore.getInstance().secret;
  @StorageLink(STORAGE_CONNECTION_STATUS) storedConnectionStatus: string = AppStore.getInstance().connectionStatus;
  @StorageLink(STORAGE_ERROR_MESSAGE) storedErrorMessage: string = '';
  @StorageLink(STORAGE_ACTIVE_CONNECTION_COUNT) activeConnectionCount: number = 0;
  @State controllerUrl: string = AppStore.getInstance().controllerUrl;
  @State secret: string = AppStore.getInstance().secret;
  @State testing: boolean = false;
  @State resultMessage: string = '';

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text('设置')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
          .width('100%')

        Column({ space: 14 }) {
          Text('mihomo external-controller')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.textPrimary)
            .width('100%')

          TextInput({ placeholder: 'http://192.168.1.1:9090', text: this.controllerUrl })
            .height(46)
            .backgroundColor('#F1F4F8')
            .borderRadius(12)
            .onChange((value: string) => {
              this.controllerUrl = value;
            })

          TextInput({ placeholder: 'secret 可为空', text: this.secret })
            .height(46)
            .backgroundColor('#F1F4F8')
            .borderRadius(12)
            .type(InputType.Password)
            .onChange((value: string) => {
              this.secret = value;
            })

          Row({ space: 12 }) {
            Button('保存')
              .height(42)
              .layoutWeight(1)
              .onClick(async () => {
                this.store.updateControllerUrl(this.controllerUrl);
                this.store.updateSecret(this.secret);
                await this.store.saveConfig();
                this.resultMessage = '已保存';
                this.controllerUrl = this.storedControllerUrl;
                this.secret = this.storedSecret;
              })

            Button(this.testing ? '测试中' : '测试连接')
              .height(42)
              .layoutWeight(1)
              .enabled(!this.testing)
              .onClick(async () => {
                this.testing = true;
                this.store.updateControllerUrl(this.controllerUrl);
                this.store.updateSecret(this.secret);
                const ok = await this.store.testConnection();
                this.resultMessage = ok ? '控制器可用' : '连接失败';
                this.controllerUrl = this.storedControllerUrl;
                this.secret = this.storedSecret;
                this.testing = false;
              })
          }
          .width('100%')

          if (this.resultMessage.length > 0) {
            Text(this.resultMessage)
              .fontSize(14)
              .fontColor(this.resultMessage === '控制器可用' || this.resultMessage === '已保存' ? AppColors.success : AppColors.danger)
              .width('100%')
          }

          Row() {
            Text('控制器状态')
              .fontSize(15)
              .fontColor(AppColors.textSecondary)
            Blank()
            Text(this.storedConnectionStatus)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.storedConnectionStatus === '控制器可用' ? AppColors.success : this.storedConnectionStatus === '连接失败' ? AppColors.danger : AppColors.textSecondary)
          }
          .width('100%')

          Row() {
            Text('活动连接')
              .fontSize(15)
              .fontColor(AppColors.textSecondary)
            Blank()
            Text(`${this.activeConnectionCount}`)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.activeConnectionCount > 0 ? AppColors.primary : AppColors.textSecondary)
          }
          .width('100%')

          if (this.storedErrorMessage.length > 0) {
            ErrorView({ message: this.storedErrorMessage })
          }
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
