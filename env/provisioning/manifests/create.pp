#
# This is basically a stripped down copy of the basic test create.pp module from
# https://github.com/puppetlabs/puppetlabs-aws
#
# no sense in re-inventing the wheel.
#
# creates a load balancer and a basic web instance with SSH access
#
#  You will need to create a keypair in AWS named 'cdevopskey' to connect.
#

Ec2_securitygroup {
  region => 'us-east-1',
}

Ec2_instance {
  region            => 'us-east-1',
  availability_zone => 'us-east-1a',
}

#Elb_loadbalancer {
#  region => 'us-east-1',
#}
#
#ec2_securitygroup { 'lb-secgrp':
#  ensure      => present,
#  description => 'Security group for load balancer',
#  ingress     => [
#    {
#      protocol => 'tcp',
#      port     => 80,
#      cidr     => '0.0.0.0/0'
#    },
#    {
#      protocol => 'tcp',
#      port     => 443,
#      cidr     => '0.0.0.0/0'
#    }
#  ],
#}

ec2_securitygroup { 'web-secgrp':
  ensure      => present,
  description => 'Security group for web servers',
  ingress     => [
    {
      protocol => 'tcp',
      port     => 22,
      cidr     => '0.0.0.0/0'
    },{
      protocol => 'tcp',
      port     => 80,
      cidr     => '0.0.0.0/0'
    },{
      protocol => 'tcp',
      port     => 443,
      cidr     => '0.0.0.0/0'
    }
  ],
}

# launch the public ubuntu 14.04 as a micro instance
ec2_instance { ['web1']:
  ensure          => present,
  region          => 'us-east-1',
  image_id        => 'ami-656be372',
  security_groups => ['web-secgrp'],
  instance_type   => 't1.micro',
  tenancy         => 'default',
  key_name        => 'cdevopskey',
  user_data       => template('/etc/puppet/env/provisioning/templates/user-data.erb'),
}

#elb_loadbalancer { 'lb1':
#  ensure             => present,
#  availability_zones => ['us-east-1a'],
#  instances          => ['web1'],
#  listeners          => [
#    {
#      protocol           => 'tcp',
#      load_balancer_port => 80,
#      instance_protocol  => 'tcp',
#      instance_port      => 80,
#    },
#    {
#      protocol           => 'tcp',
#      load_balancer_port => 443,
#      instance_protocol  => 'tcp',
#      instance_port      => 443,
#    },
#  ],
#}
