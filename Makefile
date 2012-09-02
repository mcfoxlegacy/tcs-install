# Makefile para instalação do ambiente CCDE
# Uso:
#   make all        instala o ambiente completo
#   make portal20   instala Portal 2.0
#   make nfemais    instala NFe+

# verificar última versão em: http://www.elasticsearch.org/download/
elasticsearch_version = 0.19.9

ifneq (,$(findstring amzn,$(shell uname -r)))
export AMAZON=1
export RAILS_ENV=amazon_demo
else
export AMAZON=0
export RAILS_ENV=local_install
endif

define apache_vhost_config
<VirtualHost *:80>\n\tRackBaseURI $(app_base_uri)\n\t<Directory /var/www/html$(app_base_uri)>\n\t\tOptions -MultiViews\n\t</Directory>\n</VirtualHost>
endef

define configure_ruby_app
	sudo su - deploy -c 'mkdir -p $(1)/{releases,shared} $(1)/shared/{assets,bundle,cached-copy,pids,system,log}'
	sudo su - deploy -c 'git clone $(3) $(1)/shared/cached-copy'
	sudo su - deploy -c 'cp -pr $(1)/shared/cached-copy $(1)/releases/capless'
	sudo su - deploy -c 'ln -s $(1)/releases/capless $(1)/current'
	sudo su - deploy -c 'ln -s $(1)/shared/log $(1)/current/'
	sudo ln -s $(1)/current /var/www/html$(2)
	echo -e '$(apache_vhost_config)' | sudo tee /etc/httpd/conf.d$(2).conf
endef

.PHONY: all
all: portal20 sped_webservices nfemais

.PHONY: basics
basics:
	# Desligar SELinux
	echo 0 | sudo tee /selinux/enforce # desligar SELinux agora
	echo "SELINUX=disabled" | sudo tee /etc/sysconfig/selinux # desligar SELinux para sempre

	# Ambiente de execução
	echo "export RAILS_ENV=${RAILS_ENV}" | sudo tee /etc/profile.d/rails.sh

ifneq ($(AMAZON),1)
	# Repositório EPEL (Extra Packages for Enterprise Linux), necessário para RHEL e CentOS:
	# Consultar http://fedoraproject.org/wiki/EPEL para informações atualizadas
	sudo yum install -q -y http://epel.gtdinternet.com/6/i386/epel-release-6-7.noarch.rpm
endif

	# Instalar pacotes básicos
	sudo yum install -q -y git mutt httpd

	# Cria usuário “deploy”, se não existir
	sudo adduser -g apache -G users,wheel -u 700 deploy ; \
		e=$$?; if [ $$e -ne 9 -a $$e -ne 0 ]; then exit $$e; fi
	
	# Cria diretório /app e passa propriedade para o usuário deploy
	sudo su -c 'mkdir -p /app && chown deploy:apache /app && chmod 775 /app'
	
	# Adiciona github.com ao known_hosts
	sudo su - deploy -c 'mkdir -p ~/.ssh && chmod 600 ~/.ssh && echo "github.com,207.97.227.239 ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ==" >> ~/.ssh/known_hosts'

.PHONY: rvm
rvm: basics
	# RVM
	curl -L https://get.rvm.io | sudo bash -s stable
	sudo usermod -a -G rvm deploy # repetir para cada usuário que precisar do rvm

.PHONY: ruby_193
ruby_193: rvm
	# Pacotes para Ruby 1.9.3
	sudo yum install -q -y gcc-c++ patch readline readline-devel zlib zlib-devel libyaml-devel \
	                       libffi-devel openssl-devel make bzip2 autoconf automake libtool bison \
	                       iconv-devel httpd httpd-devel apr-devel apr-util-devel curl-devel \
	                       libxml2-devel libxslt-devel
	
	# Instalação do Ruby 1.9.3
	sudo su - deploy -c 'rvm use --default --install 1.9.3'

.PHONY: passenger
passenger: ruby_193
	# Instalação do Passenger
	sudo su - deploy -c 'gem install passenger --no-rdoc --no-ri'
	sudo su - deploy -c 'passenger-install-apache2-module --auto'
	# Configuração do Apache
	sudo su - deploy -c 'passenger-install-apache2-module --snippet' | sudo tee /etc/httpd/conf.d/00passenger.conf
	echo "RailsEnv ${RAILS_ENV}" | sudo tee /etc/httpd/conf.d/00rails_env.conf

	# Configurando o início automático do Apache
	sudo chkconfig httpd on

.PHONY: beanstalkd
beanstalkd:
	sudo yum install -q -y beanstalkd --enablerepo=epel
	sudo chkconfig beanstalkd on

.PHONY: sendmail
sendmail:
	sudo yum install -q -y sendmail
	sudo chkconfig sendmail on

.PHONY: memcached
memcached:
	sudo yum install -q -y memcached
	sudo chkconfig memcached on

.PHONY: oracle
oracle:
	# Download e instalação dos pacotes (Oracle não fornece download direto, por isso está no S3)
	mkdir -p ${HOME}/oracleclient; \
		cd ${HOME}/oracleclient; \
		curl -O 'https://s3.amazonaws.com/ccde-install/oracle-instantclient11.2-{basic,devel,sqlplus}-11.2.0.3.0-1.x86_64.rpm'; \
		sudo yum install -q -y oracle-instantclient* || true
	
	# Configurar o LD
	echo /usr/lib/oracle/11.2/client64/lib | sudo tee /etc/ld.so.conf.d/oracle.conf
	sudo ldconfig

	# Configurar variável de ambiente NLS_LANG
	echo "export NLS_LANG=american_america.AL32UTF8" | sudo tee /etc/profile.d/oracle.sh
	sudo chmod +x /etc/profile.d/oracle.sh

	# Permitir que o Apache leia as variáveis de ambiente
	echo ". /etc/profile.d/oracle.sh" | sudo tee -a /etc/sysconfig/httpd
			
