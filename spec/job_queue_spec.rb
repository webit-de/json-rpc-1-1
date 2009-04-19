require File.dirname(__FILE__) + '/spec_helper'

describe JobQueue do
  
  before :all do
    @q = JobQueue.new
    @q.stop_worker        # Just in case there is one running by default (shouldn't be)
  end
  
  before :each do
    @q.hard_reset
  end
  
  after :all do
    @q.stop_worker
    File.delete @q.db.path
  end
  
  
  it "should create a default db" do
    File.basename(@q.db.path).should == "#{RAILS_ENV}.pstore"
  end
  
  it "should be queriable for statistics" do
    @q.stats.should be_an_instance_of(Hash)
  end
  
  it "should add ordered jobs to the ordered queue" do
    @q.submit Job.new
    @q.submit Job.new
    @q.submit Job.new
    @q.stats[:jobs_waiting_ordered].should == 3
  end
  
  it "should add unordered jobs to the unordered queue" do
    @q.submit Job.new(:unordered => true)
    @q.submit Job.new(:unordered => true)
    @q.submit Job.new(:unordered => true)
    @q.stats[:jobs_waiting_unordered].should == 3
  end
  
  it "should be possible to do a hard reset" do
    @q.submit Job.new
    @q.submit Job.new
    @q.submit Job.new(:unordered => true)
    @q.submit Job.new(:unordered => true)
    @q.submit Job.new
    @q.submit Job.new(:unordered => true)
    @q.claim
    @q.stats[:jobs_waiting_unordered].should == 3
    @q.stats[:jobs_waiting_ordered].should == 2
    @q.stats[:jobs_processing_ordered].should == 1
    @q.hard_reset
    @q.stats[:jobs_waiting_unordered].should == 0
    @q.stats[:jobs_waiting_ordered].should == 0
    @q.stats[:job_processing_ordered].should == nil
  end
  
  it "should be possible to remove an ordered job from the queue" do
    @q.submit Job.new
    j2 = @q.submit Job.new
    @q.submit Job.new(:unordered => true)
    @q.submit Job.new(:unordered => true)
    @q.submit Job.new
    @q.submit Job.new(:unordered => true)
    @q.stats[:jobs_waiting_ordered].should == 3
    @q.db.transaction do 
      @q.db[:waiting_ordered].should == [1, 2, 5] 
      @q.db[:waiting_unordered].should == [3, 4, 6] 
      end
    @q.remove j2
    @q.db.transaction do 
      @q.db[:waiting_ordered].should == [1, 5]
      @q.db[:waiting_unordered].should == [3, 4, 6]
    end
  end
  
  it "should be possible to remove an unordered job from the queue" do
    @q.submit Job.new
    @q.submit Job.new
    @q.submit Job.new(:unordered => true)
    j4 = @q.submit Job.new(:unordered => true)
    @q.submit Job.new
    @q.submit Job.new(:unordered => true)
    @q.stats[:jobs_waiting_ordered].should == 3
    @q.db.transaction do 
      @q.db[:waiting_ordered].should == [1, 2, 5] 
      @q.db[:waiting_unordered].should == [3, 4, 6] 
      end
    @q.remove j4
    @q.db.transaction do 
      @q.db[:waiting_ordered].should == [1, 2, 5]
      @q.db[:waiting_unordered].should == [3, 6]
    end
  end
  
  it "should claim nothing if both queues are empty" do
    @q.claim.should == nil
  end
  
  it "should claim the first ordered job if no ordered job is being processed and there are both ordered and unordered jobs waiting" do
    @q.submit Job.new
    @q.submit Job.new
    @q.submit Job.new(:unordered => true)
    @q.submit Job.new(:unordered => true)
    @q.submit Job.new
    @q.submit Job.new(:unordered => true)
    claimed_job = @q.claim
    claimed_job.uuid.should == 1
    @q.db.transaction do 
      @q.db[:waiting_unordered].should == [3, 4, 6]
      @q.db[:waiting_ordered].should == [2, 5]
      @q.db[:processing_ordered].should == 1
    end
  end
  
  it "should claim an unordered job if there is an ordered job being processed and there is an unordered one waiting" do
    @q.submit Job.new
    @q.submit Job.new
    @q.submit Job.new(:unordered => true)
    @q.submit Job.new(:unordered => true)
    @q.submit Job.new
    @q.submit Job.new(:unordered => true)
    claimed_job_1 = @q.claim
    claimed_job_1.uuid.should == 1
    claimed_job_3 = @q.claim
    claimed_job_3.uuid.should == 3
    claimed_job_4 = @q.claim
    claimed_job_4.uuid.should == 4
    @q.db.transaction do 
      @q.db[:waiting_unordered].should == [6]
      @q.db[:waiting_ordered].should == [2, 5]
      @q.db[:processing_ordered].should == 1
      @q.db[:processing_unordered].should == [3, 4]
    end
  end
  
  it "should not be possible to claim another ordered job while one is being processed" do
    @q.submit(Job.new)
    @q.submit(Job.new)
    @q.submit(Job.new)
    @q.stats[:jobs_waiting_ordered].should == 3
    @q.db.transaction { @q.db[:waiting_ordered].should == [1, 2, 3] }
    claimed_job = @q.claim
    @q.claim.should == nil
  end
  
  it "should be possible to remove an ordered job being processed and then claim another one" do
    @q.submit(Job.new)
    @q.submit(Job.new)
    @q.submit(Job.new)
    @q.stats[:jobs_waiting_ordered].should == 3
    @q.db.transaction { @q.db[:waiting_ordered].should == [1, 2, 3] }
    claimed_job = @q.claim
    @q.remove claimed_job
    @q.claim.should_not == nil
  end
  
  it "should add a uuid and the time enqueued to each ordered job and update the queue statistics accordingly" do
    job = Job.new
    job.uuid.should == nil
    job.submitted_at.should == nil
    @q.stats[:last_job_submitted_at].should == nil
    @q.submit job
    job.uuid.should_not == nil
    job.submitted_at.should be_an_instance_of(Time)
    @q.stats[:last_job_submitted_at].should be_an_instance_of(Time)
  end
    
  it "should add a uuid and the time enqueued to each unordered job and update the queue statistics accordingly" do
    job = Job.new(:unordered => true)
    job.uuid.should == nil
    job.submitted_at.should == nil
    @q.stats[:last_job_submitted_at].should == nil
    @q.submit job
    job.uuid.should_not == nil
    job.submitted_at.should be_an_instance_of(Time)
    @q.stats[:last_job_submitted_at].should be_an_instance_of(Time)
  end
    
  it "should be possible to signal an ordered job as completed which should make it possible to claim another ordered one" do
    @q.submit(Job.new)
    @q.submit(Job.new)
    claimed_job_1 = @q.claim
    @q.claim.should == nil
    @q.complete claimed_job_1
    claimed_job_2 = @q.claim
    claimed_job_2.should_not == nil
    claimed_job_2.uuid.should_not == claimed_job_1.uuid
    @q.complete claimed_job_2
    @q.claim.should == nil
  end
  
  it "should be possible to signal an unordered job as completed" do
    @q.submit(Job.new(:unordered => true))
    @q.submit(Job.new(:unordered => true))
    claimed_job_1 = @q.claim
    claimed_job_1.uuid.should == 1
    claimed_job_2 = @q.claim
    claimed_job_2.uuid.should == 2
    @q.db.transaction do 
      @q.db[:waiting_unordered].should == []
      @q.db[:waiting_ordered].should == []
      @q.db[:processing_ordered].should == nil
      @q.db[:processing_unordered].should == [1, 2]
    end
    @q.complete claimed_job_1
    @q.db.transaction do 
      @q.db[:waiting_unordered].should == []
      @q.db[:waiting_ordered].should == []
      @q.db[:processing_ordered].should == nil
      @q.db[:processing_unordered].should == [2]
    end
    @q.complete claimed_job_2
    @q.db.transaction do 
      @q.db[:waiting_unordered].should == []
      @q.db[:waiting_ordered].should == []
      @q.db[:processing_ordered].should == nil
      @q.db[:processing_unordered].should == []
    end
  end
  
  it "should update a completed job and also update its own statistics" do
    @q.submit(Job.new)
    job = @q.claim
    job.completed_at.should == nil
    job.elapsed_seconds.should == nil
    @q.db.transaction do
      @q.db[:jobs_completed].should == 0
      @q.db[:last_job_completed_at].should == nil
      @q.db[:total_time_used].should == 0.0
      @q.db[:max_processing_time].should == -1.0e+16
      @q.db[:min_processing_time].should == 1.0e+16
    end
    @q.complete job
    job.completed_at.should be_an_instance_of(Time)
    job.elapsed_seconds.should be_an_instance_of(Float)
    @q.db.transaction do
      @q.db[:jobs_completed].should == 1
      @q.db[:last_job_completed_at].should be_an_instance_of(Time)
      @q.db[:total_time_used].should be_an_instance_of(Float)
      @q.db[:max_processing_time].should_not == -1.0e+16
      @q.db[:min_processing_time].should_not == 1.0e+16
    end
  end

  it "should update a failed job and also update its own statistics" do
    @q.submit(Job.new)
    job = @q.claim
    job.completed_at.should == nil
    job.elapsed_seconds.should == nil
    @q.db.transaction do
      @q.db[:jobs_completed].should == 0
      @q.db[:jobs_failed].should == 0
      @q.db[:last_job_completed_at].should == nil
      @q.db[:total_time_used].should == 0.0
      @q.db[:max_processing_time].should == -1.0e+16
      @q.db[:min_processing_time].should == 1.0e+16
    end
    @q.fail job
    job.completed_at.should == nil
    job.elapsed_seconds.should == nil
    @q.db.transaction do
      @q.db[:jobs_completed].should == 0
      @q.db[:jobs_failed].should == 1
      @q.db[:last_job_completed_at].should == nil
      @q.db[:total_time_used].should == 0.0
      @q.db[:max_processing_time].should == -1.0e+16
      @q.db[:min_processing_time].should == 1.0e+16
    end
  end

end

