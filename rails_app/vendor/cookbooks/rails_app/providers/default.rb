include Chef::DSL::IncludeRecipe

action :deploy do
  include_dependencies
  create_user
  create_app_directories
  create_unicorn_config
  create_nginx_config
  create_database
  configure_database_backup
  configure_deploy_key
  configure_delayed_job
  deploy_it
end

def environment_name
  new_resource.environment
end

def app_name
  "#{new_resource.id}-#{environment_name}"
end

def repo
  new_resource.repository
end

def revision
  new_resource.revision
end

def ruby_version
  #TODO: get this from the Gemfile
  new_resource.ruby_version
end

def ruby_home
  "#{node['ruby_build']['default_ruby_base_path']}/#{ruby_version}"
end

def environment_variables(log_to = 'application')
  new_resource.environment_variables.merge({
    "BUNDLE_GEMFILE" => "/var/www/#{app_name}/current/Gemfile",
    "LOG_FILE" => "/var/log/www/#{app_name}.#{log_to}.log",
    "PATH" => "#{ruby_home}/bin:/usr/local/bin:/usr/bin:/bin"
  })
end

def server_names
  new_resource.server_names
end

def ssl?
  new_resource.ssl_enabled
end

def delayed_job?
  new_resource.delayed_job
end

def delayed_job_worker_count
  1
end

def action
  :deploy
end

private

def include_dependencies
  provider = self
  include_recipe 'nginx::source'
  include_recipe 'postgresql::server'
  include_recipe 'postgresql::client'
  include_recipe 'ruby_build'
  include_recipe 'monit' if provider.delayed_job?
end

def create_user
  provider = self
  home_dir = "/home/#{provider.app_name}"

  group provider.app_name

  user provider.app_name do
    gid provider.app_name
    home home_dir
    shell "/bin/bash"
    supports :manage_home => true
  end

  directory "#{home_dir}/.ssh" do
    owner provider.app_name
    group provider.app_name
    mode 0700
  end

  cookbook_file "#{home_dir}/.ssh/known_hosts" do
    source "ssh/known_hosts"
    owner provider.app_name
    group provider.app_name
    mode "0600"
  end
end

def create_app_directories
  provider = self

  directory "/var/www/#{provider.app_name}" do
    owner provider.app_name
    group provider.app_name
    recursive true
  end

  directory "/var/log/www"

  log_files = %w{chef application stdout stderr}
  log_files << 'delayed_job' if provider.delayed_job?
  log_files.each do |log|
    file "/var/log/www/#{provider.app_name}.#{log}.log" do
      action :create_if_missing
      owner provider.app_name
      group provider.app_name
    end
  end
end

def create_unicorn_config
  provider = self
  environment_variables = environment_variables('application')

  template "/etc/init.d/#{provider.app_name}" do
    source "unicorn.erb"
    owner "root"
    group "root"
    mode 0700
    variables(
      :environment => provider.environment_name,
      :name => provider.app_name,
      :environment_variables => environment_variables
    )
  end

  service "#{provider.app_name}" do
    action :enable
    supports [:start, :restart, :stop]
  end
end

def create_nginx_config
  provider = self

  template "/etc/nginx/sites-available/#{provider.app_name}" do
    source "nginx.conf.erb"
    mode 0644
    variables(
      :name => provider.app_name,
      :server_names => provider.server_names,
      :ssl_enabled => provider.ssl?
    )
  end

  nginx_site provider.app_name

  nginx_site "default" do
    enable false
  end
end

def create_database
  provider = self
  database_name = provider.environment_variables['DATABASE_NAME']
  database_username = provider.environment_variables['DATABASE_USERNAME']
  database_password = provider.environment_variables['DATABASE_PASSWORD']

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
end

def configure_database_backup
  provider = self
  database_name = provider.environment_variables['DATABASE_NAME']
  database_username = provider.environment_variables['DATABASE_USERNAME']
  database_password = provider.environment_variables['DATABASE_PASSWORD']

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
    command "/usr/local/bin/backup-postgres -f #{provider.app_name}.dump -d #{database_name} -u #{database_username} -w #{database_password} -t '#{provider.server_names.first}' -k 365"
  end
