declare module 'libvpn_core.so' {
  export function startCore(): number;
  export function stopCore(): number;
  export function setTunFd(fd: number): number;
  export function setConfig(configText: string): number;
  export function getStats(): string;

  const vpnCore: {
    startCore(): number;
    stopCore(): number;
    setTunFd(fd: number): number;
    setConfig(configText: string): number;
    getStats(): string;
  };
  export default vpnCore;
}
