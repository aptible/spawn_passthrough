require 'spawn_passthrough/version'

module SpawnPassthrough
  # There are a few gotchas in spawning processes and passing through the
  # current FDs and signals:
  #
  # First, we cannot use Kernel.exec, because we need to return control to the
  # caller.
  #
  # Second, we need to somehow capture the exit status, because we assume the
  # caller cares.
  #
  # Third, we don't want to use a separate process group, because the caller
  # might be used non-interactively, and we want to let other processes signal
  # the caller and let this reach the subprocess we're spawning here.
  #
  # To do this, we have to handle interrutps as a signal, as opposed to handle
  # an Interrupt exception. The reason for this has to do with how Ruby's wait
  # is implemented (this happens in process.c's rb_waitpid). There are two main
  # considerations here:
  #
  # - It automatically resumes when it receives EINTR, so our control is pretty
  # high-level here.
  # - It handles interrupts prior to setting $? (this appears to have changed
  # between Ruby 2.2 and 2.3, perhaps the newer implementation behaves
  # differently).
  #
  # Unfortunately, this means that if we receive SIGINT while in
  # Process::wait2, then we never get access to SSH's exitstatus: Ruby throws a
  # Interrupt so we don't have a return value, and it doesn't set $?, so we
  # can't read it back there.
  #
  # Of course, we can't just call Proces::wait2 again, because at this point,
  # we've reaped our child.
  #
  # To solve this, we add our own signal handler on SIGINT, which simply
  # proxies SIGINT to SSH if we happen to have a different process group (which
  # shouldn't be the case), just to be safe and let users exit the CLI.
  #
  # This code was originally implemented for the Aptible CLI.
  def self.spawn_passthrough(command)
    redirection = { in: :in, out: :out, err: :err, close_others: true }
    pid = Process.spawn(*command, redirection)

    reset = Signal.trap('SIGINT') do
      # FIXME: If we're on Windows, we don't really know whether SSH
      # received SIGINT or not, so for now, we just ignore it.
      next if Gem.win_platform?

      begin
        # SSH should be running in our process group, which means that
        # if the user sends CTRL+C, we'll both receive it. In this
        # case, just ignore the signal and let SSH handle it.
        next if Process.getpgid(Process.pid) == Process.getpgid(pid)

        # If we get here, then oddly, SSH is not running in our process
        # group and yet we got the signal. In this case, let's simply
        # ignore it.
        Process.kill(:SIGINT, pid)
      rescue Errno::ESRCH
        # This could happen if SSH exited after receiving the SIGINT,
        # Ruby waited it, then ran our signal handler. In this case, we
        # don't need to do anything, so we proceed.
      end
    end

    begin
      _, status = Process.wait2(pid)
      return status.exited? ? status.exitstatus : 128 + status.termsig
    ensure
      Signal.trap('SIGINT', reset)
    end
  end
end
