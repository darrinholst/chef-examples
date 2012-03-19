default[:passenger][:version]     = "3.0.11"
default[:passenger][:max_pool_size] = "6"
default[:passenger][:root_path]   = "/usr/local/lib/ruby/gems/1.9.1/gems/passenger-#{passenger[:version]}"
default[:passenger][:module_path] = "#{passenger[:root_path]}/ext/apache2/mod_passenger.so"
