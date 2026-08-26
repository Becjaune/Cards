// Wrapper léger autour de @azure/msal-browser (chargé en UMD via <script> dans index.html).
// Flow : Authorization Code + PKCE (comportement par défaut de msal-browser v3), scope User.Read uniquement.

const GRAPH_SCOPES = ["User.Read"];

const msalConfig = {
  auth: {
    clientId: window.APP_CONFIG.msalClientId,
    authority: `https://login.microsoftonline.com/${window.APP_CONFIG.tenantId}`,
    redirectUri: window.APP_CONFIG.redirectUri,
  },
  cache: {
    cacheLocation: "sessionStorage",
    storeAuthStateInCookie: false,
  },
};

const msalInstance = new msal.PublicClientApplication(msalConfig);

window.Auth = {
  account: null,

  async init() {
    await msalInstance.initialize();
    const response = await msalInstance.handleRedirectPromise();
    if (response && response.account) {
      this.account = response.account;
    } else {
      const accounts = msalInstance.getAllAccounts();
      if (accounts.length > 0) this.account = accounts[0];
    }
    return this.account;
  },

  async login() {
    const response = await msalInstance.loginPopup({ scopes: GRAPH_SCOPES });
    this.account = response.account;
    return this.account;
  },

  logout() {
    msalInstance.logoutPopup({ account: this.account });
    this.account = null;
  },

  // Retourne un access token Graph valide, en silencieux si possible, sinon via popup.
  async getGraphToken() {
    if (!this.account) throw new Error("Utilisateur non connecté.");
    const request = { scopes: GRAPH_SCOPES, account: this.account };
    try {
      const result = await msalInstance.acquireTokenSilent(request);
      return result.accessToken;
    } catch (err) {
      const result = await msalInstance.acquireTokenPopup(request);
      return result.accessToken;
    }
  },
};
