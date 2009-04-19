require File.dirname(__FILE__) + '/spec_helper'

class MyClass
  def self.uncached
    yield
  end
end

describe JobStep do
  
  before :all do        
    class FuBar < JsonRpcClient
      json_rpc_service 'http://localhost:8888/da_service', :no_auto_config => true, :retries => 2
    end
    @job = Job.new :tries => 2
  end
  
  
  it "should require a :do value" do
    (lambda { JobStep.new }).should raise_error(":do is mandatory for each job step")
  end
  
  it "should accept a string as a :do value and eval it" do
    JobStep.new(:do => '300 + 45').
            run(@job).should == 345
  end
  
  it "should accept a symbol as a :do value and send it as a message to the specified object" do
    instance = MyClass.new
    MyClass.should_receive(:find).with(24).and_return(instance)
    instance.should_receive(:foo).with(18, 0).and_return 10000018
    JobStep.new(:target_descriptor => [:_activerecord_object, "MyClass", 24], :do => :foo, :do_args => [18, 0]).
            run(@job).should == 10000018
  end
  
  it "should automatically substitute a :target instance argument with an instance descriptor" do
    instance = mock_model(MyClass)
    MyClass.should_receive(:find).with(24).and_return(instance)
    instance.should_receive(:kind_of?).with(ActiveRecord::Base).and_return(true)
    instance.should_receive(:[]).with(:id).and_return(24)
    instance.should_receive(:foo).with(18, 0).and_return 10000018
    js = JobStep.new(:target => instance, :do => :foo, :do_args => [18, 0])
    js.target.should == nil
    js.target_descriptor.should == [:_activerecord_object, "MyClass", 24]
    js.run(@job).should == 10000018
  end
  
  it "should automatically substitute a :target class argument with a class descriptor" do
    MyClass.should_receive(:foo).with(18, 0).and_return(12345)
    js = JobStep.new(:target => MyClass, :do => :foo, :do_args => [18, 0])
    js.target.should == nil
    js.target_descriptor.should == [:_class, "MyClass"]
    js.run(@job).should == 12345
  end
  
  it "should intercept retriable errors and give up after a specified number of tries" do
    FuBar.should_receive(:add).exactly(5).times.with(1,2,3).and_raise(JsonRpcClient::ServerTimeout)
    lambda { JobStep.new(:do => "FuBar.add(1,2,3)", :tries => 5).run(@job) }.
           should raise_error(JsonRpcClient::ServerTimeout)
  end

  it "should intercept retriable errors and give up after a number of tries specified in the job if not in the step" do
    FuBar.should_receive(:add).exactly(2).times.with(1,2,3).and_raise(JsonRpcClient::ServerTimeout)
    lambda { JobStep.new(:do => "FuBar.add(1,2,3)").run(@job) }.
           should raise_error(JsonRpcClient::ServerTimeout)
  end

  it "should intercept retriable errors and give up after three tries if nothing is specified anywhere" do
    FuBar.should_receive(:add).exactly(3).times.with(1,2,3).and_raise(JsonRpcClient::ServerTimeout)
    lambda { JobStep.new(:do => "FuBar.add(1,2,3)").run(Job.new(:tries => nil)) }.
           should raise_error(JsonRpcClient::ServerTimeout)
  end
  
  it "should invoke any rollback after a failed :do" do
    FuBar.should_receive(:add).twice.and_raise(JsonRpcClient::ServerTimeout)
    Kernel.should_receive(:puts).twice
    lambda { JobStep.new(:do => "FuBar.add(1,2,3)", :rollback => "Kernel.puts '2418'").run(@job) }.
           should raise_error(JsonRpcClient::ServerTimeout)
  end
  
  it "should also handle a symbol as a :rollback" do
    FuBar.should_receive(:add).twice.with(1,2,3).and_raise(JsonRpcClient::ServerTimeout)
    instance = mock_model(MyClass)
    instance.should_receive(:cleanup).twice.with(88,99).and_return(nil)
    lambda { JobStep.new(:target => instance, :do => "FuBar.add(1,2,3)", 
                                              :rollback => :cleanup, :rollback_args => [88,99]).run(@job) }.
           should raise_error(JsonRpcClient::ServerTimeout)
  end
  
  it "should stop processing of a step if a non-retriable error occurs in the :do method, but the :rollback should be performed before exiting" do
    FuBar.should_receive(:add).once.with(1,2,3).and_raise(RuntimeError)
    Kernel.should_receive(:puts).once
    lambda { JobStep.new(:do => "FuBar.add(1,2,3)", :rollback => "Kernel.puts '2418'").run(@job) }.
           should raise_error(RuntimeError)
  end
  
  it "should retry the :rollback if it fails due to a retriable error" do
    FuBar.should_receive(:add).once.with(1,2,3).and_raise(JsonRpcClient::ServerTimeout)
    FuBar.should_receive(:fixit).exactly(10).times.and_raise(JsonRpcClient::ServiceUnavailable)
    lambda { JobStep.new(:do => "FuBar.add(1,2,3)", :rollback => "FuBar.fixit", :tries => 10).run(@job) }.
           should raise_error(JsonRpcClient::ServiceUnavailable)
  end
  
  it "should stop processing of a step if a non-retriable error occurs in the :rollback method" do
    FuBar.should_receive(:add).once.with(1,2,3).and_raise(JsonRpcClient::ServerTimeout)
    FuBar.should_receive(:fixit).once.and_raise(RuntimeError)
    lambda { JobStep.new(:do => "FuBar.add(1,2,3)", :rollback => "FuBar.fixit", :tries => 10).run(@job) }.
           should raise_error(RuntimeError)
  end
  
  it "should signal an exception if an argument ActiveRecord object can't be found" do
    instance = mock_model(MyClass)
    MyClass.should_receive(:find).with(24).ordered.and_raise(ActiveRecord::RecordNotFound)
    instance.should_receive(:kind_of?).with(ActiveRecord::Base).and_return(true)
    instance.should_receive(:[]).with(:id).and_return(24)
    js = JobStep.new(:target => MyClass, :do => :foo, :do_args => [instance, 1, 2, 3])
    js.target_descriptor.should == [:_class, "MyClass"]
    js.do_args.should == [[:_activerecord_object, "MyClass", 24], 1, 2, 3]
    lambda { js.run(@job) }.should raise_error(ActiveRecord::RecordNotFound)
  end

end
