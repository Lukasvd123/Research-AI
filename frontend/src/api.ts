// Auth model:
//   Production — entrypoint.sh authenticates server-side, runtime-config.js
//                contains only tokens (never credentials). The browser can
//                refresh tokens via the refresh_token grant (no credentials needed).
//   Dev        — VITE_AUTH_USER/PASS from env, client_credentials in the browser.
//                This is fine since dev is localhost only.

import axios, { AxiosError } from 'axios';

// Runtime config (injected in production) or Vite env (dev)
const cfg = (window as any).__RUNTIME_CONFIG__ || {};
const baseURL = cfg.VITE_API_URL || import.meta.env.VITE_API_URL || "http://localhost:8000";

// Production: pre-fetched tokens from runtime-config (credentials stayed in container)
// Dev: credentials from Vite env (localhost only)
const authUser = import.meta.env.VITE_AUTH_USER || "";
const authPass = import.meta.env.VITE_AUTH_PASS || "";

const api = axios.create({ baseURL });

let accessToken: string | null = cfg.VITE_AUTH_TOKEN || null;
let refreshToken: string | null = cfg.VITE_REFRESH_TOKEN || null;
let authenticating: Promise<void> | null = null;
let _authError: string | null = null;

const hasAuth = !!accessToken || (!!authUser && !!authPass);

/** Current auth error message, or null if auth is OK / not configured. */
export function getAuthError(): string | null {
  return _authError;
}

/** Dev only: authenticate with client_credentials. */
async function authenticate(): Promise<void> {
  if (!authUser || !authPass) return;

  _authError = null;
  try {
    const resp = await axios.post(`${baseURL}/auth/token`, {
      grant_type: "client_credentials",
      username: authUser,
      password: authPass,
    });
    accessToken = resp.data.access_token;
    refreshToken = resp.data.refresh_token;
  } catch (err) {
    accessToken = null;
    refreshToken = null;
    const axErr = err as AxiosError<{ error?: string; error_description?: string }>;
    if (axErr.response) {
      const { status, data } = axErr.response;
      if (status === 401) {
        _authError = `Auth failed: invalid credentials (${data?.error_description || "bad username or password"})`;
      } else if (status === 429) {
        _authError = `Auth failed: rate limited — too many attempts`;
      } else {
        _authError = `Auth failed: server returned ${status}`;
      }
    } else if (axErr.request) {
      _authError = `Auth failed: cannot reach ${baseURL}/auth/token`;
    } else {
      _authError = `Auth failed: ${axErr.message}`;
    }
    throw err;
  }
}

/** Refresh using refresh_token grant (works without credentials). */
async function refreshAuth(): Promise<void> {
  if (refreshToken) {
    try {
      const resp = await axios.post(`${baseURL}/auth/token`, {
        grant_type: "refresh_token",
        refresh_token: refreshToken,
      });
      accessToken = resp.data.access_token;
      refreshToken = resp.data.refresh_token;
      _authError = null;
      return;
    } catch {
      // Refresh failed — fall through
    }
  }

  // Dev: re-authenticate with credentials
  if (authUser && authPass) {
    return authenticate();
  }

  // Production: refresh failed and no credentials available
  _authError = "Session expired — please reload the page";
  accessToken = null;
  refreshToken = null;
}

// Attach Bearer token to every request
api.interceptors.request.use(async (config) => {
  if (!hasAuth) return config; // No auth configured

  if (!accessToken) {
    if (!authenticating) {
      authenticating = authenticate().finally(() => { authenticating = null; });
    }
    await authenticating;
  }

  if (accessToken) {
    config.headers.Authorization = `Bearer ${accessToken}`;
  }
  return config;
});

// Retry once on 401
api.interceptors.response.use(
  (response) => response,
  async (error) => {
    const original = error.config;
    if (error.response?.status === 401 && !original._retried && hasAuth) {
      original._retried = true;
      await refreshAuth();
      if (accessToken) {
        original.headers.Authorization = `Bearer ${accessToken}`;
      }
      return api(original);
    }
    return Promise.reject(error);
  }
);

export default api;
