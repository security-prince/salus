require_relative 'color'
require 'json'

module Salus
  class ScanReport
    include Color

    attr_reader :scanner_name

    def initialize(scanner_name)
      @scanner_name = scanner_name

      @started_at = nil
      @finished_at = nil

      @passed = nil
      @logs = []
      @info = {}
      @errors = []
    end

    def start
      @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def running_time
      @started_at && @finished_at && (@finished_at - @started_at).round(2)
    end

    def pass
      @passed = true
      @finished_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def fail
      @passed = false
      @finished_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def passed?
      @passed == true
    end

    def failed?
      @passed == false
    end

    def finished?
      !@finished_at.nil?
    end

    def log(string, verbose: false, color: nil, newline: true)
      string += "\n" if newline
      @logs << [string, verbose, color]
    end

    def info(type, value)
      @info[type] ||= []
      @info[type] << value
    end

    def error(message, hsh = {})
      hsh[:message] = message
      @errors << hsh
    end

    def to_s(verbose: false, use_colors: true, wrap: nil)
      banner = render_banner(use_colors: use_colors)

      # If the scan succeeded and verbose is false, just output the banner
      # indicating pass/fail
      return banner if @passed && !verbose

      # Correct the wrap by, because apply it only to indented paragraphs
      wrap = (wrap.nil? ? nil : wrap - 2)

      output = banner

      logs = render_logs(
        verbose: verbose,
        use_colors: use_colors,
        wrap: wrap
      )
      output += "\n\n ~~ Scan Logs:\n\n#{indent(logs)}" if !logs.empty?

      if !@info.empty? && verbose
        stringified_info = indent(wrapify(JSON.pretty_generate(@info), wrap))
        output += "\n\n ~~ Metadata:\n\n#{stringified_info}"
      end

      if !@errors.empty?
        stringified_errors = indent(wrapify(JSON.pretty_generate(@errors), wrap))
        output += "\n\n ~~ Errors:\n\n#{stringified_errors}"
      end

      output
    end

    def to_h
      {
        passed: @passed,
        running_time: running_time,
        info: @info,
        logs: render_logs(verbose: false, use_colors: false, wrap: nil)
      }.compact
    end

    private

    def render_banner(use_colors:)
      description = @passed ? 'PASSED' : 'FAILED'
      description = colorize(description, (@passed ? :green : :red)) if use_colors

      banner = "==== #{@scanner_name}: #{description}"
      banner += " in #{running_time}s" if running_time
      banner
    end

    def render_logs(verbose:, use_colors:, wrap:)
      # If wrap is nil (ie. if no wrapping is to be done),
      # just set it to a huge number
      wrap ||= 1 << 30

      # If verbose is true, include all logs;
      # if verbose is false, filter any logs that were marked as being verbose
      logs = verbose ? @logs : @logs.reject { |_, log_verbose, _| log_verbose }

      # Remove the now-useless verbose flag, and also nil out all colors
      # if use_colors is false
      logs = logs.map do |string, _, color|
        color = nil unless use_colors
        [string, color]
      end

      # The logic is a bit more complex if we need to wrap, because wrapping
      # can potentially break the color escape sequences

      output_lines = ['']

      logs.each do |string, color|
        # each_line yields each line of the string, including any trailing linefeed
        string.each_line("\n") do |logline|
          trailing_linefeed = logline.chomp!

          # If we can fit the entirety of logline onto the current output line,
          # do so; otherwise, fit as much as possible of logline onto the
          # current output line, then spread the rest across as many new output
          # lines as necessary

          if output_lines[-1].length + logline.length <= wrap
            output_lines[-1] += colorize(logline, color)
          else
            index = wrap - output_lines[-1].length

            output_lines[-1] += colorize(logline[(0...index)], color: color)

            while index <= logline.length
              lines << logline.slice(index, wrap)
              index += wrap
            end
          end

          # Start a new line iff the given line ended in a linefeed
          output_lines << '' if trailing_linefeed
        end
      end

      output_lines.join("\n").chomp
    end

    def indent(string)
      string.each_line("\n").map { |line| line == "\n" ? "\n" : ('  ' + line) }.join
    end

    def wrapify(string, wrap)
      return string if wrap.nil?

      wrapped_lines = []

      string.each_line("\n").each do |line|
        index = 0
        while index < line.length
          wrapped_lines << line.slice(index, wrap)
          index += wrap
        end
      end

      wrapped_lines
    end
  end
end
