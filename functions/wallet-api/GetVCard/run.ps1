using namespace System.Net

param($Request, $TriggerMetadata, $vCardEntity)

if (-not $vCardEntity -or -not $vCardEntity.Content) {
  Push-OutputBinding -Name Response -InputObject ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::NotFound
    Body       = "Aucune vCard générée pour cet identifiant."
  })
  return
}

Push-OutputBinding -Name Response -InputObject ([HttpResponseContext]@{
  StatusCode = [HttpStatusCode]::OK
  Headers    = @{ "Content-Type" = "text/vcard; charset=utf-8" }
  Body       = $vCardEntity.Content
})
