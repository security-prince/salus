require_relative 'lib/salus/table.rb'

include Salus::Table

def randi(n)
  (rand * n).to_i
end

headers = %w[Foo Bar Baz Derp]

table = (0...10).map do
  [
    'a' * randi(10),
    'b' * randi(10),
    'c' * randi(10),
    'd' * randi(10)
  ]
end

puts tabulate(headers, table)
