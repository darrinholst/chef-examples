actions :deploy
default_action :deploy

attribute :name,                  :kind_of => String, :required => true
attribute :environment,           :kind_of => String, :required => true
attribute :repository,            :kind_of => String, :required => true
attribute :revision,              :kind_of => String, :required => true
attribute :ruby_version,          :kind_of => String, :required => true
attribute :ssl_enabled,           :kind_of => [TrueClass, FalseClass]
attribute :delayed_job,           :kind_of => [TrueClass, FalseClass]
attribute :server_names,          :kind_of => Array, :required => true
attribute :environment_variables, :kind_of => Hash, :required => true

