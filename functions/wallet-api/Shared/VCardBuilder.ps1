# Port de New-VCardFromUser (scripts/update-vcf.ps1) : même structure de lignes, même
# échappement vCard 3.0, même constante ORG="MAGORA". Contrairement au script batch, les
# valeurs proviennent ici directement des champs soumis par l'utilisateur (potentiellement
# corrigés par rapport à l'annuaire), pas d'un objet Graph brut.

function ConvertTo-VCardValue([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return "" }
  $s = $s -replace "\\", "\\\\"
  $s = $s -replace ";", "\;"
  $s = $s -replace ",", "\,"
  $s = $s -replace "`r`n", "\\n"
  $s = $s -replace "`n", "\\n"
  $s = $s -replace "`r", "\\n"
  return $s
}

function New-VCardFromFields {
  param(
    [Parameter(Mandatory)] [string]$Id,          # id Graph immuable, jamais fourni par le client
    [Parameter(Mandatory)] [hashtable]$Fields     # champs soumis par le client (voir app/app.js FIELDS)
  )

  $crlf = "`r`n"

  $fn = ConvertTo-VCardValue($Fields.displayName)
  $given = ConvertTo-VCardValue($Fields.givenName)
  $surname = ConvertTo-VCardValue($Fields.surname)
  if ([string]::IsNullOrWhiteSpace($fn)) { $fn = ($given + " " + $surname).Trim() }

  $jobTitle = ConvertTo-VCardValue($Fields.jobTitle)
  $dept = ConvertTo-VCardValue($Fields.department)
  $company = "MAGORA"
  $office = ConvertTo-VCardValue($Fields.officeLocation)

  $email = ConvertTo-VCardValue($Fields.email)
  $mobile = ConvertTo-VCardValue($Fields.mobilePhone)

  $bizPhones = @()
  if ($Fields.businessPhones) {
    $bizPhones = $Fields.businessPhones | ForEach-Object { ConvertTo-VCardValue($_) }
  }

  $street = ConvertTo-VCardValue($Fields.streetAddress)
  $city = ConvertTo-VCardValue($Fields.city)
  $state = ConvertTo-VCardValue($Fields.state)
  $zip = ConvertTo-VCardValue($Fields.postalCode)
  $country = ConvertTo-VCardValue($Fields.country)

  $uid = ConvertTo-VCardValue($Id)

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("BEGIN:VCARD")
  $lines.Add("VERSION:3.0")
  $lines.Add("PRODID:-//Magora//VCF Self-Service//FR")
  if ($uid) { $lines.Add("UID:$uid") }
  if ($fn) { $lines.Add("FN:$fn") }
  $lines.Add("N:$surname;$given;;;")

  $org = "$company;$dept".Trim(";")
  if ($org) { $lines.Add("ORG:$org") }

  if ($jobTitle) { $lines.Add("TITLE:$jobTitle") }
  if ($office) { $lines.Add("X-OFFICE:$office") }

  if ($email) { $lines.Add("EMAIL;TYPE=INTERNET,WORK:$email") }
  if ($mobile) { $lines.Add("TEL;TYPE=CELL:$mobile") }
  foreach ($bp in $bizPhones) {
    if ($bp) { $lines.Add("TEL;TYPE=WORK,VOICE:$bp") }
  }

  if ($street -or $city -or $state -or $zip -or $country) {
    $lines.Add("ADR;TYPE=WORK:;;$street;$city;$state;$zip;$country")
  }

  $lines.Add("END:VCARD")

  return ($lines -join $crlf) + $crlf
}
