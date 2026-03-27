// Character theme definitions — port of CharacterTheme.swift

export interface BlinkSequence {
  open: string;
  half: string;
  closed: string;
  /** open -> half -> closed -> half -> open */
  frames: string[];
}

export interface IdleImageConfig {
  baseImage: string;   // half-closed eyes (shown most of the time)
  closedImage: string; // fully closed eyes (for drowsy blink)
}

export interface BreathingConfig {
  inhaleImage: string;
  exhaleImage: string;
}

export interface CharacterTheme {
  blinkSequence: BlinkSequence;
  idleImages: IdleImageConfig;
  asleepBreathing: BreathingConfig;
  waveFrames: string[];
  availableImage: string;
}

function owlTheme(suffix: string): CharacterTheme {
  const s = suffix;
  const open = `/resources/owl_active_open${s}.png`;
  const half = `/resources/owl_active_half${s}.png`;
  const closed = `/resources/owl_active_closed${s}.png`;

  return {
    blinkSequence: {
      open,
      half,
      closed,
      frames: [open, half, closed, half, open],
    },
    idleImages: {
      baseImage: half,
      closedImage: closed,
    },
    asleepBreathing: {
      inhaleImage: `/resources/owl_asleep_in${s}.png`,
      exhaleImage: `/resources/owl_asleep_out${s}.png`,
    },
    waveFrames: [
      open,
      `/resources/owl_wave_low${s}.png`,
      `/resources/owl_wave_med${s}.png`,
      `/resources/owl_wave_high${s}.png`,
      `/resources/owl_wave_med${s}.png`,
      `/resources/owl_wave_low${s}.png`,
      open,
    ],
    availableImage: open,
  };
}

export const themes: Record<string, CharacterTheme> = {
  owl1: owlTheme(''),
  owl2: owlTheme('2'),
};

export function getTheme(characterType: string): CharacterTheme {
  return themes[characterType] ?? themes.owl1;
}
