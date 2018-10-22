require 'faraday'
require 'json'

module Salus
  class Report
    class ExportReportError < StandardError; end

    # FIXME(as3richa): make wrapping behaviour configurable
    WRAP = 100

    NUM_CHAR_IN_BAR = 20
    BAR = ('=' * NUM_CHAR_IN_BAR).freeze
    SPECIAL_BAR = ('#' * NUM_CHAR_IN_BAR).freeze

    CONTENT_TYPE_FOR_FORMAT = {
      'json' => 'application/json',
      'yaml' => 'text/x-yaml',
      'txt'  => 'text/plain'
    }.freeze

    def initialize(report_uris: [], project_name: '', custom_info: '')
      @report_uris = report_uris   # where we will send this report
      @project_name = project_name # the project_name we are scanning
      @scan_reports = []           # ScanReports for each scan run
      @errors = []                 # errors from Salus execution
      @custom_info = custom_info   # some additional info to send
      @configuration = {}          # the configuration for this run
    end

    def passed?
      @scan_reports.all? { |scan_report, required| !required || scan_report.passed? }
    end

    def add_scan_report(scan_report, required:)
      @scan_reports << [scan_report, required]
    end

    def salus_runtime_error(hsh)
      @errors << hsh
    end

    def configuration_source(source)
      @configuration['sources'] ||= []
      @configuration['sources'] << source
    end

    def configuration_directive(directive, value)
      @configuration[directive] = value
    end

    def to_h
      scans_to_h = @scan_reports.map { |report| [report.scanner_name, report.to_h] }.to_h

      {
        version: VERSION,
        project_name: @project_name,
        passed: passed?,
        scans: scans_to_h,
        info: @info,
        errors: collect_errors,
        custom_info: @custom_info,
        configuration: @configuration
      }
    end

    def to_json
      JSON.pretty_generate(to_h)
    end

    # Generates the text report.
    def to_s(verbose: false)
      lines = []
      lines << "#{SPECIAL_BAR} Salus Scan v#{VERSION} for #{@project_name} #{SPECIAL_BAR}"

      # Sort scan reports required before optional, failed before passed,
      # and alphabetically by scanner name
      scan_reports = @scan_reports.sort_by do |report, required|
        [
          required ? 0 : 1,
          report.passed? ? 1 : 0,
          report.scanner_name
        ]
      end

      scan_reports.each do |report, _required|
        lines << "\n"
        lines << report.to_s(verbose: verbose, wrap: WRAP)
      end

      # Only add configuration if verbose mode is on.
      if verbose
        lines << "\n"
        lines << "#{BAR} Salus Configuration #{BAR}\n"
        lines << indent(YAML.dump(@configuration))
      end

      if !@errors.empty?
        lines << "\n"
        lines << "#{BAR} Salus Errors #{BAR}\n"
        lines << indent(JSON.pretty_generate(@errors))
      end

      lines.map { |line| wrap(line) }.join("\n")
    end

    def to_yaml
      YAML.dump(to_h)
    end

    # Send the report to given URIs (which could be remove or local).
    def export_report
      @report_uris.each do |directive|
        # First create the string for the report.
        uri = directive['uri']
        verbose = directive['verbose'] || false
        report_string = case directive['format']
                        when 'txt' then to_s(verbose: verbose)
                        when 'json' then to_json
                        when 'yaml' then to_yaml
                        else
                          raise ExportReportError, "unknown report format #{directive['format']}"
                        end

        # Now send this string to its destination.
        if Salus::Config::REMOTE_URI_SCHEME_REGEX.match?(URI(uri).scheme)
          send_report(uri, report_string, directive['format'])
        else
          # must remove the file:// schema portion of the uri.
          uri_object = URI(uri)
          file_path = "#{uri_object.host}#{uri_object.path}"
          write_report_to_file(file_path, report_string)
        end
      end
    end

    private

    def wrap(text)
      text.gsub(/(.{1,#{WRAP}})/, "\\1\n")
    end

    def indent(text)
      # each_line("\n") rather than split("\n") because the latter
      # discards trailing empty lines. Also, don't indent empty lines
      text.each_line("\n").map { |line| line == "\n" ? "\n" : ("\t" + line) }.join
    end

    def write_report_to_file(report_file_path, report_string)
      File.open(report_file_path, 'w') { |file| file.write(report_string) }
    rescue SystemCallError => e
      raise ExportReportError,
            "Cannot write file #{report_file_path} - #{e.class}: #{e.message}"
    end

    def send_report(remote_uri, data, format)
      response = Faraday.post do |req|
        req.url remote_uri
        req.headers['Content-Type'] = CONTENT_TYPE_FOR_FORMAT[format]
        req.body = data
      end

      unless response.success?
        raise ExportReportError,
              "POST of Salus report to #{remote_uri} had response status #{response.status}."
      end
    end
  end
end
