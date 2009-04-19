#
# This is the JobQueue class. It will be moved into the JSON-RPC plugin eventually.
#
# Interface:
#   Jobqueue.new(db_path)    returns a new JobQueue object which is the interface
#                            to the queue. The optional param db_path defines where
#                            the database file resides. It is created if it doesn't
#                            already exist and defaults to 
#                            "#{RAILS_ROOT}/db/json_rpc_queue/#{RAILS_ENV}.pstore".
#
# Instance methods
#   stats                    returns a hash of usage statistics.
#
#   jobs                     returns a hash of all job uids, queued or currently processing.
#                            The hash has keys for each category of job.
#
#   job(uuid)                returns the job of the given uuid.
#
#   hard_reset               resets the db. Job uuids will start over from 1.
#
#   submit(job)              submits a Job object for processing and gives it an uuid.
#
#   claim                    if there is a Job ready for processing, returns it.
#                            If not, or if a Job has been claimed but not completed,
#                            returns nil. This means that only one job at a time is
#                            processed.
#
#   complete(job)            when a claimed job has finished successfully, this method
#                            should always be called to let the next scheduled job
#                            be claimed.
#
#   fail(job)                when a claimed job has failed completely, this method
#                            should always be called to let the next scheduled job
#                            be claimed.
#
#   remove(job)              removes a Job from processing (aborting it). This is a
#                            semi-internal method which rarely should be used.
#
#   start_worker             starts an asynchronous worker task. Only one per Rails
#                            process is allowed (at this time): returns false if a
#                            worker process was already running. Returns true if one
#                            was actually started.
#
#   stop_worker              stops the asynchronous worker task. Returns true if
#                            a worker was stopped, false if not.
#

require 'openstruct'
require 'job'
require 'job_step'
require 'fileutils'


