# Builds robot/sverka.process from real Sherpa Designer toolbox items.
$ErrorActionPreference = 'Stop'
$libFs = 'E:\Sherpa RPA\Designer\Library\File System\FileManipulation.process'
$libEx = 'E:\Sherpa RPA\Designer\Library\Main Blocks\InvokeExpression.process'
$outProcess = Join-Path $PSScriptRoot 'sverka.process'
$papka = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\Papka'))

function Get-Block([xml]$doc, [string]$internal) {
    $item = $doc.Root.DesignerItems.DesignerItem | Where-Object { $_.Content -match ('InternalName="{0}"' -f [regex]::Escape($internal)) } | Select-Object -First 1
    if (-not $item) { throw "block not found: $internal" }
    return $item
}

function Set-Prop($item, [string]$name, [string]$value) {
    $c = $item.Content
    $pattern = '(Property Name="' + [regex]::Escape($name) + '"[\s\S]{0,1500}? Value=")' + '(.*?)' + '(" Visible)'
    $m = [regex]::Match($c, $pattern)
    if (-not $m.Success) { throw "property $name not found" }
    $item.Content = [regex]::Replace($c, $pattern, '${1}' + $value + '${3}', 1)
}

function New-Conn([xml]$doc, $src, $srcName, $sink, $sinkName, $z) {
    $c = $doc.CreateElement('Connection')
    foreach ($pair in @(
            @('SourceID', $src.ID),
            @('SinkID', $sink.ID),
            @('SourceConnectorName', $srcName),
            @('SinkConnectorName', $sinkName),
            @('SourceArrowSymbol', 'None'),
            @('SinkArrowSymbol', 'Arrow'),
            @('zIndex', "$z")
        )) {
        $e = $doc.CreateElement($pair[0])
        $e.InnerText = $pair[1]
        [void]$c.AppendChild($e)
    }
    [void]$script:conns.AppendChild($c)
}

$fs = New-Object xml
$fs.PreserveWhitespace = $false
$fs.Load($libFs)
$ex = New-Object xml
$ex.Load($libEx)

$start = Get-Block $fs 'Start'
$exist = Get-Block $fs 'DoesItemExist'
$write = Get-Block $fs 'FileWrite'
$stop = Get-Block $fs 'ReturnOrStop'
$invoke = Get-Block $ex 'InvokeExpression'

$doc = New-Object xml
$doc.AppendChild($doc.CreateXmlDeclaration('1.0', 'utf-8', $null)) | Out-Null
$root = $doc.CreateElement('Root')
[void]$doc.AppendChild($root)
$items = $doc.CreateElement('DesignerItems')
[void]$root.AppendChild($items)
$script:conns = $doc.CreateElement('Connections')
[void]$root.AppendChild($script:conns)
$props = $doc.CreateElement('Properties')
[void]$root.AppendChild($props)

function Import-Block($src, $left, $top) {
    $n = $doc.ImportNode($src, $true)
    $n.ID = [guid]::NewGuid().ToString()
    $n.Left = "$left"
    $n.Top = "$top"
    $n.ParentID = '00000000-0000-0000-0000-000000000000'
    [void]$items.AppendChild($n)
    return $n
}

$bStart = Import-Block $start 175 40
$bV = Import-Block $exist 135 160
$bO = Import-Block $exist 135 360
$bErr = Import-Block $write 480 250
$bSver = Import-Block $invoke 110 560
$bEndErr = Import-Block $stop 540 430
$bEndOk = Import-Block $stop 175 720

