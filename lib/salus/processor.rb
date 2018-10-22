require 'uri'
require 'salus/report'

module Salus
  class Processor
    class InvalidConfigSourceError < StandardError; end

    attr_reader :config, :report

    DEFAULT_CONFIG_SOURCE = "file:///salus.yaml".freeze

    def initialize(configuration_sources = [], repo_path: DEFAULT_REPO_PATH)
      @repo_path = repo_path

      # Add default file path to the configs if empty.
      configuration_sources << DEFAULT_CONFIG_SOURCE if configuration_sources.empty?

      # Import each config file in order.
      files = configuration_sources.map { |source| fetch_config_file(source, repo_path) }

      # Compact to account for the cases where fetching the config file gave nil.
      @config = Salus::Config.new(files.compact)

      report_uris = interpolate_local_report_uris(@config.report_uris)

      @report = Report.new(
        report_uris: report_uris,
        project_name: @config.project_name,
        custom_info: @config.custom_info
      )

      # Add configurations + sources to report - this is very useful for debugging.
      configuration_sources.each { |source| @report.configuration_source(source) }
      @report.configuration_directive('active_scanners', @config.active_scanners.to_a)
      @report.configuration_directive('enforced_scanners', @config.enforced_scanners.to_a)
      @report.configuration_directive('scanner_configs', @config.scanner_configs)
      @report.configuration_directive('reports', @config.report_uris)
    end

    def fetch_config_file(source_uri, repo_path)
      uri = URI(source_uri)

      case uri.scheme
      when Salus::Config::LOCAL_FILE_SCHEME_REGEX
        location = "#{repo_path}/#{uri.host}#{uri.path}"
        File.read(location) if Dir[location].any?
      when Salus::Config::REMOTE_URI_SCHEME_REGEX
        Faraday.get(source_uri).body
      else
        raise InvalidConfigSourceError, 'Unknown config file source.'
      end
    end

    def scan_project
      repository = Repo.new(@repo_path)

      Config::SCANNERS.each do |scanner_name, scanner_class|
        scanner = scanner_class.new(
          repository: repository,
          config: @config.scanner_configs.fetch(scanner_name, {})
        )

        next unless @config.scanner_active?(scanner_name) && scanner.should_run?

        scan_report = scanner.report
        required = @config.enforced_scanners.include?(scanner_name)

        @report.add_scan_report(scan_report, required: required)

        begin
          scan_report.record { scanner.run }
        rescue StandardError => e
          # We rescue any failure (and report them) to allow the other scanners to run.
          raise e if ENV['RUNNING_SALUS_TESTS']

          @report.salus_runtime_error(
            type: e.class.name,
            message: e.message,
            location: e.backtrace.first
          )
        end
      end
    end

    # Returns an ASCII version of the report.
    def string_report(verbose: false)
      @report.to_s(verbose: verbose)
    end

    # Sends to the report to configured report URIs.
    def export_report
      @report.export_report
    end

    # Returns the hash version of the report.
    def report_hash
      @report.to_h
    end

    # Returns true is the scan succeeded.
    def passed?
      @report.passed?
    end

    private

    # If the URI is local, we will need to prepend the repo_path since
    # the report URI is relative to the root of the repo. This allows us
    # to print reports to a location outside of Salus's docker container.
    def interpolate_local_report_uris(report_directives)
      report_directives.map do |report_uri|
        uri_object = URI(report_uri['uri'])
        scheme = URI(report_uri['uri']).scheme
        file_path = "#{uri_object.host}#{uri_object.path}"

        if Salus::Config::LOCAL_FILE_SCHEME_REGEX.match?(scheme)
          report_uri['uri'] = "file://#{File.join(@repo_path, file_path)}"
        end

        report_uri
      end
    end
  end
end
