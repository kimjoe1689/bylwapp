interface SecretBindings {
  BOOTSTRAP_ADMIN_USER?: string;
  BOOTSTRAP_ADMIN_PASSWORD?: string;
  TEST_MIGRATIONS?: Array<{ name: string; queries: string[] }>;
}

interface Env extends SecretBindings {}

declare namespace Cloudflare {
  interface Env extends SecretBindings {}
}
