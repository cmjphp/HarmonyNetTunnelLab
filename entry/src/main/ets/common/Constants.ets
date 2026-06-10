export const APP_NAME: string = 'HarmonyNetTunnelLab';
export const DEFAULT_CONTROLLER_URL: string = 'http://192.168.1.15:9090';

export interface ColorPalette {
  background: string;
  surface: string;
  primary: string;
  primarySoft: string;
  textPrimary: string;
  textSecondary: string;
  border: string;
  danger: string;
  success: string;
}

export const AppColors: ColorPalette = {
  background: '#F7F8FA',
  surface: '#FFFFFF',
  primary: '#0A7AFF',
  primarySoft: '#E8F2FF',
  textPrimary: '#18202A',
  textSecondary: '#647084',
  border: '#E3E7EE',
  danger: '#D94841',
  success: '#1E9E63'
};

export const CARD_RADIUS: number = 18;
export const PAGE_PADDING: number = 16;