end

def configure_deploy_key
  provider = self

  directory "/tmp/private_code/.ssh" do
    owner provider.app_name
    recursive true
  end

  cookbook_file "/tmp/private_code/deploy-ssh-wrapper.sh" do
    source "ssh/deploy-ssh-wrapper.sh"
    owner provider.app_name
    mode 0700
  end

  cookbook_file "/tmp/private_code/.ssh/id_deploy" do
    source "ssh/id_deploy"
    owner provider.app_name
    mode 0600
  end
end

def configure_delayed_job
  provider = self
  environment_variables = environment_variables('delayed_job')

  if provider.delayed_job?
    template "/etc/monit/conf.d/delayed_job.#{provider.app_name}.conf" do
      source "delayed_job.monitrc.erb"
      owner "root"
      group "root"
      mode 0644
      variables({
        :app_name => provider.app_name,
        :env => provider.environment_name,
        :worker_count => provider.delayed_job_worker_count,
        :worker_name => "#{provider.app_name}_delayed_job",
        :environment_variables => environment_variables
      })
      notifies :restart, "service[monit]"
    end
  end
end

def deploy_it
  provider = self
  deploy_to = "/var/www/#{provider.app_name}"
  shared_dir = "#{deploy_to}/shared"
  environment_variables = environment_variables('chef')

  directory shared_dir do
    owner provider.app_name
    group provider.app_name
  end

  %W{assets bundle pids sockets log system config}.each do |dir|
    directory "#{shared_dir}/#{dir}" do
      owner provider.app_name
      group provider.app_name
    end
  end

  template "#{shared_dir}/config/unicorn.rb" do
    source "unicorn.rb.erb"
    owner provider.app_name
    group provider.app_name
    variables(
      :environment => provider.environment_name,
      :name => provider.app_name,
      :environment_variables => environment_variables
    )
  end

  deploy_revision deploy_to do
    action provider.action
    repo provider.repo
    revision provider.revision
    user provider.app_name
    group provider.app_name
    migrate false #we need some environment variables so we'll do it ourselves before restart
    ssh_wrapper "/tmp/private_code/deploy-ssh-wrapper.sh"
    environment("RAILS_ENV" => provider.environment_name)
    shallow_clone true
    symlinks(
      "assets" => "public/assets",
      "pids" => "tmp/pids",
      "sockets" => "tmp/sockets",
      "log" => "log",
      "system" => "public/system",
      "config/unicorn.rb" => "config/unicorn.rb"
    )
    symlink_before_migrate({})

    before_restart do
      ruby_build_ruby provider.ruby_version

      gem_package 'bundler' do
        gem_binary "#{provider.ruby_home}/bin/gem"
      end

      execute "bundle install --path #{deploy_to}/shared/bundle --deployment --without development test" do
        cwd release_path
        user provider.app_name
        environment environment_variables
      end

      execute "bundle exec rake RAILS_ENV=#{provider.environment_name} RAILS_GROUPS=assets assets:precompile:primary" do
        cwd release_path
        user provider.app_name
        environment environment_variables
      end

      execute "bundle exec rake RAILS_ENV=#{provider.environment_name} db:migrate db:seed --trace" do
        cwd release_path
        user provider.app_name
        environment environment_variables
      end
    end

    restart_command do
      execute "/etc/init.d/#{provider.app_name} restart" do
      end
    end

    after_restart do
      if provider.delayed_job?
        bash "monit-reload-restart" do
          user "root"
          code "monit reload && monit"

          provider.delayed_job_worker_count.times do |i|
            code "pidof delayed_job.#{i} | xargs --no-run-if-empty kill"
          end
        end
      end

      ruby_block "check deployed version" do
        block do
          all_output = `curl -kvH 'Host: #{provider.server_names.first}' http#{provider.ssl? ? 's' : ''}://localhost/version 2>&1`
          deployed_version = `curl -kH 'Host: #{provider.server_names.first}' http#{provider.ssl? ? 's' : ''}://localhost/version`
          raise "Deployed version #{release_slug}, but #{deployed_version} was returned\n#{all_output}" unless deployed_version.match(release_slug)
        end
      end
    end
  end
end

