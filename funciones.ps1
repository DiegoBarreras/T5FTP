function Verificar-Paquete {
    param([string]$Caracteristica)

    Write-Host "Buscando la caracteristica $Caracteristica :"

    $estado = Get-WindowsFeature -Name $Caracteristica -ErrorAction SilentlyContinue

    if ($estado -and $estado.Installed) {
        Write-Host "La caracteristica $Caracteristica fue instalada previamente.`n"
    }
    else {
        Write-Host "La caracteristica $Caracteristica no ha sido instalada.`n"
    }
}

function Instalar-Paquete {
    param([string]$Caracteristica)

    Verificar-Paquete -Caracteristica $Caracteristica
    $estado = Get-WindowsFeature -Name $Caracteristica -ErrorAction SilentlyContinue

    if ($estado -and $estado.Installed) {
        $res = (Read-Host "Deseas reinstalar la caracteristica $Caracteristica? s/n").ToLower()
        if ($res -eq "s") {
            Write-Host "Reinstalando la caracteristica $Caracteristica.`n"
            Uninstall-WindowsFeature -Name $Caracteristica | Out-Null
            Install-WindowsFeature -Name $Caracteristica -IncludeManagementTools | Out-Null
        }
        else {
            Write-Host "La instalacion fue cancelada.`n"
        }
    }
    else {
        $res = (Read-Host "Deseas instalar la caracteristica $Caracteristica? s/n").ToLower()
        if ($res -eq "s") {
            Write-Host "Instalando la caracteristica $Caracteristica.`n"
            Install-WindowsFeature -Name $Caracteristica -IncludeManagementTools | Out-Null
        }
        else {
            Write-Host "La instalacion fue cancelada.`n"
        }
    }
}