#1. Générer VCF

.\update-vcf.ps1 `
  -TenantId "d0ae6336-5c35-4735-9703-03fb777bbd2b" `
  -ClientId "4203faaf-c609-4601-9645-71399763e2df" `
  -CertThumbprint "240910F19838E6CA4E2D74B7D428A4D7274D1AD7" `
  -UpnFile "C:\Repos\Cards\comex.txt" `
  -OutputDir "C:\Repos\Cards\contacts" `
  -IncludeFields "JobTitle" ,"Department","Company","Email","Mobile","FN", "N"

# Use inverse mode with explicit includes instead of excludes:
#-IncludeFields "FN","N","Email","Mobile","Address" `
# Accepted aliases include: Mail, UserPrincipalName, DisplayName, CompanyName, OfficeLocation, Phones

#2. Push git

git add .
git commit -m "Update VCF files $(Get-Date)"
git push