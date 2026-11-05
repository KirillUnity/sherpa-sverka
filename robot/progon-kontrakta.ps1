# Stand-in for Sherpa Assistant: follows robot/sverka.process without Designer block names.
param(
    [string]$Papka = $(if ($env:Papka) { $env:Papka } else { Join-Path $PSScriptRoot '..\Papka' })
)

$ErrorActionPreference = 'Stop'
$Papka = [System.IO.Path]::GetFullPath($Papka)
$vigruzkaPath = Join-Path $Papka 'vigruzka.csv'
$otchetPath = Join-Path $Papka 'otchet.csv'
$oshibkaPath = Join-Path $Papka 'oshibka.txt'
$rashPath = Join-Path $Papka 'rashozhdeniya.csv'

function Write-Oshibka([string]$text) {
    [System.IO.File]::WriteAllText($oshibkaPath, $text, [System.Text.UTF8Encoding]::new($false))
}

function Format-Summa([decimal]$n) {
    if ($n -eq [decimal]::Truncate($n)) {
        return ([decimal]::Truncate($n)).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
    return $n.ToString([System.Globalization.CultureInfo]::InvariantCulture).TrimEnd('0').TrimEnd('.')
}

function Read-Table([string]$path) {
    $lines = [System.IO.File]::ReadAllLines($path, [System.Text.UTF8Encoding]::new($false))
    if ($lines.Count -lt 1) {
        throw "empty csv: $path"
    }
    $header = $lines[0].Trim() -split ','
    $idxNomer = [array]::IndexOf($header, 'nomer')
    $idxSumma = [array]::IndexOf($header, 'summa')
    $idxStatus = [array]::IndexOf($header, 'status')
    $byNomer = [ordered]@{}
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()
        if ($line -eq '') { continue }
        $cols = $line -split ',', -1
        $nomer = $cols[$idxNomer].Trim()
        $status = $cols[$idxStatus].Trim()
        $summa = [decimal]::Parse($cols[$idxSumma].Trim(), [System.Globalization.CultureInfo]::InvariantCulture)
        if ($byNomer.Contains($nomer)) {
            return @{ Duplicate = $true }
        }
        $byNomer[$nomer] = @{ nomer = $nomer; summa = $summa; status = $status }
    }
    return @{ Duplicate = $false; Rows = $byNomer }
}

if (-not (Test-Path -LiteralPath $vigruzkaPath) -or -not (Test-Path -LiteralPath $otchetPath)) {
    Write-Oshibka 'Не найден файл для сверки'
    exit 2
}

$vigruzka = Read-Table $vigruzkaPath
$otchet = Read-Table $otchetPath
if ($vigruzka.Duplicate -or $otchet.Duplicate) {
    Write-Oshibka 'Повторяется номер в одном файле'
    exit 3
}

$keys = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($k in $vigruzka.Rows.Keys) { [void]$keys.Add($k) }
foreach ($k in $otchet.Rows.Keys) { [void]$keys.Add($k) }

$groupDiff = New-Object System.Collections.Generic.List[object]
$groupOnlyV = New-Object System.Collections.Generic.List[object]
$groupOnlyO = New-Object System.Collections.Generic.List[object]

function New-Row($tip, $nomer, $sv, $so, $stv, $sto) {
    return [pscustomobject]@{
        tip             = $tip
        nomer           = $nomer
        summa_vigruzka  = $sv
        summa_otchet    = $so
        status_vigruzka = $stv
        status_otchet   = $sto
    }
}

foreach ($nomer in $keys) {
    $inV = $vigruzka.Rows.Contains($nomer)
    $inO = $otchet.Rows.Contains($nomer)
    if ($inV -and -not $inO) {
        $r = $vigruzka.Rows[$nomer]
        [void]$groupOnlyV.Add((New-Row 'net-v-otchete' $nomer (Format-Summa $r.summa) '' $r.status ''))
    }
    elseif ($inO -and -not $inV) {
        $r = $otchet.Rows[$nomer]
        [void]$groupOnlyO.Add((New-Row 'net-v-vigruzke' $nomer '' (Format-Summa $r.summa) '' $r.status))
    }
    else {
        $a = $vigruzka.Rows[$nomer]
        $b = $otchet.Rows[$nomer]
        if ($a.summa -ne $b.summa) {
            [void]$groupDiff.Add((New-Row 'summa' $nomer (Format-Summa $a.summa) (Format-Summa $b.summa) $a.status $b.status))
        }
        elseif ($a.status -ne $b.status) {
            [void]$groupDiff.Add((New-Row 'status' $nomer (Format-Summa $a.summa) (Format-Summa $b.summa) $a.status $b.status))
        }
    }
}

function Sort-ByNomer($items) {
    return @($items | Sort-Object { $_.nomer })
}
$groupDiff = Sort-ByNomer $groupDiff
$groupOnlyV = Sort-ByNomer $groupOnlyV
$groupOnlyO = Sort-ByNomer $groupOnlyO

$rows = @($groupDiff) + @($groupOnlyV) + @($groupOnlyO)
$nomerov = $keys.Count
$rashozhdeniy = $rows.Count

$out = New-Object System.Collections.Generic.List[string]
[void]$out.Add("nomerov,$nomerov")
[void]$out.Add("rashozhdeniy,$rashozhdeniy")
[void]$out.Add('tip,nomer,summa_vigruzka,summa_otchet,status_vigruzka,status_otchet')
foreach ($r in $rows) {
    [void]$out.Add("$($r.tip),$($r.nomer),$($r.summa_vigruzka),$($r.summa_otchet),$($r.status_vigruzka),$($r.status_otchet)")
}

$text = ($out -join "`r`n") + "`r`n"
[System.IO.File]::WriteAllText($rashPath, $text, [System.Text.UTF8Encoding]::new($false))
exit 0
