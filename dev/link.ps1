<#
.SYNOPSIS
  Link the HogHeals addon folders into a WoW client's Interface\AddOns via directory junctions.
.EXAMPLE
  .\dev\link.ps1 -Client anniversary          # link into _anniversary_
  .\dev\link.ps1 -Client all                  # anniversary + era
  .\dev\link.ps1 -Client anniversary -Remove  # unlink
.NOTES
  Junctions need no admin, but writing under "Program Files (x86)" may prompt UAC once.
  Remove = delete two junctions; the repo is untouched.
#>
param(
  [ValidateSet("anniversary", "era", "retail", "all")] [string] $Client = "anniversary",
  [switch] $Remove,
  [string] $WowRoot = "C:\Program Files (x86)\World of Warcraft"
)

$repo = Split-Path -Parent $PSScriptRoot
$addons = @("HogHeals", "HogHeals_Frames", "HogHeals_HUD")
$map = @{ anniversary = "_anniversary_"; era = "_classic_era_"; retail = "_retail_" }
$targets = if ($Client -eq "all") { @("anniversary", "era") } else { @($Client) }

foreach ($t in $targets) {
  $dir = Join-Path $WowRoot "$($map[$t])\Interface\AddOns"
  if (-not (Test-Path $dir)) { Write-Warning "Missing: $dir"; continue }
  foreach ($a in $addons) {
    $link = Join-Path $dir $a
    $src = Join-Path $repo $a
    if ($Remove) {
      if (Test-Path $link) { (Get-Item $link).Delete(); Write-Host "removed $link" } else { Write-Host "absent  $link" }
      continue
    }
    if (Test-Path $link) {
      $item = Get-Item $link
      if ($item.LinkType -eq "Junction") { Write-Host "exists  $link -> $($item.Target)"; continue }
      Write-Warning "$link exists and is NOT a junction (a real folder). Move it aside first."; continue
    }
    New-Item -ItemType Junction -Path $link -Target $src | Out-Null
    Write-Host "linked  $link -> $src"
  }
}
Write-Host "`nIn game: /reload, then /hh (options), /hh test 10 (preview), /hh unlock (move), /hh errors."
