require 'spec_helper'
require 'tmpdir'

describe SpawnPassthrough do
  it 'has a version number' do
    expect(SpawnPassthrough::VERSION).not_to be nil
  end

  describe '.spawn_passthrough' do
    let(:bins) { File.expand_path('../script', __FILE__) }
    let(:ruby) { Gem.win_platform? ? 'ruby.exe' : 'ruby' }
    let(:wrapper) { [ruby, File.join(bins, 'wrapper')] }
    let(:exit_with) { [ruby, File.join(bins, 'exit-with')] }
    let(:sigint) { [ruby, File.join(bins, 'pid-signal')] }
    let(:setpgid) { [ruby, File.join(bins, 'setpgid')] }

    let(:cleanup) { [] }

    after do
      cleanup.each do |pid|
        begin
          Process.kill(:SIGKILL, -pid)
        rescue Errno::ESRCH, Errno::EINVAL
        end
      end
    end

    def spawn_with_cleanup(*args)
      kw = Gem.win_platform? ? { new_pgroup: true } : { pgroup: true }
      Process.spawn(*args, **kw).tap { |pid| cleanup << pid }
    end

    def wait_for_file(file)
      50.times do
        return if File.exist?(file)
        sleep 0.1
      end

      raise "File never showed up: #{file}"
    end

    def wait_for_pid(pid, timeout = 5)
      (timeout * 10).times do
        _, status = Process.wait2(pid, Process::WNOHANG)
        return status if status
        sleep 0.1
      end

      raise "PID never exited: #{pid}"
    end

    [0, 1].each do |c|
      it "returns the command exit code (#{c})" do
        pid = spawn_with_cleanup(*wrapper, *exit_with, c.to_s)
        status = wait_for_pid(pid)
        expect(status.exitstatus).to eq(c)
      end
    end

    context 'signals' do
      # Don't run these on Windows: sending SIGINT will send it to the entire
      # console group, which includes the process running the specs.
      before { skip 'Windows' if Gem.win_platform? }

      it 'returns 128 + signal number when signalled' do
        Dir.mktmpdir do |dir|
          pid_file = File.join(dir, 'pid')
          pid = spawn_with_cleanup(*wrapper, *sigint, pid_file)
          wait_for_file(pid_file)

          child_pid = Integer(File.read(pid_file).chomp)
          Process.kill('INT', child_pid)

          status = wait_for_pid(pid)

          if Gem.win_platform?
            expect(status.exitstatus).not_to eq(0)
          else
            expect(status.exitstatus).to eq(128 + Signal.list.fetch('INT'))
          end
        end
      end

      it 'does not proxy SIGINT when part of the same process group' do
        Dir.mktmpdir do |dir|
          pid_file = File.join(dir, 'pid')
          pid = spawn_with_cleanup(*wrapper, *sigint, pid_file)
          wait_for_file(pid_file)

          child_pid = Integer(File.read(pid_file).chomp)
          expect(Process.getpgid(child_pid)).to eq(Process.getpgid(pid))
          Process.kill('INT', pid)

          expect { wait_for_pid(pid, 2) }.to raise_error(/never exited/im)
        end
      end

      it 'proxies SIGINT when process groups are different' do
        Dir.mktmpdir do |dir|
          pid_file = File.join(dir, 'pid')
          pid = spawn_with_cleanup(*wrapper, *setpgid, *sigint, pid_file)
          wait_for_file(pid_file)

          child_pid = Integer(File.read(pid_file).chomp)
          expect(Process.getpgid(child_pid)).not_to eq(Process.getpgid(pid))
          Process.kill('INT', pid)

          status = wait_for_pid(pid)
          expect(status.exitstatus).to eq(128 + Signal.list.fetch('INT'))
        end
      end

      it 'does not crash when receiving SIGINT concurrently' do
        Dir.mktmpdir do |dir|
          pid_file = File.join(dir, 'pid')
          pid = spawn_with_cleanup(*wrapper, *sigint, pid_file)
          wait_for_file(pid_file)

          child_pid = Integer(File.read(pid_file).chomp)
          expect(Process.getpgid(child_pid)).to eq(Process.getpgid(pid))
          Process.kill('INT', -pid)

          status = wait_for_pid(pid)
          expect(status.exitstatus).to eq(128 + Signal.list.fetch('INT'))
        end
      end
    end
  end
end
