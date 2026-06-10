import { AppColors, PAGE_PADDING } from '../common/Constants';
import { AppStore } from '../store/AppStore';
import { ProxyGroup, isProxyGroup } from '../model/ProxyModel';
import { EmptyView } from '../components/EmptyView';
import { ErrorView } from '../components/ErrorView';
import { ProxyGroupCard } from '../components/ProxyGroupCard';

@Component
export struct ProxiesPage {
  @State store: AppStore = AppStore.getInstance();
  @State groups: ProxyGroup[] = [];
  @State loading: boolean = false;
  @State errorMessage: string = '';

  async loadProxies(): Promise<void> {
    this.loading = true;
    this.errorMessage = '';
    try {
      const response = await this.store.createApi().getProxies();
      const result: ProxyGroup[] = [];
      Object.keys(response.proxies).forEach((name: string) => {
        const proxy = response.proxies[name];
        if (isProxyGroup(proxy)) {
          result.push(proxy as ProxyGroup);
        }
      });
      this.groups = result;
    } catch (error) {
      this.errorMessage = error instanceof Error ? error.message : String(error);
    }
    this.loading = false;
  }

  async selectProxy(groupName: string, proxyName: string): Promise<void> {
    this.errorMessage = '';
    try {
      await this.store.createApi().selectProxy(groupName, proxyName);
      await this.loadProxies();
    } catch (error) {
      this.errorMessage = error instanceof Error ? error.message : String(error);
    }
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Row() {
          Text('策略组')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.textPrimary)
          Blank()
          Button(this.loading ? '刷新中' : '刷新')
            .enabled(!this.loading)
            .height(40)
            .onClick(() => {
              this.loadProxies();
            })
        }
        .width('100%')

        if (this.errorMessage.length > 0) {
          ErrorView({ message: this.errorMessage })
        }

        if (!this.loading && this.groups.length === 0 && this.errorMessage.length === 0) {
          EmptyView({ message: '暂无策略组，点击刷新获取 /proxies 数据' })
        }

        ForEach(this.groups, (group: ProxyGroup) => {
          ProxyGroupCard({
            group: group,
            onSelectProxy: (groupName: string, proxyName: string) => {
              this.selectProxy(groupName, proxyName);
            }
          })
        }, (group: ProxyGroup) => group.name)
      }
      .padding(PAGE_PADDING)
    }
    .backgroundColor(AppColors.background)
    .width('100%')
    .height('100%')
  }
}
