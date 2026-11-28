param(
    [string]$GameFolder,
    [string]$Destination = (Join-Path $env:LOCALAPPDATA 'GTAVXR-QuestHolsters-Beta')
)
$ErrorActionPreference = 'Stop'
if (!$GameFolder) {
    Add-Type -AssemblyName System.Windows.Forms
    $picker = New-Object Windows.Forms.OpenFileDialog
    $picker.Title = 'Select GTA5.exe in your GTA V Legacy installation'
    $picker.Filter = 'GTA V Legacy (GTA5.exe)|GTA5.exe'
    if ($picker.ShowDialog() -ne 'OK') { exit 1 }
    $GameFolder = Split-Path -Parent $picker.FileName
}
if (!(Test-Path -LiteralPath (Join-Path $GameFolder 'GTA5.exe'))) { throw 'Choose the folder containing GTA5.exe.' }
$temp = New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N')))
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    function Get-Reader($id,$version,$expected,$relativeDll) {
        $zip = Join-Path $temp.FullName "$id.zip"
        $url = "https://api.nuget.org/v3-flatcontainer/$id/$version/$id.$version.nupkg"
        (New-Object Net.WebClient).DownloadFile($url,$zip)
        if ((Get-FileHash -LiteralPath $zip).Hash -ne $expected) { throw "Unexpected package checksum for $id." }
        $folder = Join-Path $temp.FullName $id
        [IO.Compression.ZipFile]::ExtractToDirectory($zip,$folder)
        [void][Reflection.Assembly]::LoadFrom((Join-Path $folder $relativeDll))
    }
    Write-Host 'Downloading the verified game-file reader from NuGet...'
    Get-Reader sharpdx 4.2.0 117126040200FAAA118F1312AD5A5B1E7D067C90ABF6E726F18B6D1635216FC3 'lib/net45/SharpDX.dll'
    Get-Reader sharpdx.mathematics 4.2.0 CB107F2B73C7982A31A7F9DD2E74C1C262F7B79E8B40344053A22F2AD8F1D594 'lib/net45/SharpDX.Mathematics.dll'
    Get-Reader codewalker.core 1.0.3 3DE63D8E6E0589E28B1C5D6CE269DDD02A92103C87D0EF3ECDB86C3BE8414660 'lib/netstandard2.0/CodeWalker.Core.dll'
    Write-Host 'Reading the HUD from your GTA V Legacy files...'
    [CodeWalker.GameFiles.GTA5Keys]::LoadFromPath($GameFolder,$null)
    $r = [CodeWalker.GameFiles.RpfFile]::new((Join-Path $GameFolder 'update/update.rpf'),'update.rpf')
    $r.ScanStructure([Action[string]]{},[Action[string]]{})
    $hudArchive = $r.Children | Where-Object Name -eq 'scaleform_generic.rpf' | Select-Object -First 1
    $entry = $hudArchive.AllEntries | Where-Object Name -eq 'hud.ytd' | Select-Object -First 1
    $gfx = $hudArchive.AllEntries | Where-Object Name -eq 'hud.gfx' | Select-Object -First 1
    if (!$gfx -or !$entry) { throw 'Could not find the Legacy HUD files.' }
    $getFile = [CodeWalker.GameFiles.RpfFile].GetMethods() | Where-Object { $_.Name -eq 'GetFile' -and $_.IsGenericMethodDefinition -and $_.GetParameters().Count -eq 1 } | Select-Object -First 1
    $hud = $getFile.MakeGenericMethod([CodeWalker.GameFiles.YtdFile]).Invoke($null,@($entry.PSObject.BaseObject))
    foreach ($t in $hud.TextureDict.Textures.data_items | Where-Object Name -in 'weapons_all','weapons_dlc_bb','weapons_dlc_bc','weapons_dlc_bd') {
        [IO.File]::WriteAllBytes((Join-Path $temp.FullName ($t.Name+'.dds')),[CodeWalker.Utils.DDSIO]::GetDDSFile($t))
    }
    [IO.File]::WriteAllBytes((Join-Path $temp.FullName 'hud.gfx'),$hudArchive.ExtractFile($gfx))
    & "$PSScriptRoot/tools/MakeWeaponIcons/MakeWeaponIcons.exe" $temp.FullName "$PSScriptRoot/catalog.inl"
    if ($LASTEXITCODE) { throw 'Could not generate the weapon pictures.' }
    $layer = Join-Path $Destination 'layer'
    [void](New-Item -ItemType Directory -Force $layer)
    Copy-Item -LiteralPath "$PSScriptRoot/layer/QuestFourSlotsXR.dll","$PSScriptRoot/layer/QuestFourSlots.json" -Destination $layer -Force
    Copy-Item -LiteralPath (Join-Path $temp.FullName 'original-hud.icons') -Destination (Join-Path $layer 'weapons.icons') -Force
    $mirrorDir = Join-Path $env:ProgramFiles 'OpenXR-OBSMirror'
    $mirrorName = 'XR_APILAYER_NOVENDOR_OBSMirror'
    if ((Test-Path "$mirrorDir/$mirrorName.json") -and (Test-Path "$mirrorDir/$mirrorName.dll")) {
        $manifest = Get-Content "$mirrorDir/$mirrorName.json" -Raw | ConvertFrom-Json
        $manifest.api_layer.library_path = (Resolve-Path "$mirrorDir/$mirrorName.dll").Path
        $manifest.api_layer.PSObject.Properties.Remove('disable_environment')
        $manifest | ConvertTo-Json -Depth 8 | Set-Content "$layer/OBSMirror.json" -Encoding ascii
    }
    Write-Host 'Ready. In GTAVXR Suite, choose Mods > Add mod and import QuestFourSlots.zip from the extracted download. Enable it in your Story Mode profile.'
} finally {
    $path = [IO.Path]::GetFullPath($temp.FullName)
    if ([IO.Path]::GetDirectoryName($path).TrimEnd('\') -eq [IO.Path]::GetTempPath().TrimEnd('\') -and $temp.Name -match '^[0-9a-f]{32}$') {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}
