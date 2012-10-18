begin
  require File.dirname(__FILE__) + '/../../../../spec/spec_helper'
rescue LoadError
  puts "You need to install rspec in your base app"
  exit
end

plugin_spec_dir = File.dirname(__FILE__)
ActiveRecord::Base.logger = Logger.new(plugin_spec_dir + "/debug.log")


require 'spec'
require 'spec/rails'

load File.expand_path(File.dirname(__FILE__) + '/../lib/json_rpc_client.rb')  # To get rid of the redefinition in laplace


class Hash
  
  def except(*keys)
    self.reject { |k,v| keys.include?(k || k.to_sym) }
  end
  
  def with(overrides = {})
    self.merge overrides
  end
  
  def only(*keys)
    self.reject { |k,v| !keys.include?( k || k.to_sym) }
  end
  
end

def stringify_symbols_in_hash(h)
  res = {}
  h.each do |k, v|
    res[k.to_s] = case v
                  when Hash then stringify_symbols_in_hash(v)
                  when Array then stringify_symbols_in_array(v)
                  else
                    v
                  end
  end
  res
end

def stringify_symbols_in_array(h)
  res = []
  h.each do |v|
    res << case v
           when Hash then stringify_symbols_in_hash(v)
           when Array then  stringify_symbols_in_array(v)
           else
             v
           end
  end
  res
end
