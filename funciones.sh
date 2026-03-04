verificar_paquete() {
	local paq=$1
	echo "Buscando al paquete $paq:"
	if rpm -q $paq &> /dev/null; then
		echo -e "El paquete $paq fue instalado previamente.\n"
	else
		echo -e "El paquete $paq no ha sido instalado.\n"
	fi
}

instalar_paquete() {
	local paq=$1
	verificar_paquete $paq
	if rpm -q $paq &> /dev/null; then
		read -p "Deseas reinstalar el paquete $paq? s/n " res
		res=${res,,}
		if [[ $res == "s" ]]; then
			echo -e "Reinstalando el paquete $paq.\n"
			sudo dnf reinstall -y $paq
		else
			echo -e "La instalacion fue cancelada.\n"
		fi
	else
		read -p "Deseas instalar el paquete $paq? s/n " res
		res=${res,,}
		if [[ $res == "s" ]]; then
			echo -e "Instalando el paquete $paq.\n"
			sudo dnf install -y $paq
		else
			echo -e "La instalacion fue cancelada.\n"
		fi
	fi
}