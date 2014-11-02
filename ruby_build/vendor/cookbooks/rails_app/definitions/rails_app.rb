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
end

