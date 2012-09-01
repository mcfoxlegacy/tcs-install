#!/bin/sh

curl -O 'https://raw.github.com/taxweb/tcs-install/master/Makefile'

# Instala Make, se não estiver instalado
yum -q -y install make

make $@
