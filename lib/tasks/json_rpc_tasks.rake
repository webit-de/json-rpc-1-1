desc "Copies the local version of the json_rpc to the shared plugin for later submission to git"
task :json_rpc do
  from = RAILS_ROOT + '/vendor/plugins/json_rpc/*'
  to = File.expand_path RAILS_ROOT + '/../json_rpc/'
  `cp -Rf #{from} #{to}`
  puts "The json_rpc plugin has been updated. You must now submit the changes to git in the usual manner."
end