class JobQueue < OpenStruct
  
  require 'pstore'    # Our persistent storage handler
  include Spawn       # Helper plugin for managing forked processes
  
  
  #
  # Sets up the basic data in the PStore DB if not already initialised.
  #
  def initialize(options={})
    super({:db_path => "#{RAILS_ROOT}/db/json_rpc_queue/#{RAILS_ENV}.pstore",
           :worker_sleep => 0.1,
           :synchronous => false}.merge(options))
    dbp = File.expand_path db_path
    FileUtils.mkdir_p(File.dirname(dbp))
    self.db = PStore.new dbp
    self.db.transaction do
      db[:waiting_unordered] = db[:waiting_unordered] || []
      db[:waiting_ordered] = db[:waiting_ordered] || []
      db[:processing_ordered] = db[:processing_ordered]
      db[:processing_unordered] = db[:processing_unordered] || []
      db[:next_uuid] = db[:next_uuid] || 1
      db[:jobs_completed] = db[:jobs_completed] || 0
      db[:jobs_failed] = db[:jobs_failed] || 0
      db[:total_time_used] = db[:total_time_used] || 0.0
      db[:max_processing_time] = db[:max_processing_time] || -10000000000000000.0
      db[:min_processing_time] = db[:min_processing_time] || 10000000000000000.0
      db[:workers_in_touch] = db[:workers_in_touch] || []
    end
    self.parent_pid = nil
    self.worker_pid = nil
    self.detached_checker_thread = nil
  end
  
  
  #
  # This returns a simple hash of statistical information.
  #
  def stats
    self.db.transaction do
      { :jobs_waiting_unordered => db[:waiting_unordered].length,
        :jobs_waiting_ordered => db[:waiting_ordered].length,
        :jobs_processing_ordered => db[:processing_ordered] ? 1 : 0,
        :jobs_processing_unordered => db[:processing_unordered].length,
        :next_uuid => db[:next_uuid],
        :last_job_submitted_at => db[:last_job_submitted_at],
        :last_job_completed_at => db[:last_job_completed_at],
        :jobs_completed => db[:jobs_completed],
        :jobs_failed => db[:jobs_failed],
        :total_time_used => db[:total_time_used],
        :average_processing_time => (db[:jobs_completed] == 0 ? 0.0 : db[:total_time_used] / db[:jobs_completed]),
        :max_processing_time => db[:max_processing_time],
        :min_processing_time => db[:min_processing_time],
        :worker_pid => worker_pid,
        :workers_in_touch => db[:workers_in_touch]
      }
    end
  end
  
  
  #
  # This returns a categorized has of all jobs in the queue.
  #
  def jobs
    self.db.transaction do
      { :jobs_waiting_unordered => db[:waiting_unordered],
        :jobs_waiting_ordered => db[:waiting_ordered],
        :jobs_processing_ordered => db[:processing_ordered] ? [db[:processing_ordered]] : [],
        :jobs_processing_unordered => db[:processing_unordered]
      }
    end
  end
  
  
  #
  # This returns a specific job, given its uuid.
  #
  def job(uuid)
    return nil unless uuid.kind_of?(Integer)
    self.db.transaction { db[uuid] }
  end
  
  
  #
  # Kills everything in the DB and resets it to its empty state.
  #
  def hard_reset
    self.db.transaction do
      db.roots.each { |x| db.delete x }
      db[:waiting_ordered] = []
      db[:waiting_unordered] = []
      db[:processing_ordered] = nil
      db[:processing_unordered] = []
      db[:next_uuid] = 1
      db[:jobs_completed] = 0
      db[:jobs_failed] = 0
      db[:total_time_used] = 0.0
      db[:max_processing_time] = -10000000000000000.0
      db[:min_processing_time] = 10000000000000000.0
      db[:workers_in_touch] = []
    end
    true
  end
  
  
  #
  # This method can only be called from within a transaction. It
  # returns the next UUID to be used for a Job.
  #
  def next_uuid
    uuid = db[:next_uuid]
    db[:next_uuid] += 1
    uuid
  end
  
  
  #
  # Enqueues a job for processing.
  #
  def submit(job)
    self.db.transaction do
      job.uuid = next_uuid
      job.submitted_at = Time.now.utc
      db[:last_job_submitted_at] = job.submitted_at
      if job.unordered
        db[:waiting_unordered] << job.uuid
      else
        db[:waiting_ordered] << job.uuid
      end
      db[job.uuid] = job
      job
    end
  end
  
  
  #
  # Removes a Job from the queue. No checks are made that the
  # Job exists, has completed, etc. 
  #
  def remove(job)
    self.db.transaction do
      # Ordered jobs
      waiting_ordered = db[:waiting_ordered]
      waiting_ordered.delete job.uuid
      db[:waiting_ordered] = waiting_ordered
      # Unordered jobs
      waiting_unordered = db[:waiting_unordered]
      waiting_unordered.delete job.uuid
      db[:waiting_unordered] = waiting_unordered
      # Ordered job being processed
      db[:processing_ordered] = nil
      db.delete job.uuid
      # Unordered job being processed
      processing_unordered = db[:processing_unordered]
      processing_unordered.delete job.uuid
      db[:processing_unordered] = processing_unordered
      # Remove the job itself from the db
      db.delete job.uuid
      job
    end
  end
  
  
  #
  # Returns the next Job to be processed, if there is one available.
  # Nil will be returned if a Job already is being processed (processing
  # is strictly sequential and pipelined) or no Job is available.
  #
  def claim(host=nil, pid=nil)
    self.db.transaction do
      record_worker_in_touch(host, pid) if host && pid
      job = nil
      if db[:processing_ordered]
        # If there is an ordered job being processed, choose an unordered job if there is one
        waiting_unordered = db[:waiting_unordered]
        return nil if waiting_unordered.length == 0
        job = db[waiting_unordered.first]
        db[:waiting_unordered] = waiting_unordered[1..-1]
        db[:processing_unordered] << job.uuid
      elsif ((waiting_ordered = db[:waiting_ordered]) != [])
        # If no ordered job is being processed, but there is an ordered job waiting, choose it
        job = db[waiting_ordered.first]
        db[:waiting_ordered] = waiting_ordered[1..-1]
        db[:processing_ordered] = job.uuid
      elsif ((waiting_unordered = db[:waiting_unordered]) != [])
        # If no ordered jobs were waiting, choose an unordened one, if available
        job = db[waiting_unordered.first]
        db[:waiting_unordered] = waiting_unordered[1..-1]
        db[:processing_unordered] << job.uuid
      end
      # Have we selected a job? If so, adorn it
      return nil unless job
      job.begun_at = Time.now.utc
      db[job.uuid] = job
      job
    end
  end


  #
  # When a job has been processed successfully, this method
  # should be called to remove it from the queues and to allow the next Job
  # to be run. This method also updates the running statistics.
  #
  def complete(job)
    t = Time.now.utc
    elapsed = t - job.begun_at if job.begun_at
    remove job
    job.completed_at = t
    job.elapsed_seconds = elapsed if job.begun_at
    self.db.transaction do 
      db[:jobs_completed] += 1
      db[:last_job_completed_at] = t 
      db[:total_time_used] += elapsed if job.begun_at
      db[:max_processing_time] = elapsed if job.begun_at && elapsed > db[:max_processing_time]
      db[:min_processing_time] = elapsed if job.begun_at && elapsed < db[:min_processing_time]
    end
    job
  end
  
  
  #
  # When a job has failed completely and has been abandoned, this method
  # should be called to remove it from the queues and to allow the next Job
  # to be run. This method also updates the running statistics.
  #
  def fail(job)
    remove job
    self.db.transaction do
      db[:jobs_failed] += 1
    end
  rescue Exception => e
  end
  
    
  #
  # Forks a worker process, unless one is already active
  #
  def start_worker
    return false if parent_pid
    #raise "This worker process tried to start a worker process. BAAAAD idea." if parent_pid
    return false if worker_pid
    self.parent_pid = Process.pid
    self.worker_pid, self.detached_checker_thread = spawn do
      Signal.trap("INT", "IGNORE")
      worker_loop(`hostname`.chomp, Process.pid, parent_pid)
    end
    Signal.trap("EXIT") { stop_worker }
    true
  end

  #
  # Stops the worker process, if there is one active
  #
  def stop_worker
    return false unless worker_pid
    unregister_worker(`hostname`.chomp, worker_pid) # This should really be done from within the worker_loop
    Thread.kill("TERM", detached_checker_thread) rescue nil
    self.detached_checker_thread = nil
    Process.kill("TERM", worker_pid) rescue nil
    self.worker_pid = nil
    true
  end
  
  
  private
  
    #
    # This is the main worker event loop  
    #
    def worker_loop(host, pid, ppid)
      loop do
        (job = claim(host, pid)) ? job.run(self) : no_job_available
        break unless (Process.getpgid(ppid) rescue nil)  # Die if the parent is gone
      end
    end
  
    
    #
    # When there is no job available, we sleep for a fraction of a second,
    # otherwise the worker will consume too much processor power.
    #
    def no_job_available
      sleep(worker_sleep || 0.1) rescue sleep(0.1)
    end
    
    
    #
    # This is called when a worker has been in touch. It updates the
    # db[:workers_in_touch] array, creating or updating the entry for
    # the worker, and pruning away workers which haven't been in touch
    # lately. (The pruning would better be done in a separate thread.)
    # NB: this method can only be called from within a PStore transaction.
    #
    def record_worker_in_touch(host, pid)
      return unless host && pid
      wit = db[:workers_in_touch]
      # Find the worker. If found, update its time. If not found, create an entry.
      if (x = wit.find { |y| y[0] == host && y[1] == pid })
        x[2] = Time.now.utc
      else
        wit << [host, pid, Time.now.utc]
      end
      # Prune away workers which haven't been in touch during the last minute
      db[:workers_in_touch] = wit.delete_if { |x| x[2] <= Time.now.utc - 1.minute }
    end
    
    
    #
    # Removes a worker from the "in touch" list. This method must NOT be
    # called from within a PStore transaction.
    #
    def unregister_worker(host, pid)
      $q.db.transaction do
        db[:workers_in_touch] = db[:workers_in_touch].delete_if { |y| y[0] == host && y[1] == pid }
      end
    end
      
end
