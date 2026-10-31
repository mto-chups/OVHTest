param(
  [Parameter(Mandatory = $true)][string]$Lot,
  [Parameter(Mandatory = $true)][string]$EstimationMensuelle
)

Write-Host "Lot : $Lot"
Write-Host "Estimation mensuelle issue du Manager : $EstimationMensuelle"
$confirmation = Read-Host "Saisissez APPROUVE pour autoriser l'apply payant"
if ($confirmation -cne "APPROUVE") {
  throw "Apply annulé : coût non approuvé."
}
Write-Host "Coût approuvé. Vous pouvez appliquer le plan relu de ce lot."
