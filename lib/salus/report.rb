require 'faraday'
require 'json'
require_relative 'color'
require_relative 'table'

module Salus
  class Report
    include Color
    include Table

    class ExportReportError < StandardError; end

    NUM_CHAR_IN_BAR = 20
    BAR = ('=' * NUM_CHAR_IN_BAR).freeze
    SPECIAL_BAR = ('#' * NUM_CHAR_IN_BAR).freeze

    CONTENT_TYPE_FOR_FORMAT = {
      'json' => 'application/json',
      'yaml' => 'text/x-yaml',
      'txt'  => 'text/plain'
    }.freeze

    def initialize(report_uris: [], enforced_scanners: [], project_name: '', custom_info: '')
      @report_uris = report_uris   # where we will send this report
      @enforced_scanners = enforced_scanners.to_a
      @project_name = project_name # the project_name we are scanning
      @scan_reports = {}
      @errors = {}
      @custom_info = custom_info   # some additional info to send
      @configuration = {}          # the configuration for this run
    end

    def add_scan_report(scan_report)
      @scan_reports[scan_report.scanner_name] = scan_report
    end

    def salus_runtime_error(error_data)
      salus_error('Salus', error_data)
    end

    # Record a list of any errors that Salus encounters.
    # These might be Salus code or from scanners.
    def salus_error(error_origin, error_data)
      # If we have a bugsnag api key and we're not running tests
      if ENV['BUGSNAG_API_KEY'] && !ENV['RUNNING_SALUS_TESTS']
        Bugsnag.notify([error_origin, error_data])
      end

      @errors[error_origin] ||= []
      @errors[error_origin] << error_data
    end

    def configuration_source(source)
      @configuration['sources'] ||= []
      @configuration['sources'] << source
    end

    def configuration_directive(directive, value)
      @configuration[directive] = value
    end

    def failed?
      @scan_reports.any? do |scanner_name, scan_report|
        @enforced_scanners.include?(scanner_name) && scan_report.failed?
      end
    end

    def passed?
      !failed?
    end

    def to_h
      scan_reports_hsh =
        @scan_reports
          .map { |scanner_name, scan_report| [scanner_name, scan_report.to_h] }
          .to_h

      {
        salus_version: VERSION,
        project_name:  @project_name,
        passed:        passed?,
        scans:         scan_reports_hsh,
        errors:        @errors,
        custom_info:   @custom_info,
        configuration: @configuration
      }
    end

    def to_json
      JSON.pretty_generate(to_h)
    end

    # Generates the text report.
    def to_s(verbose: false, use_colors: true, wrap: nil)
      output = "#{SPECIAL_BAR} Salus Scan v#{VERSION} for #{@project_name} #{SPECIAL_BAR}"

      description = passed? ? 'PASSED' : 'FAILED'
      description = colorize(description, (passed? ? :green : :red)) if use_colors
      output += "\n\nScan result: #{description}"

      if !@scan_reports.empty?
        # Sort scans:
        # - enforced before unenforced
        # - failed before passed
        # - alphabetically by name
        scan_reports = @scan_reports.values.sort_by do |scan_report|
          [
            @enforced_scanners.include?(scan_report.scanner_name) ? 0 : 1,
            (scan_report.failed? ? 0 : 1),
            scan_report.scanner_name
          ]
        end

        # Build a summary table of all run scans
        table = scan_reports.map do |scan_report|
          required = @enforced_scanners.include?(scan_report.scanner_name)

          color =
            if scan_report.passed?
              :green
            elsif !required
              :yellow
            else
              :red
            end

          row = [
            scan_report.scanner_name,
            "#{scan_report.running_time}s",
            @enforced_scanners.include?(scan_report.scanner_name) ? 'yes' : 'no',
            scan_report.passed? ? 'yes' : 'no'
          ]

          row = row.map { |string| colorize(string, color) } if use_colors
          row
        end

        tabulated_scan_results = tabulate(
          ['Scanner', 'Running Time', 'Required', 'Passed'],
          table
        )

        output += "\n\n#{tabulated_scan_results}"

        scan_reports.each do |scan_report|
          next if scan_report.passed? && !verbose

          output += "\n\n"
          output += scan_report.to_s(
            verbose: verbose,
            use_colors: use_colors,
            wrap: wrap
          )
        end
      end

      output
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
