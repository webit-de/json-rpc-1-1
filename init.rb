# Include hook code here
require 'spawn/spawn'

require 'json/ext'
# require 'json/add/rails'
require 'ostruct'

require 'job'
require 'job_step'
require 'job_queue'
require 'json_rpc_client'
require 'json_rpc_service'
require 'json_rpc_utils'

require 'spawn/patches'
ActionController::Base.send :include, Spawn
if defined?(ActiveRecord)
  ActiveRecord::Base.send :include, Spawn
end
if defined?(ActiveRecord::Observer)
  ActiveRecord::Observer.send :include, Spawn
end

#
# If we're running a Rails version previous to 2.3.3, where
# the JSON parser has undergone substantial revision:
#
# This might be right or it might not: the default to_json
# method for strings encodes *all* Unicode characters using
# the "\uFFFF" syntax, which is unnecessary since the JSON
# spec explicitly states that Unicode characters are fully
# supported. Rails only uses UTF-8 and never decodes the 
# \uFFFF it creates (insert expletive here). Therefore, we 
# monkey patch String#to_json to not use the \uFFFF syntax 
# at all. This might have unforeseen side effects. We shall
# see.
#
unless "string".respond_to?(:as_json)
  class ::String
    def to_json(options = nil) #:nodoc:
      '"' + gsub(/[\010\f\n\r\t"\\><&]/) { |s| ActiveSupport::JSON::Encoding::ESCAPED_CHARS[s] } + '"'
    end
  end
end



ActionController::Base.send(:include, JsonRpcService)
