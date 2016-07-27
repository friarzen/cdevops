# cdevops
example of puppet and AWS in the real world.

This example uses a few off-the-shelf bits:

* https://github.com/puppetlabs/puppetlabs-aws
* Ruby 1.9 or greater
* Amazon AWS Ruby SDK (available as a gem)
* Retries gem

This example was written for Puppet 3.8, which is included in Ubuntu 16.04 LTS

basic puppetmaster steps taken were:
* git clone this repo as /etc/puppet
* git clone the env repo as /etc/puppet/env/production and /etc/puppet/env/dev
* git checkout the production branch for production
* git checkout the dev branch for dev
* edit the /etc/puppet/hiera/defaults.yaml to insert the puppetmaster IP Address

spin up the client environment by:
* change directory to /etc/puppet/env/common/modules/puppetlabs-aws
* export your AWS\_ACCESS\_KEY\_ID and AWS\_SECRET\_ACCESS\_KEY
* run "puppet apply /etc/puppet/env/provisioning/manifests/create.pp"

