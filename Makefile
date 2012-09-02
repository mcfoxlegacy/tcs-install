# Makefile para instalação do ambiente CCDE
# Uso:
#   make all        instala o ambiente completo
#   make portal20   instala Portal 2.0
#   make nfemais    instala NFe+

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
	mkdir -p $(app_dir)/{releases,shared}
	mkdir -p $(app_dir)/shared/{assets,bundle,cached-copy,pids,system,log}
	git clone $(git_repos) $(app_dir)/shared/cached-copy
	cp -pr $(app_dir)/shared/cached-copy $(app_dir)/releases/capless
	ln -s $(app_dir)/releases/capless $(app_dir)/current
	ln -s $(app_dir)/shared/log $(app_dir)/current/
	sudo ln -s $(app_dir)/current /var/www/html$(app_base_uri)
	
	echo -e $(apache_vhost_config) | sudo tee /etc/httpd/conf.d$(app_base_uri).conf
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
	
	# Instalação - verificar última versão em: http://www.elasticsearch.org/download/
	cd /app/elasticsearch/versions
	curl -O https://github.com/downloads/elasticsearch/elasticsearch/elasticsearch-0.19.9.tar.gz
	tar xvzf elasticsearch-0.19.9.tar.gz
	ln -s /app/elasticsearch/shared/{data,logs} elasticseach-0.19.9/
	cd /app/elasticsearch
	ln -s versions/elasticsearch-0.19.9 current
	ln -s shared/data current/data
	ln -s shared/log current/logs
	
	# Configuração
	echo "cluster.name: elasticsearch-portal20-${RAILS_ENV}-new" | tee /app/elasticsearch/current/config/elasticsearch.yml

.PHONY: nfemais
nfemais: ruby_193 passenger beanstalkd oracle logrotate
	app_dir = /app/nfe_mais
	app_base_uri = /nfemais
	git_repos = git@github.com:elementar/nfe_mais.git
	
	# Cria uma árvore compatível com a do Capistrano, para evitar surpresas
	$(configure_ruby_app)
	
	# Configura o CRON
	echo -e "`crontab -l`\n0 5,13,17 * * * /bin/bash -l -c 'cd /app/nfe_mais/current && bundle exec rake documentos:reconsulta'" | crontab

.PHONY: portal20
portal20: ruby_193 passenger beanstalkd oracle logrotate
	app_dir = /app/portal20
	app_base_uri = /custodia
	git_repos = git@github.com:taxweb/ccde-portal-20.git
	
	# Cria uma árvore compatível com a do Capistrano, para evitar surpresas
	$(configure_ruby_app)
	
	# Configura o CRON
	echo -e "`crontab -l`\n*/15 * * * * /bin/bash -l -c 'cd /app/portal20/current && time bundle exec rake ccde:documentos:indexa SLICE=1 --trace'" | crontab

.PHONY: sped_webservices
sped_webservices: ruby_193 jruby nodejs logrotate
	app_dir = /app/sped_webservices
	app_base_uri = /spedws
	git_repos = git@github.com:elementar/sped_webservices.git
	
	# Cria uma árvore compatível com a do Capistrano, para evitar surpresas
	$(configure_ruby_app)
	
	# Instala as gemas necessárias
	cd $(app_dir)/current
	rvm-shell jruby -c 'bundle install --deployment --quiet --path $(app_dir)/shared/bundle --without development test'

	# Instala sped-node
	app_dir = /app/sped-node
	app_base_uri = /spednode
	git_repos = git@github.com:elementar/sped-node.git

	$(configure_ruby_app)
	
	# Instala pacotes do node
	cd $(app_dir)/current
	npm install
	
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
