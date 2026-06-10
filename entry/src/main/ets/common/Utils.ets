export function isBlank(value: string): boolean {
  return value.trim().length === 0;
}

export function trimTrailingSlash(value: string): string {
  let result: string = value.trim();
  while (result.endsWith('/')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

export function formatChains(chains: string[]): string {
  if (chains.length === 0) {
    return '无';
  }
  return chains.join(' -> ');
}

export function toErrorMessage(error: Error | Object | string): string {
  if (typeof error === 'string') {
    return error;
  }
  if (error instanceof Error) {
    return error.message;
  }
  return JSON.stringify(error);
}
