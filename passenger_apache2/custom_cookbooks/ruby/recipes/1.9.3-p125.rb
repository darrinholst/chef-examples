include_recipe "ruby_build"

ruby_build_ruby "1.9.3-p125" do
  action      :install
  prefix_path "/usr/local"
end

gem_package "bundler" do
  gem_binary "/usr/local/bin/gem"
end

