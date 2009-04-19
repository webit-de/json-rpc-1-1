require File.dirname(__FILE__) + '/spec_helper'

describe "enqueue" do
  
  before :each do
    @oldq = $q
    $q = nil
  end
  
  after :each do
    $q.stop_worker
    File.delete $q.db.path
    $q = @oldq
  end
  

  it "should allocate a JobQueue if none was present" do
    enqueue(Job.new(:synchronous => true))
    $q.should be_an_instance_of(JobQueue)
  end
  
  it "should start a worker if none was started" do
    enqueue(Job.new)
    $q.worker_pid.should be_an_instance_of(Fixnum)
  end
  
  it "should execute a Job synchronously if the JobQueue was declared synchronous" do
    Kernel.should_receive(:puts).with(123)
    $q = JobQueue.new :synchronous => true
    enqueue(Job.new(:do => 'Kernel.puts 123'))
  end
  
  it "should execute a Job synchronously if the Job was declared synchronous" do
    Kernel.should_receive(:puts).with(123)
    enqueue(Job.new({:do => 'Kernel.puts 123'}, :synchronous => true))
  end
  
  it "should execute a Job asynchronously if neither the JobQueue nor the Job wasn't declared synchronous" do
    Kernel.should_not_receive(:puts).with(123)
    $q = JobQueue.new :synchronous => false
    $q.should_receive(:submit)
    enqueue(Job.new(:do => 'Kernel.puts 123'))
  end
    
end
