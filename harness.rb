require_relative 'lib/salus/scan_report.rb'

scan_report = Salus::ScanReport.new('NPMAudit')

scan_report.start

5.times do
  scan_report.log('This is green text', color: :green)
  scan_report.log('This is yellow text', color: :yellow)
  scan_report.log('This is red text', color: :red)
end

10.times do
  scan_report.info('lemurs', rand)
  scan_report.info('ocelots', rand)
end

3.times do
  scan_report.error('lemurs are loose', count: (rand * 1000).to_i)
end

scan_report.pass

puts(scan_report.to_s(verbose: true))
puts(scan_report.to_h)
