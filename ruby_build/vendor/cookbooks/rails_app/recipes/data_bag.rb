bag = node['rails_app']['data_bag']

data_bag(bag).each do |name|
  rails_app name do
    data_bag_item(bag, name).raw_data.each do |k, v|
      send(k, v)
    end
  end
end

