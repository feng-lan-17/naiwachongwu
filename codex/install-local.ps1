[CmdletBinding(SupportsShouldProcess=$true)]
param([string]$CodexHome=$env:CODEX_HOME)
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($CodexHome)){
    $CodexHome=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'
}
$sourceManifest=Join-Path $PSScriptRoot 'pet.json'
$sourceSheet=Join-Path $PSScriptRoot 'spritesheet.png'
if(-not (Test-Path -LiteralPath $sourceManifest) -or -not (Test-Path -LiteralPath $sourceSheet)){
    throw 'Keep pet.json and spritesheet.png alongside this installer.'
}
$target=Join-Path $CodexHome 'pets\nailong-three-actions'
if($PSCmdlet.ShouldProcess($target,'Install local pet artwork and manifest')){
    [void][IO.Directory]::CreateDirectory($target)
    foreach($name in @('pet.json','spritesheet.png')){
        $destination=Join-Path $target $name
        $source=Join-Path $PSScriptRoot $name
        if(Test-Path -LiteralPath $destination){
            if((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $destination).Hash){
                Copy-Item -LiteralPath $destination -Destination ($destination+'.'+(Get-Date -Format 'yyyyMMddHHmmss')+'.bak')
            }
        }
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }
    Write-Output "Installed local pet files: $target"
    Write-Output 'Refresh the pet list and select the pet in the app.'
}
