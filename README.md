# TCS Installer

An installer for the Total Compliance Suite.

## Usage

To install all projects, use:

    curl -s https://raw.github.com/taxweb/tcs-install/master/tcs-install.sh | bash

To install a single project, use any of those:

    curl -s https://raw.github.com/taxweb/tcs-install/master/tcs-install.sh | bash -s portal20
	curl -s https://raw.github.com/taxweb/tcs-install/master/tcs-install.sh | bash -s nfemais
	curl -s https://raw.github.com/taxweb/tcs-install/master/tcs-install.sh | bash -s elasticsearch
	...

Make sure you edit the configuration files after installing.
Most of them are in `.yml` files on folders named `config`.

Check the individual `README` files for more details.
