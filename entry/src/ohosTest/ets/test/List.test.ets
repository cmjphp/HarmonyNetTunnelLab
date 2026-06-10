import mihomoApiTest from './MihomoApi.test';
import appStoreTest from './AppStore.test';

export default function testsuite() {
  mihomoApiTest();
  appStoreTest();
}
