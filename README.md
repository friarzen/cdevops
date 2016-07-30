# cdevops
example of puppet and AWS in the real world.

This example uses a few off-the-shelf bits:

* https://github.com/puppetlabs/puppetlabs-aws
* Ruby 1.9 or greater
* Amazon AWS Ruby SDK (available as a gem)
* Retries gem

go to AWS console and create a puppetmaster instance for "long term use":
* create a keypair named 'cdevops'
* create a keypair named 'puppetmaster'
* launch new Puppetmaster instance of ami-656be372 (Ubuntu 16.04 LTS 20160721 snapshot)
* open ports 22, 80, 443, 8140
* scp -i puppetmaster.pem install.sh ubuntu@Puppetmaster:
* scp -i puppetmaster.pem cdevops.pem ubuntu@Puppetmaster:

now ssh to ubuntu@Puppetmaster and:
* sudo to root
* mv ~/cdevops.pem /root
* export AWS\_ACCESS\_KEY\_ID=
* export AWS\_SECRET\_ACCESS\_KEY=
* bash ~/install.sh
