#!/bin/bash

#-----------------------------------------------------------------------------
# Install ruby
#-----------------------------------------------------------------------------
rm -rf /opt/ruby
echo "installing ruby"
apt-get -y install ruby1.8 ruby1.8-dev rubygems1.8 libopenssl-ruby1.8

#-----------------------------------------------------------------------------
# Install chef-solo
#-----------------------------------------------------------------------------
if [[ `/var/lib/gems/1.8/bin/chef-solo --version` != Chef:\ 0.10.8* ]]; then
  echo "installing chef"
  gem install chef --no-ri --no-rdoc
  mkdir -p /var/chef/cache
  chmod 777 /var/chef/cache
fi

#-----------------------------------------------------------------------------
# Run chef-solo
#-----------------------------------------------------------------------------
echo "running chef-solo"
/var/lib/gems/1.8/bin/chef-solo -c /opt/chef/solo.rb -j /opt/chef/solo.json

