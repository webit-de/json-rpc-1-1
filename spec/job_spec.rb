require File.dirname(__FILE__) + '/spec_helper'


class MyClass
  def self.find(n)
    new
  end
  def self.uncached
    yield
  end
end


describe Job do
  
  before :all do
    @q = JobQueue.new
    @q.stop_worker        # Just in case there is one running by default (shouldn't be)
  end
  
  after :all do
    @q.stop_worker        # Just in case there is one running by default (shouldn't be)
    File.delete @q.db.path
  end
  
  
  it "should execute each step in order" do
    Kernel.should_receive(:puts).with("one").ordered
    Kernel.should_receive(:puts).with("two").ordered
    Kernel.should_receive(:puts).with("three").ordered
    Job.new(:begun_at => Time.now.utc,
            :steps => [JobStep.new(:do => 'Kernel.puts "one"'),
                       JobStep.new(:do => 'Kernel.puts "two"'),
                       JobStep.new(:do => 'Kernel.puts "three"')]).run(@q)
  end
  
  it "should convert a hash step to a proper JobStep object when created" do
    Kernel.should_receive(:puts).with("one").ordered
    Kernel.should_receive(:puts).with("two").ordered
    Kernel.should_receive(:puts).with("three").ordered
    Job.new(:begun_at => Time.now.utc,
            :steps => [{:do => 'Kernel.puts "one"'},
                       {:do => 'Kernel.puts "two"'},
                       {:do => 'Kernel.puts "three"'}]).run(@q)
  end
  
  it "should handle being passed a series of step hashes as arguments" do
    job = Job.new({:do => 'Kernel.puts "one"'},
                  {:do => 'Kernel.puts "two"'},
                  {:do => 'Kernel.puts "three"'})
    job.steps.length.should == 3
  end
  
  it "should handle being passed job options at the end" do
    job = Job.new({:do => 'Kernel.puts "one"'},
                  {:do => 'Kernel.puts "two"'},
                  {:do => 'Kernel.puts "three"'},
                  :tries => 100)
    job.steps.length.should == 3
    job.tries.should == 100
  end
  
  it "should protest if trying to pass both step hashes and a :steps job option" do
    lambda { Job.new({:do => 'Kernel.puts "one"'},
                     {:do => 'Kernel.puts "two"'},
                     {:do => 'Kernel.puts "three"'},
                     :tries => 100, :steps => []) }.
            should raise_error(Exception)
  end
  
  it "should convert a failure :target to a target descriptor" do
    instance = MyClass.new
    instance.should_receive(:kind_of?).with(ActiveRecord::Base).and_return(true)
    instance.should_receive(:[]).with(:id).and_return(24)
    job = Job.new({:do => 'whatever'}, :on_failure => :something, :target => instance)
    job.target_descriptor.should == [:_activerecord_object, "MyClass", 24]
  end
  
  it "should call a failure handler, if one is specified" do
    instance = MyClass.new
    instance.should_receive(:kind_of?).with(ActiveRecord::Base).and_return(true)
    MyClass.should_receive(:find).with(24).and_return(instance)
    instance.should_receive(:[]).with(:id).and_return(24)
    instance.should_receive(:my_fail_handler).with(an_instance_of(Exception), 1, 2, 3)
    job = Job.new({:do => "---ffff---"}, 
                  :on_failure => :my_fail_handler, :target => instance, :failure_args => [1, 2, 3],
                  :begun_at => Time.now.utc)
    job.target_descriptor.should == [:_activerecord_object, "MyClass", 24]
    job.run(@q)
  end
  
  it "should handle class method failure handlers" do
    MyClass.should_receive(:my_fail_handler).with(an_instance_of(Exception), 1, 2, 3)
    job = Job.new({:do => "---ffff---"}, 
                   :on_failure => :my_fail_handler, :target => MyClass, :failure_args => [1, 2, 3],
                   :begun_at => Time.now.utc)
    job.target_descriptor.should == [:_class, "MyClass"]
    job.run(@q)
  end
  
  it "should not call a failure handler, if none is specified" do
    instance = MyClass.new
    MyClass.should_not_receive(:find).with(24).and_return(instance)
    instance.should_not_receive(:[]).with(:id).and_return(24)
    instance.should_not_receive(:my_fail_handler).with(an_instance_of(Exception), 1, 2, 3)
    Job.new({:do => "rrtutrtryutyruyt"}, :begun_at => Time.now.utc).run(@q)
  end
  
  it "should not call a failure handler, if one is specified but the operation doesn't fail" do
    MyClass.should_receive(:foo)
    instance = MyClass.new
    instance.should_receive(:kind_of?).with(ActiveRecord::Base).and_return(true)
    MyClass.should_not_receive(:find).with(24).and_return(instance)
    instance.should_receive(:[]).with(:id).and_return(24)
    instance.should_not_receive(:my_fail_handler).with(an_instance_of(Exception), 1, 2, 3)
    Job.new({:do => "MyClass.foo"}, 
            :on_failure => :my_fail_handler, :target => instance, :failure_args => [1, 2, 3],
            :begun_at => Time.now.utc).run(@q)
  end
  
  # it "should require the failure target instance to be an ActiveRecord object" do
  #   lambda { Job.new({:do => '1+2+3'}, :on_failure => :my_fail_handler, :target => "wrooong") }.
  #          should raise_error(":target instance must have an id and be findable")
  # end
  
end


