# Point d'entrée du worker PowerShell pour Azure Functions (exécuté au cold start).
# Rien à initialiser ici : Table Storage passe par les bindings natifs (AzureWebJobsStorage)
# et Graph/Pass2U par Invoke-RestMethod, sans dépendance au module Az.
