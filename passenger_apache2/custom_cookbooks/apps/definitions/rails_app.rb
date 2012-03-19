define :rails_app do
  #---------------------------------------------------------------------
  # All the recipes this app will need
  #---------------------------------------------------------------------
  include_recipe 'apt'
  include_recipe 'git'
  include_recipe 'ruby::1.9.3-p125'
  include_recipe 'postgresql::server'
  include_recipe 'apache2'
  include_recipe 'apache2::mod_ssl'
  include_recipe 'apache2::mod_rewrite'
  include_recipe 'passenger_apache2::mod_rails'


  #---------------------------------------------------------------------
  # the application config
  #---------------------------------------------------------------------
  app = {
    :id          => params[:name],
    :owner       => params[:name],
    :group       => params[:name],
    :deploy_to   => "/var/www/#{params[:name]}",
    :repository  => params[:repo],
    :revision    => 'HEAD',
    :environment => 'production',
    :migrate     => true,
    :databases   => {
      :production => {
        :adapter => 'postgresql',
        :host => "localhost",
        :database => params[:name],
        :username => params[:name],
        :password => '89sdfaj;OIU' #TODO: randomize thsi
      }
    }
  }


  #---------------------------------------------------------------------
  # application user/group
  #---------------------------------------------------------------------
  group app[:group]

  user app[:owner] do
    gid app[:group]
    shell "/bin/false"
  end


  #---------------------------------------------------------------------
  # apache/passenger config
  #---------------------------------------------------------------------
  web_app app[:id] do
    docroot   "#{app[:deploy_to]}/current/public"
    template  "passenger_apache2.conf.erb"
    log_dir   node[:apache][:log_dir]
    rails_env app[:environment]
  end

  apache_site "000-default" do
    enable false
  end


  #---------------------------------------------------------------------
  # database setup
  #---------------------------------------------------------------------
  postgresql_database_user "create database user" do
    connection ({:host => "localhost", :username => 'postgres', :password => node['postgresql']['password']['postgres']})
    username app[:databases][app[:environment].to_sym][:username]
    password app[:databases][app[:environment].to_sym][:password]
  end

  postgresql_database app[:databases][app[:environment].to_sym][:database] do
    connection ({:host => "localhost", :username => 'postgres', :password => node['postgresql']['password']['postgres']})
    owner app[:databases][app[:environment].to_sym][:username]
  end


  #---------------------------------------------------------------------
  # deploy directory setup
  #---------------------------------------------------------------------
  directory app[:deploy_to] do
    owner app[:owner]
    group app[:group]
    mode 0755
    recursive true
  end

  directory "#{app[:deploy_to]}/shared" do
    owner app[:owner]
    group app[:group]
    mode 0755
    recursive true
  end

  template "#{app[:deploy_to]}/shared/database.yml" do
    source "database.yml.erb"
    owner app[:owner]
    group app[:group]
    mode 0644
    variables(
      :databases => app[:databases]
    )
  end

  %w{assets log pids system bundle}.each do |dir|
    directory "#{app[:deploy_to]}/shared/#{dir}" do
      owner app[:owner]
      group app[:group]
      mode 0755
      recursive true
    end
  end


  #---------------------------------------------------------------------
  # private repo setup
  #---------------------------------------------------------------------
  if app.has_key?(:deploy_key)
    ruby_block "write_key" do
      block do
        f = ::File.open("#{app[:deploy_to]}/id_deploy", "w")
        f.print(app[:deploy_key])
        f.close
      end
      not_if do ::File.exists?("#{app[:deploy_to]}/id_deploy"); end
    end

    file "#{app[:deploy_to]}/id_deploy" do
      owner app[:owner]
      group app[:group]
      mode 0600
    end

    template "#{app[:deploy_to]}/deploy-ssh-wrapper" do
      source "deploy-ssh-wrapper.erb"
      owner app[:owner]
      group app[:group]
      mode 0755
      variables app
    end
  end


  #---------------------------------------------------------------------
  # deploy the app
  #---------------------------------------------------------------------
  deploy_revision app[:id] do
    action :deploy
    revision app[:revision]
    repository app[:repository]
    user app[:owner]
    group app[:group]
    deploy_to app[:deploy_to]
    environment 'RAILS_ENV' => app[:environment]
    ssh_wrapper "#{app[:deploy_to]}/deploy-ssh-wrapper" if app[:deploy_key]
    shallow_clone true
    migrate true
    migration_command "rake db:migrate"
    symlinks("log" => "log", "assets" => "public/assets", "system" => "public/system", "pids" => "tmp/pids")
    symlink_before_migrate("database.yml" => "config/database.yml")

    before_migrate do
      execute "bundle install --path #{app[:deploy_to]}/shared/bundle --deployment --without development test" do
        cwd release_path
      end
    end

    before_restart do
      execute "bundle exec rake RAILS_ENV=#{app[:environment]} RAILS_GROUPS=assets assets:precompile:primary" do
        cwd release_path
      end
    end

    restart_command do
      execute "touch #{app[:deploy_to]}/current/tmp/restart.txt"
    end
  end
end

