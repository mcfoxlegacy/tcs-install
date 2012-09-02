#!/bin/bash -e

# Instala Make, se não estiver instalado
sudo yum -q -y install make

# Baixa o Makefile para o local correto
sudo mkdir -p /opt/tcs-install ; cd $_
sudo curl -s -O 'https://raw.github.com/taxweb/tcs-install/master/Makefile'

# Executa o Makefile com as opções fornecidas na linha de comando
make $@
