// Valeurs NON secrètes uniquement (visibles par tout le monde côté navigateur).
// Aucun secret (clé API Pass2U, client secret) ne doit jamais figurer ici.
window.APP_CONFIG = {
  // App Registration Entra ID dédiée au SPA (déléguée, User.Read seul, PKCE, pas de secret).
  // À remplacer par le clientId réel une fois l'App Registration créée.
  msalClientId: "REPLACE-WITH-SPA-APP-CLIENT-ID",

  // Même tenant que le batch nocturne, mais App Registration distincte.
  tenantId: "d0ae6336-5c35-4735-9703-03fb777bbd2b",

  // Doit correspondre EXACTEMENT au Redirect URI configuré dans l'App Registration.
  redirectUri: window.location.origin + window.location.pathname,

  // URL de base de l'Azure Function (à renseigner une fois la Function déployée).
  functionBaseUrl: "https://REPLACE-WITH-FUNCTION-APP.azurewebsites.net/api",
};
