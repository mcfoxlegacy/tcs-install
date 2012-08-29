# Makefile para instalação do ambiente CCDE
# Uso:
#   make all        instala o ambiente completo
#   make portal20   instala Portal 2.0
#   make nfemais    instala NFe+

# Substituir pelo nome correto do ambiente: "production", "staging", "demo", etc
export RAILS_ENV=amazon_demo

.PHONY: basics
basics:
	# Desligar SELinux
	echo 0 | sudo tee /selinux/enforce # desligar SELinux agora
	echo "SELINUX=disabled" | sudo tee /etc/sysconfig/selinux # desligar SELinux para sempre

	# Ambiente de execução
	echo "export RAILS_ENV=${RAILS_ENV}" | sudo tee /etc/profile.d/rails.sh

	# Usuário “deploy”
	sudo adduser -g apache -G users,wheel -u 700 deploy

	# Repositório EPEL (Extra Packages for Enterprise Linux), necessário para RHEL e CentOS:
	# Consultar http://fedoraproject.org/wiki/EPEL para informações atualizadas
	sudo yum install -y http://epel.gtdinternet.com/6/i386/epel-release-6-7.noarch.rpm

	# Instalar pacotes básicos
	sudo yum -y install git mutt

.PHONY: rvm
rvm: basics
	# RVM
	curl -L https://get.rvm.io | sudo bash -s stable
	sudo usermod -a -G rvm deploy # repetir para cada usuário que precisar do rvm

.PHONY: ruby_193
ruby_193: rvm
	# Pacotes para Ruby 1.9.3
	sudo yum install -y gcc-c++ patch readline readline-devel zlib zlib-devel libyaml-devel \
	                    libffi-devel openssl-devel make bzip2 autoconf automake libtool bison \
	                    iconv-devel httpd httpd-devel apr-devel apr-util-devel curl-devel \
	                    libxml2-devel libxslt-devel
	
	# Instalação do Ruby 1.9.3
	rvm install 1.9.3
	rvm use --default 1.9.3

.PHONY: passenger
passenger: ruby_193
	# Instalação do Passenger e Configuração do Apache
	gem install passenger --no-rdoc --no-ri
	passenger-install-apache2-module --auto
	passenger-install-apache2-module --snippet | sudo tee /etc/httpd/conf.d/00passenger.conf
	echo "RailsEnv ${RAILS_ENV}" | sudo tee /etc/httpd/conf.d/00rails_env.conf

	# Configurando o início automático do Apache
	sudo chkconfig httpd on

.PHONY: beanstalkd
beanstalkd:
	sudo yum install -y beanstalkd
	sudo chkconfig beanstalkd on

.PHONY: sendmail
sendmail:
	sudo yum install -y sendmail
	sudo chkconfig sendmail on

.PHONY: memcached
sendmail:
	sudo yum install -y memcached
	sudo chkconfig memcached on

.PHONY: oracle
oracle:
	# Download e instalação dos pacotes (Oracle não fornece download direto, por isso está no S3)
	mkdir -p ${HOME}/oracleclient && cd $_
	curl 'https://s3.amazonaws.com/ccde-install/oracle-instantclient11.2-{basic,devel,sqlplus}-11.2.0.3.0-1.x86_64.rpm' -O
	sudo yum install -y oracle-instantclient*
	
	# Configurar o LD
	echo /usr/lib/oracle/11.2/client64/lib | sudo tee /etc/ld.so.conf.d/oracle.conf
	sudo ldconfig

	# Configurar variável de ambiente NLS_LANG
	echo "export NLS_LANG=american_america.AL32UTF8" | sudo tee /etc/profile.d/oracle.sh
	sudo chmod +x /etc/profile.d/oracle.sh

	# Permitir que o Apache leia as variáveis de ambiente
	echo ". /etc/profile.d/oracle.sh" | sudo tee -a /etc/sysconfig/httpd
	sudo service httpd restart
			
