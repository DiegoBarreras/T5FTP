source "$(dirname "$0")/funciones.sh"

if [[ $# -eq 0 ]]; then
	echo -e "\n"
	echo -e "---------------------------------------------"
	echo -e "---------- MENU SCRIPT FTP SERVER -'---------"
	echo -e "---------------------------------------------\n"

	echo -e "Para verificar la instalacion de los paquetes:"
	echo -e "./FTPPro.sh --verificarinst\n"

	echo -e "Para re/instalar los paquetes:"
	echo -e "./FTPPro.sh --instalar\n"

	echo -e "Creacion de usuarios:"
	echo -e "./FTPPro.sh --crearusuario\n"

	echo -e "Cambio de grupo (usuarios):"
	echo -e "./FTPPro.sh --moverusuario\n"

	echo -e "Para reiniciar el servicio:"
	echo -e "./FTPPro.sh --restartserv\n"
fi

case $1 in
	--verificarinst)
		verificar_paquete "vsftpd"
		verificar_paquete "acl"
		verificar_paquete "policycoreutils-python-utils"
		exit 0
	;;

	--instalar)
		echo -e "Re/Instalacion de Paquetes: \n"
		instalar_paquete "vsftpd"
		instalar_paquete "acl"
		instalar_paquete "policycoreutils-python-utils"
		
		echo -e "Creando carpetas... \n"
		mkdir -p /srv/ftp/reprobados
		mkdir -p /srv/ftp/recursadores
		mkdir -p /srv/ftp/general

		echo -e "Creando grupos... \n"
		groupadd -f reprobados
		groupadd -f recursadores

		echo -e "Actualizando configuracion de carpetas... \n"
		semanage fcontext -a -t public_content_rw_t "/srv/ftp(/.*)?"
		restorecon -Rv /srv/ftp
		setsebool -P ftpd_full_access 1

		echo -e "Asignando permisos... \n"
		chmod 755 /srv/ftp/general
		setfacl -m g:reprobados:rwx /srv/ftp/general
		setfacl -m g:recursadores:rwx /srv/ftp/general

		echo -e "Configurando /etc/vsftpd.conf... \n"
cat <<EOF > /etc/vsftpd.conf
# Configuracion general
listen=NO
listen_ipv6=YES
anonymous_enable=YES
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES

# Rutas y accesos
anon_root=/srv/ftp/general
chroot_local_user=YES
allow_writeable_chroot=YES

# Seguridad y aislamiento
pam_service_name=vsftpd
userlist_enable=YES
tcp_wrappers=YES
EOF

	systemctl restart vsftpd

	;;

	--crearusuario)
        read -p "¿Cuántos usuarios deseas agregar? " num
        for ((i=1; i<=num; i++)); do
            echo -e "\n--- Configurando usuario $i de $num ---"
            read -p "Nombre de usuario: " usuario
            read -s -p "Contraseña: " contrasena
            echo ""
            
            echo "Seleccione grupo: 1) reprobados 2) recursadores"
            read -p "Opción [1-2]: " op
            if [[ "$op" == "1" ]]; then grupo="reprobados"; else grupo="recursadores"; fi

            if id "$usuario" &>/dev/null; then
                echo "Error: El usuario $usuario ya existe. Saltando..."
            else
                useradd -m -G "$grupo" "$usuario"
                echo "$usuario:$contrasena" | chpasswd

                mkdir -p "/home/$usuario/general"
                mkdir -p "/home/$usuario/$grupo"
                mkdir -p "/home/$usuario/$usuario"

                chown -R "$usuario:$grupo" "/home/$usuario"

                mount --bind /srv/ftp/general "/home/$usuario/general"
                mount --bind "/srv/ftp/$grupo" "/home/$usuario/$grupo"
                mount --bind "/home/$usuario" "/home/$usuario/$usuario"

                setfacl -m u:"$usuario":rwx "/srv/ftp/$grupo"
                setfacl -m u:"$usuario":rwx /srv/ftp/general
                
                echo "Usuario $usuario configurado con éxito."
            fi
        done
    ;;

	--moverusuario)
	while true; do
		read -p "Inserta el nombre del usuario que quieres cambiar de grupo." usuario

		if ! id "$usuario" &>/dev/null; then
        	echo "Error: El usuario $usuario no existe."
			continue
        fi

		echo "Seleccione grupo: 1) reprobados 2) recursadores"
        read -p "Opción [1-2]: " op
        if [[ "$op" == "1" ]]; then grupo="reprobados"; else grupo="recursadores"; fi

		if groups "$usuario" | grep -q "reprobados"; then
			grupo_viejo="reprobados"
            grupo_nuevo="recursadores"
		elif groups "$usuario" | grep -q "recursadores"; then
			grupo_viejo="recursadores"
            grupo_nuevo="reprobados"
		else
			echo "El usuario no se encuentra en los grupos previamente establecidos."
			continue
		fi			

		usermod -g "$grupo_nuevo" -G "$grupo_viejo" "$usuario"

		umount "/home/$usuario/$grupo_viejo"
		rmdir "/home/$usuario/$grupo_viejo"

		mkdir -p "/home/$usuario/$grupo_nuevo"
		mount --bind "/srv/ftp/$grupo_nuevo" "/home/$usuario/$grupo_nuevo"

		setfacl -x u:"$usuario" "/srv/ftp/$grupo_viejo"
        setfacl -m u:"$usuario":rwx "/srv/ftp/$grupo_nuevo"
        chown -R "$usuario:$grupo_nuevo" "/home/$usuario"

		echo -e "El usuario ha cambiado de grupo de manera exitosa."
		break
	done
	;;

	--restartserv)
		systemctl restart vsftpd
        systemctl enable vsftpd
        echo "Servicio FTP reiniciado y habilitado en el arranque."
	;;

esac