Set-Prop $bStart 'Variable1' '$Papka'
Set-Prop $bStart 'Expression1' ('&quot;{0}&quot;' -f $papka.Replace('\', '\\'))

Set-Prop $bV 'Path' '$Papka + &quot;\vigruzka.csv&quot;'
Set-Prop $bV 'TypeItem' 'File'
Set-Prop $bO 'Path' '$Papka + &quot;\otchet.csv&quot;'
Set-Prop $bO 'TypeItem' 'File'

Set-Prop $bErr 'FileName' '$Papka + &quot;\oshibka.txt&quot;'
Set-Prop $bErr 'Encoding' 'UTF8'
Set-Prop $bErr 'Value' '&quot;Не найден файл для сверки&quot;'

# Sherpa InvokeExpression склеивает переводы строк. Каждая команда заканчивается ; .
# Нельзя: function, foreach ($x in ...), for ($i=...). $vars станут $script:clssverka.X
$sverit = @'
$utf8 = New-Object System.Text.UTF8Encoding $false;
$culture = [System.Globalization.CultureInfo]::InvariantCulture;
$vigruzkaPath = Join-Path $Papka "vigruzka.csv";
$otchetPath = Join-Path $Papka "otchet.csv";
$oshibkaPath = Join-Path $Papka "oshibka.txt";
$rashPath = Join-Path $Papka "rashozhdeniya.csv";
$dupFlag = 0;
$vigruzka = [ordered]@{};
$otchet = [ordered]@{};
$lines = [System.IO.File]::ReadAllLines($vigruzkaPath, $utf8);
$header = $lines[0].Trim() -split ",";
$idxNomer = [array]::IndexOf($header, "nomer");
$idxSumma = [array]::IndexOf($header, "summa");
$idxStatus = [array]::IndexOf($header, "status");
$i = 1;
while ($i -lt $lines.Count) {
  $line = $lines[$i].Trim();
  if ($line -eq "") { $i = $i + 1; continue };
  $cols = $line -split ",", -1;
  $nomer = $cols[$idxNomer].Trim();
  $status = $cols[$idxStatus].Trim();
  $summa = [decimal]::Parse($cols[$idxSumma].Trim(), $culture);
  if ($vigruzka.Contains($nomer)) { $dupFlag = 1 };
  if (-not $vigruzka.Contains($nomer)) { $vigruzka[$nomer] = @{ nomer = $nomer; summa = $summa; status = $status } };
  $i = $i + 1;
};
$lines = [System.IO.File]::ReadAllLines($otchetPath, $utf8);
$header = $lines[0].Trim() -split ",";
$idxNomer = [array]::IndexOf($header, "nomer");
$idxSumma = [array]::IndexOf($header, "summa");
$idxStatus = [array]::IndexOf($header, "status");
$i = 1;
while ($i -lt $lines.Count) {
  $line = $lines[$i].Trim();
  if ($line -eq "") { $i = $i + 1; continue };
  $cols = $line -split ",", -1;
  $nomer = $cols[$idxNomer].Trim();
  $status = $cols[$idxStatus].Trim();
  $summa = [decimal]::Parse($cols[$idxSumma].Trim(), $culture);
  if ($otchet.Contains($nomer)) { $dupFlag = 1 };
  if (-not $otchet.Contains($nomer)) { $otchet[$nomer] = @{ nomer = $nomer; summa = $summa; status = $status } };
  $i = $i + 1;
};
if ($dupFlag -eq 1) {
  [System.IO.File]::WriteAllText($oshibkaPath, "Повторяется номер в одном файле", $utf8);
} else {
  $nomerList = New-Object System.Collections.Generic.List[string];
  $vk = @($vigruzka.Keys);
  $i = 0;
  while ($i -lt $vk.Count) { [void]$nomerList.Add($vk[$i]); $i = $i + 1 };
  $ok = @($otchet.Keys);
  $i = 0;
  while ($i -lt $ok.Count) { if (-not $nomerList.Contains($ok[$i])) { [void]$nomerList.Add($ok[$i]) }; $i = $i + 1 };
  $nomerArr = $nomerList.ToArray();
  [Array]::Sort($nomerArr);
  $groupDiff = New-Object System.Collections.Generic.List[string];
  $groupOnlyV = New-Object System.Collections.Generic.List[string];
  $groupOnlyO = New-Object System.Collections.Generic.List[string];
  $i = 0;
  while ($i -lt $nomerArr.Length) {
    $nomer = $nomerArr[$i];
    $hasV = $vigruzka.Contains($nomer);
    $hasO = $otchet.Contains($nomer);
    if ($hasV -and -not $hasO) {
      $rec = $vigruzka[$nomer];
      $sv = $rec.summa;
      if ($sv -eq [decimal]::Truncate($sv)) { $svTxt = ([decimal]::Truncate($sv)).ToString($culture) } else { $svTxt = $sv.ToString($culture).TrimEnd("0").TrimEnd(".") };
      [void]$groupOnlyV.Add(($nomer + "|net-v-otchete|" + $svTxt + "||" + $rec.status + "|"));
    } elseif ($hasO -and -not $hasV) {
      $rec = $otchet[$nomer];
      $so = $rec.summa;
      if ($so -eq [decimal]::Truncate($so)) { $soTxt = ([decimal]::Truncate($so)).ToString($culture) } else { $soTxt = $so.ToString($culture).TrimEnd("0").TrimEnd(".") };
      [void]$groupOnlyO.Add(($nomer + "|net-v-vigruzke||" + $soTxt + "||" + $rec.status));
    } else {
      $recV = $vigruzka[$nomer];
      $recO = $otchet[$nomer];
      $sv = $recV.summa;
      $so = $recO.summa;
      if ($sv -eq [decimal]::Truncate($sv)) { $svTxt = ([decimal]::Truncate($sv)).ToString($culture) } else { $svTxt = $sv.ToString($culture).TrimEnd("0").TrimEnd(".") };
      if ($so -eq [decimal]::Truncate($so)) { $soTxt = ([decimal]::Truncate($so)).ToString($culture) } else { $soTxt = $so.ToString($culture).TrimEnd("0").TrimEnd(".") };
      if ($sv -ne $so) { [void]$groupDiff.Add(($nomer + "|summa|" + $svTxt + "|" + $soTxt + "|" + $recV.status + "|" + $recO.status)) } elseif ($recV.status -ne $recO.status) { [void]$groupDiff.Add(($nomer + "|status|" + $svTxt + "|" + $soTxt + "|" + $recV.status + "|" + $recO.status)) };
    };
    $i = $i + 1;
  };
  $rows = New-Object System.Collections.Generic.List[string];
  $allGroups = @($groupDiff, $groupOnlyV, $groupOnlyO);
  $g = 0;
  while ($g -lt $allGroups.Count) {
    $grp = $allGroups[$g];
    $sorted = $grp.ToArray();
    if ($sorted.Length -gt 1) { [Array]::Sort($sorted) };
    $j = 0;
    while ($j -lt $sorted.Length) {
      $parts = $sorted[$j] -split "\|", -1;
      [void]$rows.Add(($parts[1] + "," + $parts[0] + "," + $parts[2] + "," + $parts[3] + "," + $parts[4] + "," + $parts[5]));
      $j = $j + 1;
    };
    $g = $g + 1;
  };
  $sb = New-Object System.Text.StringBuilder;
  [void]$sb.Append("nomerov,");
  [void]$sb.Append($nomerArr.Length);
  [void]$sb.Append([char]10);
  [void]$sb.Append("rashozhdeniy,");
  [void]$sb.Append($rows.Count);
  [void]$sb.Append([char]10);
  [void]$sb.Append("tip,nomer,summa_vigruzka,summa_otchet,status_vigruzka,status_otchet");
  [void]$sb.Append([char]10);
  $j = 0;
  while ($j -lt $rows.Count) { [void]$sb.Append($rows[$j]); [void]$sb.Append([char]10); $j = $j + 1 };
  [System.IO.File]::WriteAllText($rashPath, $sb.ToString(), $utf8);
};
'@

$escaped = $sverit.Replace('&', '&amp;').Replace('"', '&quot;')
Set-Prop $bSver 'Expression1' $escaped

New-Conn $doc $bStart 'Next' $bV 'Input' 1
New-Conn $doc $bV 'Yes' $bO 'Input' 2
New-Conn $doc $bV 'No' $bErr 'Input' 3
New-Conn $doc $bO 'No' $bErr 'InputLeft' 4
New-Conn $doc $bO 'Yes' $bSver 'Input' 5
New-Conn $doc $bErr 'Next' $bEndErr 'Input' 6
New-Conn $doc $bSver 'Next' $bEndOk 'Input' 7

$settings = New-Object xml.XmlWriterSettings
$settings.Indent = $true
$settings.Encoding = New-Object System.Text.UTF8Encoding $false
$w = [System.Xml.XmlWriter]::Create($outProcess, $settings)
$doc.Save($w)
$w.Close()
Write-Host "wrote $outProcess"
