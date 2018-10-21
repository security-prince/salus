require 'open3'

module Salus::Scanners
  # Super class for all scanner objects.
  class Base
    class UnhandledExitStatusError < StandardError; end
    class InvalidScannerInvocationError < StandardError; end

    ShellResult = Struct.new(:stdout, :stderr, :exit_status)

    def initialize(repository:, scan_report:, config:)
      @repository = repository
      @scan_report = scan_report
      @config = config
    end

    def name
      self.class.name.sub('Salus::Scanners::', '')
    end

    # The scanning logic or something that calls a scanner.
    def run
      raise NoMethodError
    end

    # Returns TRUE if this scanner is appropriate for this repo, ELSE false.
    def should_run?
      raise NoMethodError
    end

    # Runs a command on the terminal.
    def run_shell(command, env: {}, stdin_data: '')
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = ShellResult.new(*Open3.capture3(env, *command, stdin_data: stdin_data))
      elapsed_time = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at).round(2)

      log(
        "Ran `#{command}`; " \
        "finished in #{elapsed_time}s with exit code #{result.exit_status.exitstatus}",
        verbose: true
      )

      result
    end

    def log(string, verbose: false)
      @scan_report.log(string, verbose: verbose)
    end

    # Add a log to the report that this scanner had no findings.
    def report_success
      @scan_report.pass
    end

    # Add a log to the report that this scanner had findings.
    def report_failure
      @scan_report.fail
    end

    # Report information about this scan.
    def report_info(type, message)
      @scan_report.info(type, message)
    end

    # Report the STDOUT from the scanner.
    def report_stdout(stdout)
      @scan_report.info(:stdout, stdout)
    end

    # Report the STDERR from the scanner.
    def report_stderr(stderr)
      @scan_report.info(:stderr, stderr)
    end

    # Report an error in a scanner.
    def report_error(message)
      @scan_report.error(message: message)
    end

    def record_dependency_info(info, dependency_file)
      @scan_report.info('dependency', { dependency_file: dependency_file }.merge(info))
    end
  end
end
