#
# This is the JobStep class.
#
class JobStep < OpenStruct
  
  def initialize(args={})
    super
    unless self.do
      raise ":do is mandatory for each job step"
    end
    Job.convert_target(self)
    self.do_args = Job.encode_activerecord_objects(do_args)
    self.rollback_args = Job.encode_activerecord_objects(rollback_args)
  end
  
  
  #
  # This executes the JobStep. The job itself is passed as a parameter,
  # to allow exception logic to access data common to all JobSteps.
  #
  def run(job)
    remaining_tries = tries || job.tries || 3
    begin
      execute self.do, do_args
    rescue JsonRpcClient::RetriableError => e
      remaining_tries -= 1
      rollback_with_retries(job)
      retry if remaining_tries > 0
      raise e
    rescue Exception => e
      rollback_with_retries(job)
      raise e
    end
  end
  
  
  #
  # This executes the :do or :rollback code. The target object is cached.
  # The +args+ arg may be nil, in which case no args will be sent to the symbol thing.
  #
  def execute(thing, args)
    case thing
    when String then eval thing
    when Symbol then 
      fresh_args = Job.decode_activerecord_objects(args)
      Job.decode_activerecord_object(target_descriptor).send(thing, *fresh_args)
    when NilClass then nil
    else
      raise "Unsupported :do or :rollback type: '#{thing}'"
    end
  end
  
  
  #
  # This executes the rollback, with retries
  #
  def rollback_with_retries(job)
    remaining_tries = tries || job.tries || 3
    begin
      execute rollback, rollback_args
    rescue JsonRpcClient::RetriableError => e
      remaining_tries -= 1
      retry if remaining_tries > 0
      raise e
    end
  end
  
end
