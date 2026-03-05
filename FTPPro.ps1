. "$PSScriptRoot\funciones.ps1"

$FtpRoot = "C:\inetpub\ftproot"
$FtpSite = "FTPPro"
$FtpPort = 21

if ($args.Count -eq 0) {
    Write-Host "`n"
    Write-Host "---------------------------------------------"
    Write-Host "---------- MENU SCRIPT FTP SERVER -----------"
    Write-Host "---------------------------------------------`n"
    Write-Host "Para verificar la instalacion de los paquetes:"
    Write-Host ".\FTPPro.ps1 --verificarinst`n"
    Write-Host "Para re/instalar los paquetes:"
    Write-Host ".\FTPPro.ps1 --instalar`n"
    Write-Host "Creacion de usuarios:"
    Write-Host ".\FTPPro.ps1 --crearusuario`n"
    Write-Host "Cambio de grupo (usuarios):"
    Write-Host ".\FTPPro.ps1 --moverusuario`n"
    Write-Host "Para reiniciar el servicio:"
    Write-Host ".\FTPPro.ps1 --restartserv`n"
}

switch ($args[0]) {

    "--verificarinst" {
        Get-Paquete "Web-FTP-Server"
        Get-Paquete "Web-Server"
        Get-Paquete "Web-Mgmt-Console"
        break
    }

    "--instalar" {
        Write-Host "Re/Instalacion de Paquetes:`n"
        Set-Paquete "Web-FTP-Server"
        Set-Paquete "Web-Server"
        Set-Paquete "Web-Mgmt-Console"

        Write-Host "Creando grupos locales...`n"
        foreach ($grupo in @("reprobados", "recursadores")) {
            if (-not (Get-LocalGroup -Name $grupo -ErrorAction SilentlyContinue)) {
                New-LocalGroup -Name $grupo | Out-Null
                Write-Host "Grupo $grupo creado."
            }
            else {
                Write-Host "Grupo $grupo ya existe."
            }
        }

        Write-Host "Creando carpetas...`n"
        New-Item -ItemType Directory -Force -Path "$FtpRoot\reprobados"       | Out-Null
        New-Item -ItemType Directory -Force -Path "$FtpRoot\recursadores"     | Out-Null
        New-Item -ItemType Directory -Force -Path "$FtpRoot\general"          | Out-Null
        New-Item -ItemType Directory -Force -Path "$FtpRoot\LocalUser\Public" | Out-Null

        Write-Host "Asignando permisos a carpetas...`n"

        $sidTodos = New-Object System.Security.Principal.SecurityIdentifier("S-1-1-0")
        $cuentaTodos = $sidTodos.Translate([System.Security.Principal.NTAccount])

        $acl = Get-Acl "$FtpRoot\general"
        $reglaEveryone = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $cuentaTodos, "Read", "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.AddAccessRule($reglaEveryone)
        foreach ($grupo in @("reprobados", "recursadores")) {
            $reglaGrupo = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $grupo, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow"
            )
            $acl.AddAccessRule($reglaGrupo)
        }
        Set-Acl "$FtpRoot\general" $acl

        $aclPublic = Get-Acl "$FtpRoot\LocalUser\Public"
        $reglaPublic = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $cuentaTodos, "Read", "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $aclPublic.AddAccessRule($reglaPublic)
        Set-Acl "$FtpRoot\LocalUser\Public" $aclPublic

        if (-not (Test-Path "$FtpRoot\LocalUser\Public\general")) {
            cmd /c mklink /J "$FtpRoot\LocalUser\Public\general" "$FtpRoot\general" | Out-Null
        }

        foreach ($grupo in @("reprobados", "recursadores")) {
            $aclGrupo = Get-Acl "$FtpRoot\$grupo"
            $reglaGrupo = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $grupo, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow"
            )
            $aclGrupo.AddAccessRule($reglaGrupo)
            Set-Acl "$FtpRoot\$grupo" $aclGrupo
        }

        Write-Host "Reiniciando IIS para liberar configuracion...`n"
        Stop-Service -Name "W3SVC" -ErrorAction SilentlyContinue
        Stop-Service -Name "FTPSVC" -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        & "$env:SystemRoot\system32\inetsrv\appcmd.exe" list site | Out-Null
        Start-Service -Name "W3SVC" -ErrorAction SilentlyContinue
        Start-Service -Name "FTPSVC" -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5

        Import-Module WebAdministration -Force

        Write-Host "Creando sitio FTP en IIS...`n"
        & "$env:SystemRoot\system32\inetsrv\appcmd.exe" delete site $FtpSite 2>$null

        try {
            New-WebFtpSite -Name $FtpSite -Port $FtpPort -PhysicalPath $FtpRoot -Force | Out-Null
            Write-Host "Sitio FTP creado correctamente."
        }
        catch {
            Write-Host "Error al crear sitio FTP: $_" -ForegroundColor Red
            Write-Host "Intenta correr el script nuevamente." -ForegroundColor Yellow
            break
        }

        Set-ItemProperty "IIS:\Sites\$FtpSite" `
            -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
        Set-ItemProperty "IIS:\Sites\$FtpSite" `
            -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true

        Add-WebConfiguration "/system.ftpServer/security/authorization" `
            -Value @{accessType = "Allow"; users = "*"; permissions = "Read" } `
            -PSPath "IIS:\" -Location $FtpSite

        Add-WebConfiguration "/system.ftpServer/security/authorization" `
            -Value @{accessType = "Allow"; roles = "reprobados,recursadores"; permissions = "Read,Write" } `
            -PSPath "IIS:\" -Location $FtpSite

        Set-ItemProperty "IIS:\Sites\$FtpSite" `
            -Name ftpServer.userIsolation.mode -Value 3

        New-NetFirewallRule -DisplayName "FTP Puerto 21" `
            -Direction Inbound -Protocol TCP -LocalPort 21 `
            -Action Allow -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -DisplayName "FTP Pasivo" `
            -Direction Inbound -Protocol TCP -LocalPort 1024-65535 `
            -Action Allow -ErrorAction SilentlyContinue | Out-Null

        Restart-WebItem "IIS:\Sites\$FtpSite"
        Write-Host "Sitio FTP configurado y reiniciado correctamente.`n"
        break
    }

    "--crearusuario" {
        Import-Module WebAdministration

        $num = [int](Read-Host "Cuantos usuarios deseas agregar?")
        for ($i = 1; $i -le $num; $i++) {
            Write-Host "`n--- Configurando usuario $i de $num ---"
            $usuario = Read-Host "Nombre de usuario"

            while ($true) {
                $contrasena = Read-Host "Contrasena (min 8 chars, mayuscula, numero, simbolo)" -AsSecureString
                $confirmacion = Read-Host "Confirma la contrasena" -AsSecureString

                $plain1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($contrasena))
                $plain2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirmacion))

                if ($plain1 -ne $plain2) { Write-Host "Error: Las contrasenas no coinciden. Intenta de nuevo."; continue }
                if ($plain1.Length -lt 8) { Write-Host "Error: La contrasena debe tener al menos 8 caracteres."; continue }
                break
            }

            Write-Host "Seleccione grupo: 1) reprobados  2) recursadores"
            $op = Read-Host "Opcion [1-2]"
            $grupo = if ($op -eq "1") { "reprobados" } else { "recursadores" }

            if (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue) {
                Write-Host "Error: El usuario $usuario ya existe. Saltando..."
                continue
            }

            try {
                New-LocalUser -Name $usuario -Password $contrasena -FullName $usuario `
                    -PasswordNeverExpires | Out-Null
            }
            catch {
                Write-Host "Error al crear usuario: $_" -ForegroundColor Red
                Write-Host "Verifica que la contrasena cumpla la politica de Windows Server." -ForegroundColor Yellow
                continue
            }

            Add-LocalGroupMember -Group $grupo -Member $usuario | Out-Null

            $homeBase = "$FtpRoot\LocalUser\$usuario"
            New-Item -ItemType Directory -Force -Path $homeBase         | Out-Null
            New-Item -ItemType Directory -Force -Path "$FtpRoot\$grupo" | Out-Null

            if (-not (Test-Path "$homeBase\general")) {
                cmd /c mklink /J "$homeBase\general" "$FtpRoot\general" | Out-Null
            }
            if (-not (Test-Path "$homeBase\$grupo")) {
                cmd /c mklink /J "$homeBase\$grupo" "$FtpRoot\$grupo" | Out-Null
            }
            if (-not (Test-Path "$homeBase\$usuario")) {
                New-Item -ItemType Directory -Force -Path "$homeBase\$usuario" | Out-Null
            }

            $cuenta = "$env:COMPUTERNAME\$usuario"

            foreach ($carpeta in @("$FtpRoot\general", "$FtpRoot\$grupo")) {
                $acl = Get-Acl $carpeta
                $regla = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $cuenta, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow"
                )
                $acl.AddAccessRule($regla)
                Set-Acl $carpeta $acl
            }

            $aclHome = Get-Acl $homeBase
            $reglaHome = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $cuenta, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
            )
            $aclHome.SetOwner([System.Security.Principal.NTAccount]$cuenta)
            $aclHome.AddAccessRule($reglaHome)
            Set-Acl $homeBase $aclHome

            $aclPersonal = Get-Acl "$homeBase\$usuario"
            $reglaPersonal = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $cuenta, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
            )
            $aclPersonal.SetOwner([System.Security.Principal.NTAccount]$cuenta)
            $aclPersonal.AddAccessRule($reglaPersonal)
            Set-Acl "$homeBase\$usuario" $aclPersonal

            Write-Host "Usuario $usuario configurado con exito."
        }
        break
    }

    "--moverusuario" {
        Import-Module WebAdministration

        while ($true) {
            $usuario = Read-Host "Inserta el nombre del usuario que quieres cambiar de grupo"

            if (-not (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue)) {
                Write-Host "Error: El usuario $usuario no existe."
                continue
            }

            $grupos = (Get-LocalGroup | Where-Object {
                    (Get-LocalGroupMember -Group $_.Name -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like "*\$usuario" })
                }).Name

            if ($grupos -contains "reprobados") {
                $grupoViejo = "reprobados"
                $grupoNuevo = "recursadores"
            }
            elseif ($grupos -contains "recursadores") {
                $grupoViejo = "recursadores"
                $grupoNuevo = "reprobados"
            }
            else {
                Write-Host "El usuario no se encuentra en los grupos previamente establecidos."
                continue
            }

            Remove-LocalGroupMember -Group $grupoViejo -Member $usuario -ErrorAction SilentlyContinue
            Add-LocalGroupMember    -Group $grupoNuevo -Member $usuario | Out-Null

            $homeBase = "$FtpRoot\LocalUser\$usuario"

            if (Test-Path "$homeBase\$grupoViejo") {
                cmd /c rmdir "$homeBase\$grupoViejo" | Out-Null
            }

            New-Item -ItemType Directory -Force -Path "$FtpRoot\$grupoNuevo" | Out-Null
            cmd /c mklink /J "$homeBase\$grupoNuevo" "$FtpRoot\$grupoNuevo" | Out-Null

            $aclViejo = Get-Acl "$FtpRoot\$grupoViejo"
            $aclViejo.PurgeAccessRules([System.Security.Principal.NTAccount]"$env:COMPUTERNAME\$usuario")
            Set-Acl "$FtpRoot\$grupoViejo" $aclViejo

            $aclNuevo = Get-Acl "$FtpRoot\$grupoNuevo"
            $reglaNueva = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "$env:COMPUTERNAME\$usuario", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow"
            )
            $aclNuevo.AddAccessRule($reglaNueva)
            Set-Acl "$FtpRoot\$grupoNuevo" $aclNuevo

            Write-Host "El usuario ha cambiado de grupo de manera exitosa."
            break
        }
        break
    }

    "--restartserv" {
        Import-Module WebAdministration -Force

        $svcFtp = Get-Service -Name "FTPSVC" -ErrorAction SilentlyContinue
        if ($svcFtp) {
            Restart-Service -Name "FTPSVC" -ErrorAction SilentlyContinue
            Set-Service     -Name "FTPSVC" -StartupType Automatic
            Write-Host "Servicio FTPSVC reiniciado y habilitado en el arranque."
        }
        else {
            Write-Host "El servicio FTPSVC no existe. Ejecuta --instalar primero." -ForegroundColor Yellow
        }

        if (Get-Website -Name $FtpSite -ErrorAction SilentlyContinue) {
            Restart-WebItem "IIS:\Sites\$FtpSite"
            Write-Host "Sitio $FtpSite reiniciado correctamente."
        }
        else {
            Write-Host "El sitio $FtpSite no existe. Ejecuta --instalar primero." -ForegroundColor Yellow
        }
        break
    }
}