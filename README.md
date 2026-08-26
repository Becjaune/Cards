# Cards

Génération de vCards et de passes Wallet (Apple/Google via Pass2U) pour les collaborateurs.

Deux parcours coexistent :

## 1. Batch nocturne (existant)

`scripts/Global.ps1` orchestre :
- `scripts/update-vcf.ps1` — génère un `.vcf` par UPN listé dans `upns.txt`, via Microsoft Graph en **app-only** (certificat).
- `scripts/New-QRCode.ps1` — génère un QR code par `.vcf`.
- `scripts/Generate-CSV-Pass2U.ps1` — génère `contacts/pass2u.csv` pour un import batch dans Pass2U.

Déclenché chaque nuit par `.github/workflows/generate-vcf-qr.yml` (ou manuellement via `workflow_dispatch`). Les fichiers sont publiés statiquement par GitHub Pages. Ce flux reste le filet de sécurité pour les personnes sans SSO ou en cas de panne du parcours self-service ci-dessous.

Secrets utilisés : `GRAPH_CERT_PFX_B64`, `GRAPH_CERT_PFX_PASSWORD`, `GRAPH_TENANT_ID`, `GRAPH_CLIENT_ID` (App Registration Entra ID **app-only**, dédiée à ce batch).

## 2. Self-service (nouveau)

Chaque collaborateur peut générer et corriger sa propre vCard, et l'ajouter directement à son wallet mobile, sans attendre le batch :

1. **`app/`** (page statique, servie par GitHub Pages) : connexion Entra ID (MSAL.js, App Registration **SPA** distincte, permission déléguée `User.Read` uniquement), lecture de son propre profil via `GET /me`, formulaire pré-rempli mais **éditable** (corrige les données AD erronées), bouton unique "Ajouter à mon Wallet".
2. **`functions/wallet-api/`** (Azure Function, PowerShell) :
   - `AddToWallet` (POST) — valide l'appelant en relayant son token vers Graph `/me` (jamais de validation JWT maison), construit la vCard à partir des champs soumis par l'utilisateur, l'enregistre dans Azure Table Storage (clé = id Graph immuable, écrase le snapshot précédent — les corrections sont "à usage unique", non fusionnées avec l'annuaire), puis appelle l'API Pass2U pour générer le pass.
   - `GetVCard` (GET `/api/vcard/{id}`, public) — sert le dernier snapshot vCard généré ; c'est l'URL vers laquelle pointe le QR code embarqué dans le pass Wallet.

Secrets utilisés (Application Settings de la Function App, jamais dans ce repo) : `PASS2U_API_KEY`, `PASS2U_TEMPLATE_ID`. Déploiement automatisé via `.github/workflows/deploy-wallet-function.yml` (login Azure par OIDC : secrets GitHub `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_FUNCTIONAPP_NAME`).

Deux App Registrations Entra ID distinctes et cloisonnées (moindre privilège) : l'app-only du batch nocturne reste inchangée ; l'App SPA du self-service n'a que la permission déléguée `User.Read`, sans secret (PKCE).

**À configurer avant mise en service** (non fourni dans ce repo, dépend de l'organisation) :
- `app/config.js` : `clientId` de l'App Registration SPA et URL de la Function déployée.
- Dashboard Pass2U : template de pass + clé API.
- `functions/wallet-api/Shared/Pass2U.ps1` : implémenter l'appel réel une fois le contrat d'API confirmé sur https://www.pass2u.net/documentation (volontairement laissé en squelette pour ne pas committer une intégration non vérifiée).
