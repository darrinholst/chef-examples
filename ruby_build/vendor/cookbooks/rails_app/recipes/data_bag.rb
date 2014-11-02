bag = node['rails_app']['data_bag']

apps = data_bag(bag).inject({}) do |memo, name|
  memo[name] = data_bag_item(bag, name).raw_data
  memo
end

apps.each do |app, config|
  rails_app app do
    config.each do |k, v|
      send(k, v)
    end
  end
end


