import common from '@ohos.app.ability.common';
import preferences from '@ohos.data.preferences';
import { SubscriptionItem } from '../model/SubscriptionModel';

const PREF_NAME: string = 'subscription_manager';
const KEY_ITEMS: string = 'items';
const KEY_ACTIVE_ID: string = 'activeId';

export class SubscriptionManager {
  static async loadItems(context: common.Context): Promise<SubscriptionItem[]> {
    const store = await preferences.getPreferences(context, PREF_NAME);
    const itemsStr = await store.get(KEY_ITEMS, '[]');
    const items = typeof itemsStr === 'string' ? JSON.parse(itemsStr) as SubscriptionItem[] : [];
    return items;
  }

  static async saveItems(context: common.Context, items: SubscriptionItem[]): Promise<void> {
    const store = await preferences.getPreferences(context, PREF_NAME);
    await store.put(KEY_ITEMS, JSON.stringify(items));
    await store.flush();
  }

  static async getActiveId(context: common.Context): Promise<string> {
    const store = await preferences.getPreferences(context, PREF_NAME);
    const id = await store.get(KEY_ACTIVE_ID, '');
    return typeof id === 'string' ? id : '';
  }

  static async setActiveId(context: common.Context, id: string): Promise<void> {
    const store = await preferences.getPreferences(context, PREF_NAME);
    await store.put(KEY_ACTIVE_ID, id);
    await store.flush();
  }

  static async addItem(context: common.Context, item: SubscriptionItem): Promise<void> {
    const items = await SubscriptionManager.loadItems(context);
    items.push(item);
    await SubscriptionManager.saveItems(context, items);
    // Set as active if it's the first item
    if (items.length === 1) {
      await SubscriptionManager.setActiveId(context, item.id);
    }
  }

  static async updateItem(context: common.Context, id: string, updates: Partial<SubscriptionItem>): Promise<void> {
    const items = await SubscriptionManager.loadItems(context);
    const index = items.findIndex((item: SubscriptionItem) => item.id === id);
    if (index >= 0) {
      const item = items[index];
      if (updates.id !== undefined) item.id = updates.id;
      if (updates.name !== undefined) item.name = updates.name;
      if (updates.url !== undefined) item.url = updates.url;
      if (updates.content !== undefined) item.content = updates.content;
      if (updates.format !== undefined) item.format = updates.format;
      if (updates.nodeCount !== undefined) item.nodeCount = updates.nodeCount;
      if (updates.updatedAt !== undefined) item.updatedAt = updates.updatedAt;
      await SubscriptionManager.saveItems(context, items);
    }
  }

  static async removeItem(context: common.Context, id: string): Promise<void> {
    const items = await SubscriptionManager.loadItems(context);
    const newItems = items.filter((item: SubscriptionItem) => item.id !== id);
    await SubscriptionManager.saveItems(context, newItems);
    // If the active item was removed, set a new active item
    const activeId = await SubscriptionManager.getActiveId(context);
    if (activeId === id && newItems.length > 0) {
      await SubscriptionManager.setActiveId(context, newItems[0].id);
    } else if (newItems.length === 0) {
      await SubscriptionManager.setActiveId(context, '');
    }
  }

  static async getActiveItem(context: common.Context): Promise<SubscriptionItem | undefined> {
    const activeId = await SubscriptionManager.getActiveId(context);
    if (activeId.length === 0) {
      return undefined;
    }
    const items = await SubscriptionManager.loadItems(context);
    return items.find((item: SubscriptionItem) => item.id === activeId);
  }
}
