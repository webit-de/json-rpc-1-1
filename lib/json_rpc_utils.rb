#
# This is the interface to the execution queue
#
def enqueue(*args)
  #raise "enqueue() may not be called from within something which is already enqueued." if $q.parent_pid
  $q ||= JobQueue.new
  $q.start_worker unless $q.synchronous
  job = (args.length == 1 && args.first.kind_of?(Job)) ? args.first : Job.new(*args)
  ($q.synchronous || job.synchronous) ? job.run($q) : $q.submit(job)
  true
end