.PHONY: logrotate
logrotate:
	cat | sudo tee /etc/logrotate.d/rails <<-END
	/app/*/shared/log/${RAILS_ENV}.log {
	    daily
	    maxage 10
	    extension .log
	    dateformat -%Y-%m-%d
	    missingok
	    notifempty
	    delaycompress
	    copytruncate
	}
	END

.PHONY: jruby
jruby: rvm
	# Preparação
	sudo yum install -y java
	
	# Instalação do JRuby
	rvm install jruby
	rvm use --default jruby

.PHONY: nodejs
nodejs: basics
	# Preparação
	sudo yum install -y gcc-c++ openssl-devel ncurses-devel

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
	# Cria uma árvore compatível com a do Capistrano, para evitar surpresas
	mkdir -p /app/nfe_mais/{releases,shared}
	mkdir -p /app/nfe_mais/shared/{assets,bundle,cached-copy,pids,system,log}
	git clone git@github.com:elementar/nfe_mais.git /app/nfe_mais/shared/cached-copy
	cp -pr /app/nfe_mais/shared/cached-copy /app/nfe_mais/releases/capless
	ln -s /app/nfe_mais/releases/capless /app/nfe_mais/current
	ln -s /app/nfe_mais/shared/log /app/nfe_mais/current/
	
	# Configura o Apache
	sudo ln -s /app/nfe_mais/current /var/www/html/nfemais
	cat | sudo tee /etc/httpd/conf.d/nfe_mais.conf <<-END
	<VirtualHost *:80>
	  RackBaseURI /nfemais
	  <Directory /var/www/html/nfemais>
	    Options -MultiViews
	  </Directory>
	</VirtualHost>
	END
	
	# Configura o CRON
	crontab <<-END
	`crontab -l`
	0 5,13,17 * * * /bin/bash -l -c 'cd /app/nfe_mais/current && bundle exec rake documentos:reconsulta'
	END

.PHONY: portal20
nfemais: ruby_193 passenger beanstalkd oracle logrotate
	# Cria uma árvore compatível com a do Capistrano, para evitar surpresas
	mkdir -p /app/portal20/{releases,shared}
	mkdir -p /app/portal20/shared/{assets,bundle,cached-copy,pids,system,log}
	git clone git@github.com:ccde-dev/ccde-portal-20.git /app/portal20/shared/cached-copy
	cp -pr /app/portal20/shared/cached-copy /app/portal20/releases/capless
	ln -s /app/portal20/releases/capless /app/portal20/current
	ln -s /app/portal20/shared/log /app/portal20/current/
	
	# Configura o Apache
	sudo ln -s /app/portal20/current /var/www/html/custodia
	cat | sudo tee /etc/httpd/conf.d/portal20.conf <<-END
	<VirtualHost *:80>
	  RackBaseURI /custodia
	  <Directory /var/www/html/custodia>
	    Options -MultiViews
	  </Directory>
	</VirtualHost>
	END
	
	# Configura o CRON
	crontab <<-END
	`crontab -l`
	*/15 * * * * /bin/bash -l -c 'cd /app/portal20/current && time bundle exec rake ccde:documentos:indexa SLICE=1 --trace'
	END

.PHONY: sped_webservices
sped_webservices: ruby_193 jruby nodejs logrotate
	# Cria uma árvore compatível com a do Capistrano, para evitar surpresas
	mkdir -p /app/sped_webservices/{releases,shared}
	mkdir -p /app/sped_webservices/shared/{assets,bundle,cached-copy,pids,system,log}
	git clone git@github.com:ccde-dev/ccde-portal-20.git /app/sped_webservices/shared/cached-copy
	cp -pr /app/sped_webservices/shared/cached-copy /app/sped_webservices/releases/capless
	ln -s /app/sped_webservices/releases/capless /app/sped_webservices/current
	ln -s /app/sped_webservices/shared/log /app/sped_webservices/current/
	
	# Instala as gemas necessárias
	cd /app/sped_webservices/current
	rvm-shell jruby -c 'bundle install --deployment --quiet --path /app/sped_webservices/shared/bundle --without development test'

	# Instalação do sped-node
	mkdir -p /app/sped-node/{releases,shared}
	mkdir -p /app/sped_webservices/shared/{cached-copy,log}
	git clone git@github.com:ccde-dev/ccde-portal-20.git /app/sped_webservices/shared/cached-copy
	cp -pr /app/sped_webservices/shared/cached-copy /app/sped_webservices/releases/capless
	ln -s /app/sped_webservices/releases/capless /app/sped_webservices/current
	
	git clone git@github.com:ccde-dev/sped-node.git /app/sped-node
	cd /app/sped-node
	mkdir -p /app/sped-node/shared/log
	ln -s /app/log/sped-node log
	npm install
	
	# Configuração do CRON para limpeza dos logs, todos os dias à meia-noite
	crontab <<-END
	`crontab -l`
	0 0 * * * /bin/bash -l -c 'ls /app/sped_webservices/shared/log/kirk-*.log -r | tail -n +11 | xargs rm -v'
	0 0 * * * /bin/bash -l -c 'ls /app/sped-node/shared/log/sped-node-*.log -r | tail -n +11 | xargs rm -v'
	END

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
