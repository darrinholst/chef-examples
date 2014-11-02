define :rails_app do
  #-----------------------------------------------------------------------------------
  # variables
  #-----------------------------------------------------------------------------------
  env = params[:environment]
  app_name = "#{params[:name]}-#{env}"
  home_dir = "/home/#{app_name}"
  environment_variables = params[:environment_variables]
  database_name = environment_variables["DATABASE_NAME"]
  database_username = environment_variables["DATABASE_USERNAME"]
  database_password = environment_variables["DATABASE_PASSWORD"]
  server_names = [params[:server_names]].flatten
  primary_server_name = server_names.first
  use_ssl = node["is_vagrant"] ? false : params[:ssl_enabled] || false

  #-----------------------------------------------------------------------------------
  # dependencies
  #-----------------------------------------------------------------------------------
  include_recipe "nginx::source"
  include_recipe "postgresql::server"
  include_recipe "postgresql::client"

  #-----------------------------------------------------------------------------------
  # user setup
  #-----------------------------------------------------------------------------------
  group app_name

  user app_name do
    gid app_name
    home home_dir
    shell "/bin/bash"
    supports :manage_home => true
  end

  directory "#{home_dir}/.ssh" do
    owner app_name
    group app_name
    mode 0700
  end

  %w{known_hosts}.each do |f|
    cookbook_file "#{home_dir}/.ssh/#{f}" do
      source "ssh/#{f}"
      owner app_name
      group app_name
      mode "0600"
    end
  end

  #-----------------------------------------------------------------------------------
  # source and log directory setup
  #-----------------------------------------------------------------------------------
  directory "/var/www/#{app_name}" do
    owner app_name
    group app_name
    recursive true
  end

  directory "/var/log/www"

  log_files = %w{chef application stdout stderr}
  log_files << 'delayed_job' if params[:delayed_job]
  log_files.each do |log|
    file "/var/log/www/#{app_name}.#{log}.log" do
      action :create_if_missing
      owner app_name
      group app_name
    end
  end

  #-----------------------------------------------------------------------------------
  # setup the unicorns
  #-----------------------------------------------------------------------------------
  template "/etc/init.d/#{app_name}" do
    source "unicorn.erb"
    owner "root"
    group "root"
    mode 0700
    variables(
      :environment => env,
      :name => app_name,
      :environment_variables => environment_variables.merge({"LOG_FILE" => "/var/log/www/#{app_name}.application.log"})
    )
  end

  service "#{app_name}" do
    action :enable
    supports [:start, :restart, :stop]
  end

  #-----------------------------------------------------------------------------------
  # nginx config
  #-----------------------------------------------------------------------------------
  template "/etc/nginx/sites-available/#{app_name}" do
    source "nginx.conf.erb"
    mode 0644
    variables(
      :name => app_name,
      :server_names => server_names,
      :ssl_enabled => use_ssl,
    )
  end

  nginx_site app_name

  nginx_site "default" do
    enable false
  end

  #---------------------------------------------------------------------
  # database setup
  #---------------------------------------------------------------------
  execute "create-database-user" do
    user "postgres"
    command "createuser -U postgres -SDRw #{database_username}"
    not_if "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='#{database_username}'\"|grep -q 1", :user => "postgres"
  end

  execute "set-database-user-password" do
    user "postgres"
    command %{psql postgres -tAc "ALTER USER \\"#{database_username}\\" WITH PASSWORD '#{database_password}'"}
  end

  execute "create-database" do
    user 'postgres'
    command "createdb -U postgres -O #{database_username} -E utf8 -l 'en_US.utf8' -T template0 #{database_name}"
    not_if "psql --list | grep -q #{database_name}", :user => "postgres"
  end

  #---------------------------------------------------------------------
  # database backup
  #---------------------------------------------------------------------
  cookbook_file "/usr/bin/aws" do
    source "aws"
    mode 0755
  end

  cookbook_file "/root/.awssecret" do
    source "awssecret"
    mode 0600
  end

  cookbook_file "/usr/local/bin/backup-postgres" do
    source "backup-postgres"
    mode 0755
  end

  cron "database backup" do
    hour 0
    minute 0
    command "/usr/local/bin/backup-postgres -f #{app_name}.dump -d #{database_name} -u #{database_username} -w #{database_password} -t '#{primary_server_name}' -k 365"
  end

  #-----------------------------------------------------------------------------------
  # deploy key setup
  #-----------------------------------------------------------------------------------
  directory "/tmp/private_code/.ssh" do
    owner app_name
    recursive true
  end

  cookbook_file "/tmp/private_code/deploy-ssh-wrapper.sh" do
    source "ssh/deploy-ssh-wrapper.sh"
    owner app_name
    mode 0700
  end

  cookbook_file "/tmp/private_code/.ssh/id_deploy" do
    source "ssh/id_deploy"
    owner app_name
    mode 0600
  end

  #-----------------------------------------------------------------------------------
  # delayed_job
  #-----------------------------------------------------------------------------------
  if params[:delayed_job]
    include_recipe "monit"

    template "/etc/monit/conf.d/delayed_job.#{app_name}.conf" do
      source "delayed_job.monitrc.erb"
      owner "root"
      group "root"
      mode 0644
      variables({
        :app_name => app_name,
        :env => env,
        :worker_count => 1,
        :worker_name => "#{app_name}_delayed_job",
        :environment_variables => environment_variables
      })
      notifies :restart, "service[monit]"
    end
  end
end

