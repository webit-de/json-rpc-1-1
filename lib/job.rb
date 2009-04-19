require 'timeout'

#
# This is the Job class.
#
class Job < OpenStruct
  
  #
  # When a Job is created, the steps are canonicalized into JobSteps if
  # specified simply as hashes. Thus readability for the user is maximized,
  # while object-orientation is maintained internally.
  #
  def initialize(*args)
    last = args[-1]
    if last.kind_of?(Hash) && !last[:do]
      raise "Specifying :steps as a job option is not allowed when passing step hashes." if last[:steps] && args.length > 1
      options = last
      args = args[0...-1]
    else
      options = {}
    end
    super(options.merge(:steps => (options[:steps] || args).collect { |step| step.kind_of?(Hash) ? JobStep.new(step) : step }))
    Job.convert_target(self) if on_failure
    self.failure_args = Job.encode_activerecord_objects(failure_args)
  end
  
  
  #
  # Examines the object for a target property. If one is found, converts it
  # to target_class and target_id for an instance, or to just target_class
  # for an object which is a class. Sets the target property to nil.
  #
  def self.convert_target(object)
    return unless object.target
    object.target_descriptor = encode_activerecord_object(object.target)
    object.target = nil
  end
  
  
  #
  # Convert an ActiveRecord instance or class to a descriptor array,
  # otherwise return the argument untouched.
  #
  def self.encode_activerecord_object(arg)
    return arg unless defined?(ActiveRecord::Base)
    if arg.kind_of?(ActiveRecord::Base)
      [:_activerecord_object, arg.class.to_s, arg[:id]]
    elsif arg.kind_of?(Class)
      [:_class, arg.to_s]
    else
      arg
    end
  end
  
  
  #
  # Take an argument list and convert all occurrences of ActiveRecord instances
  # to an array describing the class and id of the instance. This avoids storing
  # the entire object and any related objects in the db.
  #
  def self.encode_activerecord_objects(s)
    s ||= []
    return s unless defined?(ActiveRecord::Base)
    s.collect { |arg| encode_activerecord_object(arg) }
  end
  
  
  #
  # Reinstate an ActiveRecord instance or class if a descriptor is passed,
  # otherwise return the argument untouched.
  #
  def self.decode_activerecord_object(arg)
    if arg.kind_of?(Array) && arg.length == 3 && arg.first == :_activerecord_object
      marker, klass, oid = arg
      require(klass.underscore) unless Object.const_defined?(klass)
      ar_class = Object.const_get(klass)
      ar_class.uncached { ar_class.send(:find, oid) }
    elsif arg.kind_of?(Array) && arg.length == 2 && arg.first == :_class
      marker, klass = arg
      require(klass.underscore) unless Object.const_defined?(klass)
      Object.const_get(klass)
    else
      arg
    end
  end
  
  
  #
  # Take an argument list encoded by Job.encode_activerecord_objects and
  # reinstate any ActiveRecord instances from their descriptions.
  #
  def self.decode_activerecord_objects(s)
    return [] unless s
    s.collect { |arg| decode_activerecord_object(arg) }
  end
  
  
  #
  # This runs a job. The queue itself is passed as an arg, since we need to
  # access it for completing or abandoning the job.
  #
  def run(q)
    begin
      steps.each { |step| step.run(self) }
      q.complete self
    rescue Exception => e
      q.fail self
      if on_failure
        begin
          fresh_args = Job.decode_activerecord_objects(failure_args)
          receiver = Job.decode_activerecord_object(target_descriptor)
          receiver.send(on_failure, e, *fresh_args)
        rescue Exception => e
        end
      else
        log_exception(e)
      end
    end
  end
  
  
  #
  # Logs an exception
  #
  def log_exception(e)
    RAILS_DEFAULT_LOGGER.error "======================================================================"
    RAILS_DEFAULT_LOGGER.error "Enqueued job exception: #{e.to_s} (#{`hostname`.chomp}:#{Process.pid})"
    RAILS_DEFAULT_LOGGER.error "  :unordered   => #{unordered || 'false'}"
    RAILS_DEFAULT_LOGGER.error "  :synchronous => #{synchronous || 'false'}"
    RAILS_DEFAULT_LOGGER.error "#{steps.length} job step(s):"
    steps.each do |step|
      RAILS_DEFAULT_LOGGER.error "----------------------------------------------------------------------"
      RAILS_DEFAULT_LOGGER.error "  :target descriptor: #{step.target_descriptor.inspect}"
      RAILS_DEFAULT_LOGGER.error "  :do method:         #{step.do}"
      RAILS_DEFAULT_LOGGER.error "  :do_args:           #{step.do_args.inspect}"
      RAILS_DEFAULT_LOGGER.error "  :rollback method:   #{step.rollback}"
      RAILS_DEFAULT_LOGGER.error "  :rollback_args:     #{step.rollback_args.inspect}"
      RAILS_DEFAULT_LOGGER.error "  :tries:             #{step.tries}"
    end
    RAILS_DEFAULT_LOGGER.error "----------------------------------------------------------------------"
    if e.backtrace
      RAILS_DEFAULT_LOGGER.error "Backtrace:"
      e.backtrace.each { |line| RAILS_DEFAULT_LOGGER.error line }
    else
      RAILS_DEFAULT_LOGGER.error "No backtrace available"
    end
    RAILS_DEFAULT_LOGGER.error "======================================================================"
  end
    
end
