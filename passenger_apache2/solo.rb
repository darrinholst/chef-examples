chef_dir = File.expand_path(File.dirname(__FILE__))
cookbook_path [File.join(chef_dir, "cookbooks"), File.join(chef_dir, "custom_cookbooks")]

