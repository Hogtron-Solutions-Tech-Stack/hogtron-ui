<#
.SYNOPSIS
  Link the HogTron UI addon folders into a WoW client's Interface\AddOns via directory junctions.
.EXAMPLE
  .\dev\link.ps1 -Client anniversary          # link into _anniversary_
  .\dev\link.ps1 -Client all                  # anniversary + era
  .\dev\link.ps1 -Client forever              # WoW: Forever LIVE (_forever_, product wowf); not part of "all"
  .\dev\link.ps1 -Client beta                 # WoW: Forever beta (_classic_beta_); not part of "all"
  .\dev\link.ps1 -Client forever -Repo C:\Users\me\Code\hogtron-ui   # from a worktree: link the main clone, not the worktree
  .\dev\link.ps1 -Client anniversary -Remove  # unlink
.NOTES
  Junctions need no admin, but writing under "Program Files (x86)" may prompt UAC once.
  Remove = delete the junctions; the repo is untouched.
  -Repo = which checkout the junctions point at (default: the one this script lives in). Pass the clone the game should
  load when running the script from a worktree, or every junction silently serves that worktree's branch.
#>
param(
  [ValidateSet("anniversary", "era", "retail", "forever", "beta", "all")] [string] $Client = "anniversary",
  [switch] $Remove,
  [string] $WowRoot = "C:\Program Files (x86)\World of Warcraft",
  [string] $Repo = (Split-Path -Parent $PSScriptRoot)
)

$repo = (Resolve-Path $Repo).Path
if (-not (Test-Path (Join-Path $repo "HogTronUI\HogTronUI.toc"))) { throw "Not a HogTron UI checkout: $repo" }
$addons = @("HogTronUI", "HogHeals", "HogHeals_Frames", "HogTron_Atlas", "HogTron_Bars", "HogTron_Chat", "HogTron_HUD", "HogTron_Meter", "HogTron_Plates", "HogTron_Quests", "HogTron_Skin", "HogTron_Training", "HogTron_Units", "HogTron_Awards", "HogTron_Journal")
$map = @{ anniversary = "_anniversary_"; era = "_classic_era_"; retail = "_retail_"; forever = "_forever_"; beta = "_classic_beta_" }
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
