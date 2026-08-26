const GRAPH_ME_URL =
  "https://graph.microsoft.com/v1.0/me?$select=id,displayName,givenName,surname,mail,userPrincipalName,mobilePhone,businessPhones,jobTitle,department,officeLocation,streetAddress,city,state,postalCode,country";

// Un champ de formulaire par propriété vCard éditable. `graphField` est utilisé pour le
// pré-remplissage depuis Graph ; `key` est le nom envoyé à la Function (voir AddToWallet).
const FIELDS = [
  { key: "displayName", graphField: "displayName", label: "Nom complet" },
  { key: "givenName", graphField: "givenName", label: "Prénom" },
  { key: "surname", graphField: "surname", label: "Nom" },
  { key: "jobTitle", graphField: "jobTitle", label: "Poste" },
  { key: "department", graphField: "department", label: "Service" },
  { key: "officeLocation", graphField: "officeLocation", label: "Bureau" },
  { key: "email", graphField: "mail", label: "E-mail" },
  { key: "mobilePhone", graphField: "mobilePhone", label: "Mobile" },
  { key: "businessPhones", graphField: "businessPhones", label: "Téléphone(s) professionnel(s)", isList: true },
  { key: "streetAddress", graphField: "streetAddress", label: "Adresse" },
  { key: "city", graphField: "city", label: "Ville" },
  { key: "state", graphField: "state", label: "Région" },
  { key: "postalCode", graphField: "postalCode", label: "Code postal" },
  { key: "country", graphField: "country", label: "Pays" },
];

const els = {
  loginBtn: document.getElementById("login-btn"),
  logoutBtn: document.getElementById("logout-btn"),
  loginSection: document.getElementById("login-section"),
  formSection: document.getElementById("form-section"),
  form: document.getElementById("vcard-form"),
  submitBtn: document.getElementById("submit-btn"),
  status: document.getElementById("status"),
  whoami: document.getElementById("whoami"),
};

function setStatus(message, isError = false) {
  els.status.textContent = message || "";
  els.status.classList.toggle("error", isError);
}

function renderForm(profile) {
  els.form.innerHTML = "";
  for (const field of FIELDS) {
    const wrapper = document.createElement("label");
    wrapper.className = "field";

    const caption = document.createElement("span");
    caption.textContent = field.label;
    wrapper.appendChild(caption);

    const input = document.createElement("input");
    input.type = "text";
    input.name = field.key;
    input.autocomplete = "off";

    let value = profile[field.graphField];
    if (field.isList) {
      value = Array.isArray(value) ? value.join(", ") : "";
    }
    // Repli e-mail : si `mail` est vide côté annuaire, on propose l'UPN par défaut,
    // exactement comme le fait scripts/update-vcf.ps1.
    if (field.key === "email" && !value) {
      value = profile.userPrincipalName || "";
    }
    input.value = value || "";

    wrapper.appendChild(input);
    els.form.appendChild(wrapper);
  }
}

function collectFormValues() {
  const values = {};
  for (const field of FIELDS) {
    const input = els.form.elements[field.key];
    let value = input.value.trim();
    if (field.isList) {
      value = value
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean);
    }
    values[field.key] = value;
  }
  return values;
}

async function handleLogin() {
  setStatus("Connexion en cours…");
  try {
    await window.Auth.login();
    await loadProfile();
  } catch (err) {
    setStatus("Échec de la connexion : " + err.message, true);
  }
}

function handleLogout() {
  window.Auth.logout();
  els.loginSection.hidden = false;
  els.formSection.hidden = true;
  setStatus("");
}

async function loadProfile() {
  setStatus("Chargement de votre profil…");
  const token = await window.Auth.getGraphToken();
  const response = await fetch(GRAPH_ME_URL, {
    headers: { Authorization: "Bearer " + token },
  });
  if (!response.ok) {
    throw new Error("Impossible de lire votre profil Microsoft Graph (" + response.status + ")");
  }
  const profile = await response.json();

  els.whoami.textContent = profile.displayName || profile.userPrincipalName || "";
  renderForm(profile);
  els.loginSection.hidden = true;
  els.formSection.hidden = false;
  setStatus("");
}

async function handleSubmit(event) {
  event.preventDefault();
  els.submitBtn.disabled = true;
  setStatus("Génération du pass en cours…");
  try {
    const token = await window.Auth.getGraphToken();
    const fields = collectFormValues();

    const response = await fetch(window.APP_CONFIG.functionBaseUrl + "/AddToWallet", {
      method: "POST",
      headers: {
        Authorization: "Bearer " + token,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(fields),
    });

    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.error || "La génération du pass a échoué (" + response.status + ")");
    }

    const { walletUrl } = await response.json();
    setStatus("Pass généré, ouverture du wallet…");
    window.location.href = walletUrl;
  } catch (err) {
    setStatus("Erreur : " + err.message, true);
  } finally {
    els.submitBtn.disabled = false;
  }
}

async function main() {
  els.loginBtn.addEventListener("click", handleLogin);
  els.logoutBtn.addEventListener("click", handleLogout);
  els.form.addEventListener("submit", handleSubmit);

  const account = await window.Auth.init();
  if (account) {
    await loadProfile();
  }
}

main();
