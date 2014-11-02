define :rails_app do
  #-----------------------------------------------------------------------------------
  # variables
  #-----------------------------------------------------------------------------------
  env = params[:environment]
  app_name = "#{params[:name]}-#{env}"
  home_dir = "/home/#{app_name}"

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
end

