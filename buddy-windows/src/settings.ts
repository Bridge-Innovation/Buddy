// Settings persistence via @tauri-apps/plugin-store — mirrors AppSettings.swift

import { load, type Store } from '@tauri-apps/plugin-store';
import type { CallLink } from './types';
import { parseCallLinks } from './types';

const STORE_FILE = 'buddy-settings.json';

// Keys matching the macOS UserDefaults keys
const Keys = {
  userId: 'BuddyUserId',
  friendCode: 'BuddyFriendCode',
  displayName: 'BuddyDisplayName',
  facetimeContact: 'BuddyFacetimeContact',
  owlSize: 'BuddyOwlSize',
  characterType: 'BuddyCharacterType',
  isAvailableToCowork: 'BuddyIsAvailableToCowork',
  windowPositionX: 'BuddyWindowPositionX',
  windowPositionY: 'BuddyWindowPositionY',
} as const;

export class Settings {
  private store: Store | null = null;

  async init() {
    this.store = await load(STORE_FILE, {
      defaults: {},
      autoSave: true,
      overrideDefaults: true,
    });
  }

  // -- Getters with defaults --

  async getUserId(): Promise<string | null> {
    return await this.store?.get<string>(Keys.userId) ?? null;
  }

  async getFriendCode(): Promise<string | null> {
    return await this.store?.get<string>(Keys.friendCode) ?? null;
  }

  async getDisplayName(): Promise<string> {
    return await this.store?.get<string>(Keys.displayName) ?? '';
  }

  async getFacetimeContact(): Promise<string> {
    return await this.store?.get<string>(Keys.facetimeContact) ?? '';
  }

  async getOwlSize(): Promise<number> {
    return await this.store?.get<number>(Keys.owlSize) ?? 1;
  }

  async getCharacterType(): Promise<string> {
    return await this.store?.get<string>(Keys.characterType) ?? 'owl1';
  }

  async getIsAvailableToCowork(): Promise<boolean> {
    return await this.store?.get<boolean>(Keys.isAvailableToCowork) ?? false;
  }

  async getWindowPosition(): Promise<{ x: number; y: number } | null> {
    const x = await this.store?.get<number>(Keys.windowPositionX);
    const y = await this.store?.get<number>(Keys.windowPositionY);
    if (x != null && y != null) return { x, y };
    return null;
  }

  // -- Setters --

  async setUserId(value: string) {
    await this.store?.set(Keys.userId, value);
  }

  async setFriendCode(value: string) {
    await this.store?.set(Keys.friendCode, value);
  }

  async setDisplayName(value: string) {
    await this.store?.set(Keys.displayName, value);
  }

  async setFacetimeContact(value: string) {
    await this.store?.set(Keys.facetimeContact, value);
  }

  async setOwlSize(value: number) {
    await this.store?.set(Keys.owlSize, value);
  }

  async setCharacterType(value: string) {
    await this.store?.set(Keys.characterType, value);
  }

  async setIsAvailableToCowork(value: boolean) {
    await this.store?.set(Keys.isAvailableToCowork, value);
  }

  async setWindowPosition(x: number, y: number) {
    await this.store?.set(Keys.windowPositionX, x);
    await this.store?.set(Keys.windowPositionY, y);
  }

  // -- Call links helpers --

  async getCallLinks(): Promise<CallLink[]> {
    const raw = await this.getFacetimeContact();
    return parseCallLinks(raw);
  }

  async setCallLinks(links: CallLink[]) {
    await this.setFacetimeContact(JSON.stringify(links));
  }

  // -- Owl scale helper matching macOS --

  owlScale(size: number): number {
    switch (size) {
      case 0: return 0.75;
      case 2: return 1.35;
      default: return 1.0;
    }
  }
}
