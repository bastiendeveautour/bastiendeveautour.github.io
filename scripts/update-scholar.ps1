param(
  [string]$IndexPath = (Join-Path $PSScriptRoot '..\index.html'),
  [string]$ScholarUrl = 'https://scholar.google.fr/citations?user=icHa2g0AAAAJ&hl=fr&oi=ao&pagesize=100'
)

$ErrorActionPreference = 'Stop'

function Clean-Html {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return ''
  }

  $cleaned = $Value -replace '<span class="gs_oph">,?\s*(.*?)</span>', ''
  $cleaned = $cleaned -replace '<.*?>', ''
  return [System.Net.WebUtility]::HtmlDecode($cleaned).Trim()
}

function Escape-Html {
  param([string]$Value)

  return [System.Net.WebUtility]::HtmlEncode($Value)
}

$resolvedIndexPath = Resolve-Path $IndexPath
$response = Invoke-WebRequest -Uri $ScholarUrl -UseBasicParsing -Headers @{
  'User-Agent' = 'Mozilla/5.0'
}
$html = $response.Content

$metricValues = [regex]::Matches($html, '<td class="gsc_rsb_std">(.*?)</td>') |
  ForEach-Object { Clean-Html $_.Groups[1].Value }

if ($metricValues.Count -lt 3) {
  throw 'Could not find Google Scholar citation metrics.'
}

$hIndex = [int]$metricValues[2]
$publicationRows = [regex]::Matches($html, '<tr class="gsc_a_tr">.*?</tr>')

if ($publicationRows.Count -eq 0) {
  throw 'Could not find Google Scholar publication rows.'
}

$cards = foreach ($match in $publicationRows) {
  $row = $match.Value
  $title = Clean-Html ([regex]::Match($row, '<a [^>]*class="gsc_a_at"[^>]*>(.*?)</a>').Groups[1].Value)
  $grayRows = [regex]::Matches($row, '<div class="gs_gray">(.*?)</div>')
  $authors = if ($grayRows.Count -gt 0) { Clean-Html $grayRows[0].Groups[1].Value } else { '' }
  $venue = if ($grayRows.Count -gt 1) { Clean-Html $grayRows[1].Groups[1].Value } else { '' }
  $cites = Clean-Html ([regex]::Match($row, 'class="gsc_a_ac[^>]*>(.*?)</a>').Groups[1].Value)
  $year = Clean-Html ([regex]::Match($row, '<span class="gsc_a_h gsc_a_hc gs_ibl">(.*?)</span>').Groups[1].Value)

  if ([string]::IsNullOrWhiteSpace($cites)) {
    $cites = '0'
  }

  $meta = "$(Escape-Html $authors) &middot; $(Escape-Html $venue)"
  if (-not [string]::IsNullOrWhiteSpace($year)) {
    $meta = "$meta &middot; $(Escape-Html $year)"
  }

@"
              <div class="rpg-spell-card">
                <div class="spell-title">$(Escape-Html $title)</div>
                <div class="spell-meta">$meta</div>
                <span class="spell-type-badge">CITES $(Escape-Html $cites)</span>
              </div>
"@
}

$snapshotDate = (Get-Date).ToString('yyyy-MM-dd')
$spellList = @"
            <div class="rpg-spell-list">
              <!-- Scholar snapshot: Bastien Deveautour, updated $snapshotDate. -->
$($cards -join "`r`n")            </div>
"@

$indexHtml = [System.IO.File]::ReadAllText($resolvedIndexPath, [System.Text.Encoding]::UTF8)

$indexHtml = [regex]::Replace(
  $indexHtml,
  '(<span class="stat-label"[^>]*>PUB</span>\s*<span style="font-family:var\(--font-rpg-title\); font-size:1rem; color:var\(--rpg-text\);">)\d+(</span>)',
  "`${1}$($publicationRows.Count)`$2",
  1
)

$indexHtml = [regex]::Replace(
  $indexHtml,
  '(<span class="stat-label"[^>]*>H-IDX</span>\s*<span style="font-family:var\(--font-rpg-title\); font-size:1rem; color:var\(--rpg-text\);">)\d+(</span>)',
  "`${1}$($hIndex.ToString('00'))`$2",
  1
)

$indexHtml = [regex]::Replace(
  $indexHtml,
  '(?s)<div class="rpg-spell-list">.*?</div>\s*</section>',
  "$spellList`r`n          </section>",
  1
)

[System.IO.File]::WriteAllText($resolvedIndexPath, $indexHtml, [System.Text.Encoding]::UTF8)

Write-Host "Updated $resolvedIndexPath"
Write-Host "PUB: $($publicationRows.Count)"
Write-Host "H-IDX: $($hIndex.ToString('00'))"