.PHONY: logrotate
logrotate:
	echo -e '/app/*/shared/log/${RAILS_ENV}.log {\n\tdaily\n\tmaxage 10\n\textension .log\n\tdateformat -%Y-%m-%d\n\tmissingok\n\tnotifempty\n\tdelaycompress\n\tcopytruncate\n}' | sudo tee /etc/logrotate.d/rails

.PHONY: jruby
jruby: rvm
	# Preparação
	sudo yum install -q -y java
	
	# Instalação do JRuby
	sudo su - deploy -c 'rvm use --install jruby'

.PHONY: nodejs
nodejs: basics
	# Preparação
	sudo yum install -q -y gcc-c++ openssl-devel ncurses-devel

	# Download
	cd ${HOME} && git clone https://github.com/joyent/node.git
	cd node && git checkout v0.8.8 # conferir última versão em http://nodejs.org/

	# Compilação e Instalação
	./configure && make && sudo make install
	
	# Referência: https://github.com/joyent/node/wiki/Installation

.PHONY: elasticsearch
elasticsearch: basics
	# Aumenta o limite de arquivos abertos: http://www.elasticsearch.org/tutorials/2011/04/06/too-many-open-files.html
	echo "deploy soft nofile 32000" | sudo tee -a /etc/security/limits.conf
	echo "deploy hard nofile 32000" | sudo tee -a /etc/security/limits.conf
	
	# Criação da estrutura básica
	mkdir -p /app/elasticsearch/versions /app/elasticsearch/shared/{data,log} /app/logs/elasticsearch
	
	# Instalação
	cd /app/elasticsearch/versions
	curl -O https://github.com/downloads/elasticsearch/elasticsearch/elasticsearch-$(elasticsearch_version).tar.gz
	tar xvzf elasticsearch-$(elasticsearch_version).tar.gz
	ln -s /app/elasticsearch/shared/{data,logs} elasticseach-$(elasticsearch_version)/
	cd /app/elasticsearch
	ln -s versions/elasticsearch-$(elasticsearch_version) current
	ln -s shared/data current/data
	ln -s shared/log current/logs
	
	# Configuração
	echo "cluster.name: elasticsearch-portal20-${RAILS_ENV}-new" | tee /app/elasticsearch/current/config/elasticsearch.yml

.PHONY: nfemais
nfemais: ruby_193 passenger beanstalkd oracle logrotate
	$(call configure_ruby_app,/app/nfe_mais,/nfemais,git@github.com:elementar/nfe_mais.git)
	
	# Configura o CRON
	echo -e "`crontab -l`\n0 5,13,17 * * * /bin/bash -l -c 'cd /app/nfe_mais/current && bundle exec rake documentos:reconsulta'" | crontab

.PHONY: portal20
portal20: ruby_193 passenger beanstalkd oracle logrotate
	$(call configure_ruby_app,/app/portal20,/custodia,git@github.com:taxweb/ccde-portal-20.git)
	
	# Configura o CRON
	echo -e "`crontab -l`\n*/15 * * * * /bin/bash -l -c 'cd /app/portal20/current && time bundle exec rake ccde:documentos:indexa SLICE=1 --trace'" | crontab

.PHONY: sped_webservices
sped_webservices: ruby_193 jruby nodejs logrotate
	$(call configure_ruby_app,/app/sped_webservices,/spedws,git@github.com:elementar/sped_webservices.git)
	$(call configure_ruby_app,/app/sped-node,/spednode,git@github.com:elementar/sped-node.git)
	
	# Instala as gemas necessárias
	cd /app/sped_webservices/current && rvm-shell jruby -c 'bundle install --deployment --quiet --path /app/sped_webservices/shared/bundle --without development test'

	# Instala pacotes do node
	cd /app/sped-node/current && npm install
	
	# Configuração do CRON para limpeza dos logs, todos os dias à meia-noite
	echo -e "`crontab -l`\n0 0 * * * /bin/bash -l -c 'ls /app/sped_webservices/shared/log/kirk-*.log -r | tail -n +11 | xargs rm -v'" | crontab
	echo -e "`crontab -l`\n0 0 * * * /bin/bash -l -c 'ls /app/sped-node/shared/log/sped-node-*.log -r | tail -n +11 | xargs rm -v'" | crontab

.PHONY: start
start:
	# Inicia os serviços instalados
	sudo service httpd start 2>/dev/null || echo "Apache não instalado"
	sudo service beanstalkd start 2>/dev/null || echo "Beanstalkd não instalado"
	sudo service sendmail start 2>/dev/null || echo "Sendmail não instalado"
	sudo service memcached start 2>/dev/null || echo "Memcached não instalado"
	
	cd /app/nfe_mais/current 2>/dev/null && script/stalk_all.sh || echo "NFe+ não instalado"
	cd /app/elasticsearch/current 2>/dev/null && bin/elasticsearch || echo "ElasticSearch não instalado"
	cd /app/sped_webservices/current 2>/dev/null && script/start || echo "sped_webservices não instalado"
	cd /app/sped-node 2>/dev/null && bin/start.sh || echo "sped-node não instalado"
