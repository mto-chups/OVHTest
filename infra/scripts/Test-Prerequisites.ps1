$ErrorActionPreference = "Stop"

$terraform = if (Get-Command terraform -ErrorAction SilentlyContinue) {
  "terraform"
} else {
  Join-Path $PSScriptRoot "..\..\.tools\terraform-1.17.1\terraform.exe"
}

if (-not (Test-Path $terraform) -and $terraform -ne "terraform") {
  throw "Terraform 1.17.1 est introuvable."
}

& $terraform version

$helm = if (Get-Command helm -ErrorAction SilentlyContinue) {
  "helm"
} else {
  Join-Path $PSScriptRoot "..\..\.tools\helm-v3.22.1\windows-amd64\helm.exe"
}
if (-not (Test-Path $helm) -and $helm -ne "helm") {
  throw "Helm 3.22.1 est introuvable."
}

& $helm version --short
kubectl version --client

Write-Host "Vérifiez maintenant les quotas, flavors, versions DB, plans Registry et la compatibilité vRack GRA11/GRA dans le Manager OVHcloud."
