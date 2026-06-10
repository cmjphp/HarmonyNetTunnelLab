import { describe, it, expect } from '@ohos/hypium';
import { AppStore } from '../../../main/ets/store/AppStore';

export default function appStoreTest() {
  describe('AppStore', () => {
    it('updates controllerUrl', () => {
      const store = new AppStore();
      store.updateControllerUrl('http://192.168.1.1:9090');
      expect(store.controllerUrl).assertEqual('http://192.168.1.1:9090');
    });

    it('updates secret', () => {
      const store = new AppStore();
      store.updateSecret('token');
      expect(store.secret).assertEqual('token');
    });

    it('sets errorMessage when testConnection fails', async () => {
      const store = new AppStore();
      store.updateControllerUrl('');
      await store.testConnection();
      expect(store.errorMessage.length > 0).assertTrue();
      expect(store.connectionStatus).assertEqual('连接失败');
    });
  });
}
