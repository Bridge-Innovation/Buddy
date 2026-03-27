// Idle detection via Tauri command — mirrors ActivityMonitor.swift

import { invoke } from '@tauri-apps/api/core';
import type { BuddyState } from './types';
import { BuddyEvents } from './types';

const IDLE_THRESHOLD = 120;   // 2 minutes → idle
const ASLEEP_THRESHOLD = 600; // 10 minutes → asleep
const POLL_INTERVAL = 10_000; // 10 seconds
const DEBOUNCE_DELAY = 5_000; // 5 seconds

export class IdleMonitor extends EventTarget {
  private _state: BuddyState = 'active';
  private _isAvailableToCowork = false;
  private _characterType = 'owl';
  private pollTimer: ReturnType<typeof setInterval> | null = null;
  private debounceTimer: ReturnType<typeof setTimeout> | null = null;

  get state() { return this._state; }

  get isAvailableToCowork() { return this._isAvailableToCowork; }
  set isAvailableToCowork(value: boolean) { this._isAvailableToCowork = value; }

  get characterType() { return this._characterType; }
  set characterType(value: string) { this._characterType = value; }

  start() {
    this.poll();
    this.pollTimer = setInterval(() => this.poll(), POLL_INTERVAL);
  }

  stop() {
    if (this.pollTimer) { clearInterval(this.pollTimer); this.pollTimer = null; }
    if (this.debounceTimer) { clearTimeout(this.debounceTimer); this.debounceTimer = null; }
  }

  private async poll() {
    let idleSeconds: number;
    try {
      idleSeconds = await invoke<number>('get_idle_seconds');
    } catch {
      return; // command not available (e.g. dev mode without Tauri)
    }

    const newState = this.classifyState(idleSeconds);

    if (newState === this._state) {
      // State unchanged — cancel any pending debounce
      if (this.debounceTimer) {
        clearTimeout(this.debounceTimer);
        this.debounceTimer = null;
      }
      return;
    }

    // State changed — debounce before confirming
    if (this.debounceTimer) return; // already waiting

    this.debounceTimer = setTimeout(async () => {
      this.debounceTimer = null;
      // Re-check after debounce
      let confirmedIdle: number;
      try {
        confirmedIdle = await invoke<number>('get_idle_seconds');
      } catch {
        return;
      }
      const confirmedState = this.classifyState(confirmedIdle);
      if (confirmedState !== this._state) {
        const oldState = this._state;
        this._state = confirmedState;
        this.dispatchEvent(new CustomEvent(BuddyEvents.STATE_CHANGED, {
          detail: { oldState, newState: confirmedState },
        }));
      }
    }, DEBOUNCE_DELAY);
  }

  private classifyState(idleSeconds: number): BuddyState {
    if (idleSeconds >= ASLEEP_THRESHOLD) return 'asleep';
    if (idleSeconds >= IDLE_THRESHOLD) return 'idle';
    return 'active';
  }
}
