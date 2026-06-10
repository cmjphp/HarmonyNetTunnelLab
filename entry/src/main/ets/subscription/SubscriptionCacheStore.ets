import common from '@ohos.app.ability.common';
import preferences from '@ohos.data.preferences';
import { CachedSubscription } from '../model/SubscriptionModel';

const SUBSCRIPTION_PREF_NAME: string = 'vpn_poc_subscription_cache';
const KEY_URL: string = 'url';
const KEY_CONTENT: string = 'content';
const KEY_FORMAT: string = 'format';
const KEY_NODE_COUNT: string = 'nodeCount';
const KEY_UPDATED_AT: string = 'updatedAt';

export class SubscriptionCacheStore {
  static async save(context: common.Context, cache: CachedSubscription): Promise<void> {
    const store = await preferences.getPreferences(context, SUBSCRIPTION_PREF_NAME);
    await store.put(KEY_URL, cache.url);
    await store.put(KEY_CONTENT, cache.content);
    await store.put(KEY_FORMAT, cache.format);
    await store.put(KEY_NODE_COUNT, cache.nodeCount);
    await store.put(KEY_UPDATED_AT, cache.updatedAt);
    await store.flush();
  }

  static async load(context: common.Context): Promise<CachedSubscription | undefined> {
    const store = await preferences.getPreferences(context, SUBSCRIPTION_PREF_NAME);
    const content = await SubscriptionCacheStore.readString(store, KEY_CONTENT);
    if (content.length === 0) {
      return undefined;
    }
    return {
      url: await SubscriptionCacheStore.readString(store, KEY_URL),
      content: content,
      format: await SubscriptionCacheStore.readString(store, KEY_FORMAT),
      nodeCount: await SubscriptionCacheStore.readNumber(store, KEY_NODE_COUNT),
      updatedAt: await SubscriptionCacheStore.readString(store, KEY_UPDATED_AT)
    };
  }

  static nowText(): string {
    const now = new Date();
    const year = now.getFullYear();
    const month = SubscriptionCacheStore.pad(now.getMonth() + 1);
    const day = SubscriptionCacheStore.pad(now.getDate());
    const hour = SubscriptionCacheStore.pad(now.getHours());
    const minute = SubscriptionCacheStore.pad(now.getMinutes());
    const second = SubscriptionCacheStore.pad(now.getSeconds());
    return `${year}-${month}-${day} ${hour}:${minute}:${second}`;
  }

  private static async readString(store: preferences.Preferences, key: string): Promise<string> {
    const value = await store.get(key, '');
    return typeof value === 'string' ? value : '';
  }

  private static async readNumber(store: preferences.Preferences, key: string): Promise<number> {
    const value = await store.get(key, 0);
    return typeof value === 'number' ? value : 0;
  }

  private static pad(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }
}
